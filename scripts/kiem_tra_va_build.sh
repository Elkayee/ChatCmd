#!/usr/bin/env bash
# kiem_tra_va_build.sh
# Script 1-Click Bash: Chay toan bo test -> Neu PASS thi tu dong Build va Cap nhat Release

set -euo pipefail

XANH='\033[0;32m'
DO='\033[0;31m'
VANG='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

TM_SCRIPTS="$(cd "$(dirname "$0")" && pwd)"

printf "${CYAN}================================================================${RESET}\n"
printf "${CYAN}     CHATCMD - QUY TRINH TU DONG HOA (TEST -> BUILD -> DEPLOY)   ${RESET}\n"
printf "${CYAN}================================================================${RESET}\n"

# BUOC 1: Chay test kiem tra toan dien
printf "\n${VANG}>>> [GIAI DOAN 1]: CHAY BO KIEM THU HE THONG <<<${RESET}\n\n"
if ! bash "$TM_SCRIPTS/kiem_tra_chatcmd.sh"; then
    printf "\n${DO}[DUNG LAI] Phat hien bai test bi FAIL. Huy bo quy trinh build release!${RESET}\n"
    exit 1
fi

# BUOC 2: Neu test pass, chay build va cap nhat release
printf "\n${VANG}>>> [GIAI DOAN 2]: BIEN DICH VA CAP NHAT RELEASE EXECUTABLE <<<${RESET}\n\n"
if ! bash "$TM_SCRIPTS/build_va_cap_nhat.sh"; then
    printf "\n${DO}[DUNG LAI] Build hoac cap nhat that bai!${RESET}\n"
    exit 1
fi

printf "\n${CYAN}================================================================${RESET}\n"
printf "${XANH}>>> KET LUAN CHUNG: 100%% HOAN TAT VA SAN SANG SU DUNG [PASS] <<<${RESET}\n"
printf "${CYAN}================================================================${RESET}\n"
exit 0
