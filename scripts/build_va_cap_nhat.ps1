# build_va_cap_nhat.ps1
# Script build ban release standalone va cap nhat ChatCMD.exe - Biet ngay PASS hay FAIL

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$tm_goc = Split-Path -Parent $PSScriptRoot
Set-Location $tm_goc

$tep_dich = "C:\Tools\ChatCMD-windows-x64\ChatCMD.exe"
$tep_nguon = Join-Path $tm_goc "target\release\chat-cmd-client.exe"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "     CHATCMD - BIEN DICH VA CAP NHAT RELEASE EXECUTABLE         " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# 1. Kiem tra thu muc web/dist
$tep_web = Join-Path $tm_goc "web\dist\index.html"
if (-not (Test-Path $tep_web)) {
    Write-Host "[*] Web dist chua co san. Dang build frontend web..." -ForegroundColor Yellow
    Push-Location (Join-Path $tm_goc "web")
    try {
        npm run build
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[FAIL] Build web frontend that bai!" -ForegroundColor Red
            exit 1
        }
    } finally {
        Pop-Location
    }
}
Write-Host "[PASS] 1. Frontend web/dist san sang." -ForegroundColor Green

# 2. Bien dich Rust Release binary voi embedded-web
Write-Host "[*] 2. Dang bien dich Rust release (embedded-web)..." -ForegroundColor Yellow
$bat_dau = Get-Date
cargo build --release --features embedded-web --bin chat-cmd-client 2>&1 | Out-Null
$ma_thoat = $LASTEXITCODE
$thoi_gian = [math]::Round(((Get-Date) - $bat_dau).TotalSeconds, 2)

if ($ma_thoat -ne 0 -or -not (Test-Path $tep_nguon)) {
    Write-Host "[FAIL] 2. Bien dich Rust that bai (ma loi: $ma_thoat)!" -ForegroundColor Red
    exit 1
}
$thong_tin_nguon = Get-Item $tep_nguon
$mb_nguon = [math]::Round($thong_tin_nguon.Length / 1MB, 2)
Write-Host "[PASS] 2. Bien dich Rust thanh cong (${thoi_gian}s, dung luong: ${mb_nguon} MB)." -ForegroundColor Green

# 3. Dung tien trinh cu neu dang chay
$proc = Get-Process -Name ChatCMD -ErrorAction SilentlyContinue
if ($proc) {
    Write-Host "[*] 3. Dang dung tien trinh ChatCMD cu (PID: $($proc.Id))..." -ForegroundColor Yellow
    $proc | Stop-Process -Force
    Start-Sleep -Milliseconds 500
}
Write-Host "[PASS] 3. Da giai phong tien trinh." -ForegroundColor Green

# 4. Sao chep binary sang thu muc dich C:\Tools\ChatCMD-windows-x64\ChatCMD.exe
try {
    Copy-Item -Path $tep_nguon -Destination $tep_dich -Force
    $thong_tin_dich = Get-Item $tep_dich
    $mb_dich = [math]::Round($thong_tin_dich.Length / 1MB, 2)
    $thoi_diem = $thong_tin_dich.LastWriteTime.ToString("HH:mm:ss dd/MM/yyyy")
    Write-Host "[PASS] 4. Da cap nhat sang $tep_dich" -ForegroundColor Green
    Write-Host "   * Dung luong: ${mb_dich} MB" -ForegroundColor Gray
    Write-Host "   * Thoi diem : $thoi_diem" -ForegroundColor Gray
} catch {
    Write-Host "[FAIL] 4. Khong the sao chep sang ${tep_dich}: $_" -ForegroundColor Red
    exit 1
}

Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host ">>> KET LUAN: BUILD VA CAP NHAT RELEASE [PASS] (THANH CONG) <<<" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Cyan
exit 0
