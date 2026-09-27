# chay_chatcmd.ps1
# Script khoi chay va kiem tra trang thai ChatCMD - Biet ngay PASS hay FAIL

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$tep_exe = "C:\Tools\ChatCMD-windows-x64\ChatCMD.exe"
$tm_chay = "C:\Tools\ChatCMD-windows-x64"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "         CHATCMD - KHOI CHAY VA HEALTH CHECK SERVICE            " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

if (-not (Test-Path $tep_exe)) {
    Write-Host "[FAIL] Khong tim thay file thuc thi: $tep_exe" -ForegroundColor Red
    exit 1
}

# 1. Kiem tra tien trinh hien tai
$proc = Get-Process -Name ChatCMD -ErrorAction SilentlyContinue
if ($proc) {
    Write-Host "[*] Tien trinh ChatCMD da dang chay (PID: $($proc.Id)). Dang khoi dong lai..." -ForegroundColor Yellow
    $proc | Stop-Process -Force
    Start-Sleep -Milliseconds 600
}

# 2. Khoi chay tien trinh moi (tach biet khoi Job Object bang WMI)
Write-Host "[*] Dang khoi chay $tep_exe..." -ForegroundColor Yellow
try {
    $res = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
        CommandLine = "`"$tep_exe`""
        CurrentDirectory = $tm_chay
    }
} catch {
    Start-Process -FilePath $tep_exe -WorkingDirectory $tm_chay -WindowStyle Hidden
}

# 3. Cho va xac nhan tien trinh khoi tao
$da_chay = $false
$pid_moi = 0
for ($i = 0; $i -lt 6; $i++) {
    Start-Sleep -Milliseconds 500
    $proc_moi = Get-Process -Name ChatCMD -ErrorAction SilentlyContinue
    if ($proc_moi) {
        $da_chay = $true
        $pid_moi = $proc_moi.Id
        break
    }
}

if (-not $da_chay) {
    Write-Host "[FAIL] Tien trinh ChatCMD khong the khoi dong hoac da thoat som!" -ForegroundColor Red
    exit 1
}
Write-Host "[PASS] 1. Tien trinh da chay voi PID: $pid_moi" -ForegroundColor Green

# 4. Kiem tra cong mang 8080 (Health Check)
$cong_mo = $false
for ($i = 0; $i -lt 10; $i++) {
    Start-Sleep -Milliseconds 500
    try {
        $tcp = Test-NetConnection -ComputerName 127.0.0.1 -Port 8080 -WarningAction SilentlyContinue
        if ($tcp.TcpTestSucceeded) {
            $cong_mo = $true
            break
        }
    } catch {}
}

if ($cong_mo) {
    try {
        $phan_hoi = Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:8080/api/info' -TimeoutSec 5
        if ($phan_hoi.StatusCode -ne 200) { throw "HTTP $($phan_hoi.StatusCode)" }
    } catch {
        Write-Host "[FAIL] /api/info khong san sang: $_" -ForegroundColor Red
        exit 1
    }
    Write-Host "[PASS] 2. /api/info tra HTTP 200." -ForegroundColor Green
    Write-Host "`n================================================================" -ForegroundColor Cyan
    Write-Host ">>> KET LUAN: CHATCMD SERVICE [PASS] (DANG CHAY ON DINH) <<<" -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Cyan
    exit 0
} else {
    Write-Host "[FAIL] Cong 8080 chua phan hoi trong 5 giay (tien trinh PID $pid_moi van dang chay)." -ForegroundColor Red
    exit 1
}
