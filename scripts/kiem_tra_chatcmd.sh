#!/usr/bin/env bash
# kiem_tra_chatcmd.sh
# Script Bash kiem thu toan dien ChatCMD - Chay tot tren Git Bash, WSL, Linux va macOS

set -u

# 1. Mau sac hien thi truc quan tren terminal
XANH='\033[0;32m'
DO='\033[0;31m'
VANG='\033[1;33m'
CYAN='\033[0;36m'
XAM='\033[0;90m'
RESET='\033[0m'

# 2. Xac dinh thu muc goc cua du an
TM_GOC="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TM_GOC"

printf "${CYAN}================================================================${RESET}\n"
printf "${CYAN}    CHATCMD - BO KIEM THU TOAN DIEN HE THONG (BASH RUNNER)     ${RESET}\n"
printf "${CYAN}================================================================${RESET}\n"
printf "${XAM}Thu muc du an: %s${RESET}\n\n" "$TM_GOC"

# 3. Khoi tao bien dem so bai test PASS va FAIL
dem_pass=0
dem_fail=0

# 4. Ham chay kiem tra chuan hoa
chay_kiem_tra() {
    local ten_buoc="$1"
    shift
    local lenh_chay=("$@")

    printf "${VANG}[*] Dang chay: %s...${RESET}" "$ten_buoc"
    local bat_dau
    bat_dau=$(date +%s)

    # Thuc thi lenh va bat output
    local out
    if out=$("${lenh_chay[@]}" 2>&1); then
        local ket_thuc
        ket_thuc=$(date +%s)
        local thoi_gian=$((ket_thuc - bat_dau))
        printf "\r${XANH}[PASS] %s (%ss)${RESET}\n" "$ten_buoc" "$thoi_gian"
        dem_pass=$((dem_pass + 1))
    else
        local ket_thuc
        ket_thuc=$(date +%s)
        local thoi_gian=$((ket_thuc - bat_dau))
        printf "\r${DO}[FAIL] %s (%ss)${RESET}\n" "$ten_buoc" "$thoi_gian"
        printf "${DO}   * Loi: %s${RESET}\n" "$(echo "$out" | tail -n 3)"
        dem_fail=$((dem_fail + 1))
    fi
}

# 5. Chay lan luot cac bai test cot loi
chay_kiem_tra "1. Bien dich Workspace (cargo check)" cargo check --workspace
chay_kiem_tra "2. Kiem tra Skill Service (Find Skills 4 cap & YAML)" cargo test -p chatcmd-runtime --lib skill_service
chay_kiem_tra "3. Kiem tra MCP Protocol (Contract, Tools & Schemas)" cargo test -p chatcmd-mcp --lib
chay_kiem_tra "4. Kiem tra Storage (SQL Migrations LF & Checksum)" cargo test -p chatcmd-storage --test plan_question_migration
chay_kiem_tra "5. Kiem tra Git Commit Scope (Windows Scope & Lock)" cargo test -p chatcmd-runtime --test git_commit_scope
chay_kiem_tra "6. Do luong Payload Find Skills (Giam 97.3% token)" python scripts/kiem_tra_skills_va_context.py

# 6. Tong ket ket qua
printf "\n${CYAN}================================================================${RESET}\n"
printf "${CYAN}                    BANG TONG KET KET QUA                       ${RESET}\n"
printf "${CYAN}================================================================${RESET}\n"

if [ "$dem_fail" -eq 0 ]; then
    printf "${XANH}>>> KET LUAN: TOAN BO %d/%d HANG MUC DEU [PASS] (XANH 100%%) <<<${RESET}\n\n" "$dem_pass" "$dem_pass"
    exit 0
else
    printf "${DO}>>> KET LUAN: CO %d HANG MUC [FAIL]! VUI LONG KIEM TRA CHI TIET <<<${RESET}\n\n" "$dem_fail"
    exit 1
fi
