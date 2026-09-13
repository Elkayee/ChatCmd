# kiem_tra_chatcmd.ps1
# Script kiem tra toan dien chatcmd - Chi can nhin la biet PASS hay FAIL

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$tm_goc = Split-Path -Parent $PSScriptRoot
Set-Location $tm_goc

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "    CHATCMD - BO KIEM THU TOAN DIEN HE THONG (TEST RUNNER)     " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "Thu muc du an: $tm_goc`n" -ForegroundColor Gray

$ds_kq = @()
$dem_pass = 0
$dem_fail = 0

function Chay-Kiem-Tra {
    param(
        [string]$TenBuoc,
        [scriptblock]$LenhChay
    )
    Write-Host "[*] Dang chay: $TenBuoc..." -ForegroundColor Yellow -NoNewline
    $bat_dau = Get-Date
    
    $out = & $LenhChay 2>&1
    $ma_thoat = $LASTEXITCODE
    $thoi_gian = [math]::Round(((Get-Date) - $bat_dau).TotalSeconds, 2)
    
    if ($ma_thoat -eq 0) {
        Write-Host "`r[PASS] $TenBuoc (${thoi_gian}s)" -ForegroundColor Green
        $script:dem_pass++
        $script:ds_kq += [PSCustomObject]@{
            HangMuc = $TenBuoc
            KetQua = "PASS"
            ThoiGian = "${thoi_gian}s"
            ChiTiet = "Thanh cong"
        }
    } else {
        Write-Host "`r[FAIL] $TenBuoc (${thoi_gian}s)" -ForegroundColor Red
        $script:dem_fail++
        $script:ds_kq += [PSCustomObject]@{
            HangMuc = $TenBuoc
            KetQua = "FAIL"
            ThoiGian = "${thoi_gian}s"
            ChiTiet = ($out | Select-Object -Last 3) -join " "
        }
    }
}

# 1. Kiem tra bien dich toan bo workspace
Chay-Kiem-Tra "1. Bien dich Workspace (cargo check)" {
    cargo check --workspace
}

# 2. Kiem tra Skill Service & thuat toan Find Skills
Chay-Kiem-Tra "2. Kiem tra Skill Service (Find Skills 4 cap do & YAML parse)" {
    cargo test -p chatcmd-runtime --lib skill_service
}

# 3. Kiem tra giao thuc MCP & Catalog
Chay-Kiem-Tra "3. Kiem tra MCP Protocol (Contract, Tools & Schemas)" {
    cargo test -p chatcmd-mcp --lib
}

# 4. Kiem tra Storage & Migrations LF
Chay-Kiem-Tra "4. Kiem tra Storage (SQL Migrations LF & Checksum)" {
    cargo test -p chatcmd-storage --test plan_question_migration
}

# 5. Kiem tra Git Commit Scope
Chay-Kiem-Tra "5. Kiem tra Git Commit Scope (Windows Scope & Lock)" {
    cargo test -p chatcmd-runtime --test git_commit_scope
}

# 6. Kiem tra Thuc te Find Skills & Giam Payload 97%
Chay-Kiem-Tra "6. Do luong Payload Find Skills (Giam 97.3% token)" {
    python (Join-Path $tm_goc "scripts/kiem_tra_skills_va_context.py")
}

Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "                    BANG TONG KET KET QUA                       " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

$ds_kq | Format-Table -AutoSize HangMuc, KetQua, ThoiGian

if ($dem_fail -eq 0) {
    Write-Host ">>> KET LUAN: TOAN BO $dem_pass/$dem_pass HANG MUC DEU [PASS] (XANH 100%) <<<`n" -ForegroundColor Green
    exit 0
} else {
    Write-Host ">>> KET LUAN: CO $dem_fail HANG MUC [FAIL]! VUI LONG KIEM TRA CHI TIET <<<`n" -ForegroundColor Red
    exit 1
}
