param([switch]$Doctor)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configDir = Join-Path $env:LOCALAPPDATA 'ChatCmdClient\openai-tunnel'
$envFile = Join-Path $configDir '.env'
$profileFile = Join-Path $configDir 'profile.yaml'
$logDir = Join-Path $configDir 'logs'
$tunnelExe = Join-Path $configDir 'bin\tunnel-client.exe'
$tunnelVersion = 'v0.0.10'

function Read-EnvFile([string]$Path) {
    $values = @{}
    if (Test-Path $Path) {
        Get-Content $Path | ForEach-Object {
            if ($_ -match '^\s*([^#=]+?)\s*=\s*(.*)\s*$') { $values[$matches[1]] = $matches[2].Trim('"', "'") }
        }
    }
    return $values
}

function Wait-Http([string]$Url, [int]$Attempts = 30) {
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 2
            if ($response.StatusCode -eq 200) { return }
        } catch {}
        Start-Sleep -Milliseconds 500
    }
    throw "Timed out waiting for $Url"
}

function Install-TunnelClient {
    $binDir = Split-Path -Parent $tunnelExe
    $archive = Join-Path $env:TEMP "chatcmd-tunnel-client-$tunnelVersion.zip"
    $url = "https://github.com/openai/tunnel-client/releases/download/$tunnelVersion/tunnel-client-$tunnelVersion-windows-amd64.zip"
    New-Item -ItemType Directory -Force -Path $binDir | Out-Null
    Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing
    Expand-Archive -Path $archive -DestinationPath $binDir -Force
    $found = Get-ChildItem $binDir -Recurse -Filter 'tunnel-client.exe' | Select-Object -First 1
    if (-not $found) { throw 'Downloaded archive did not contain tunnel-client.exe' }
    if ($found.FullName -ne $tunnelExe) { Copy-Item $found.FullName $tunnelExe -Force }
    Remove-Item $archive -Force
}

New-Item -ItemType Directory -Force -Path $configDir, $logDir | Out-Null
if (-not (Test-Path $envFile)) {
    Copy-Item (Join-Path $scriptDir '.env.example') $envFile
    throw "Configure tunnel credentials and CHATCMD_MCP_TOKEN in $envFile"
}
$settings = Read-EnvFile $envFile
foreach ($required in 'OPENAI_TUNNEL_ID', 'OPENAI_TUNNEL_API_KEY', 'CHATCMD_MCP_TOKEN') {
    if ([string]::IsNullOrWhiteSpace($settings[$required])) { throw "$required is required in $envFile" }
}
$chatcmdPort = if ($settings.CHATCMD_PORT) { [int]$settings.CHATCMD_PORT } else { 8080 }
$bridgePort = if ($settings.CHATCMD_BRIDGE_PORT) { [int]$settings.CHATCMD_BRIDGE_PORT } else { 8082 }
$healthPort = if ($settings.OPENAI_TUNNEL_HEALTH_PORT) { [int]$settings.OPENAI_TUNNEL_HEALTH_PORT } else { 8081 }

Wait-Http "http://127.0.0.1:$chatcmdPort/api/health"
$env:CHATCMD_PORT = $chatcmdPort
$env:CHATCMD_BRIDGE_PORT = $bridgePort
$env:CHATCMD_MCP_TOKEN = $settings.CHATCMD_MCP_TOKEN
if (-not (Test-NetConnection 127.0.0.1 -Port $bridgePort -InformationLevel Quiet -WarningAction SilentlyContinue)) {
    Start-Process node -ArgumentList (Join-Path $scriptDir 'bridge.mjs') -WorkingDirectory $scriptDir -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logDir 'bridge.log') -RedirectStandardError (Join-Path $logDir 'bridge-error.log')
}
Wait-Http "http://127.0.0.1:$bridgePort/health"

$headers = @{ Accept = 'application/json, text/event-stream'; 'Content-Type' = 'application/json' }
$body = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"chatcmd-tunnel-doctor","version":"1"}}}'
$initialize = Invoke-WebRequest -Uri "http://127.0.0.1:$bridgePort/mcp" -Method Post -Headers $headers -Body $body -UseBasicParsing -TimeoutSec 5
if ($initialize.StatusCode -ne 200 -or $initialize.Content -notmatch '"result"') { throw 'MCP initialize readiness check failed' }

$template = Get-Content -Raw (Join-Path $scriptDir 'profile.template.yaml')
$profile = $template.Replace('__TUNNEL_ID__', $settings.OPENAI_TUNNEL_ID).Replace('__HEALTH_PORT__', $healthPort).Replace('__BRIDGE_PORT__', $bridgePort)
Set-Content -Path $profileFile -Value $profile -Encoding utf8
$env:OPENAI_TUNNEL_API_KEY = $settings.OPENAI_TUNNEL_API_KEY
$env:CONTROL_PLANE_API_KEY = $settings.OPENAI_TUNNEL_API_KEY
$env:CONTROL_PLANE_TUNNEL_ID = $settings.OPENAI_TUNNEL_ID

if (-not (Test-Path $tunnelExe)) { Install-TunnelClient }
if ($Doctor) {
    & $tunnelExe doctor --profile-file $profileFile --explain
} else {
    & $tunnelExe run --profile-file $profileFile
}
exit $LASTEXITCODE
