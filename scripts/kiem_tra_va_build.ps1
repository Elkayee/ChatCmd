# kiem_tra_va_build.ps1
# Script 1-Click: Chay toan bo test -> Neu PASS thi tu dong Build va Cap nhat Release

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$tm_scripts = $PSScriptRoot

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "     CHATCMD - QUY TRINH TU DONG HOA (TEST -> BUILD -> DEPLOY)   " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# BUOC 1: Chay test kiem tra toan dien
Write-Host "`n>>> [GIAI DOAN 1]: CHAY BO KIEM THU HE THONG <<<`n" -ForegroundColor Yellow
& (Join-Path $tm_scripts "kiem_tra_chatcmd.ps1")
if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[DUNG LAI] Phat hien bai test bi FAIL. Huy bo quy trinh build release!" -ForegroundColor Red
    exit 1
}

# BUOC 2: Neu test pass, chay build va cap nhat release
Write-Host "`n>>> [GIAI DOAN 2]: BIEN DICH VA CAP NHAT RELEASE EXECUTABLE <<<`n" -ForegroundColor Yellow
& (Join-Path $tm_scripts "build_va_cap_nhat.ps1")
if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[DUNG LAI] Build hoac cap nhat that bai!" -ForegroundColor Red
    exit 1
}

Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host ">>> KET LUAN CHUNG: 100% HOAN TAT VA SAN SANG SU DUNG [PASS] <<<" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Cyan
exit 0
