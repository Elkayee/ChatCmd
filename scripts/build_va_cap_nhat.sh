#!/usr/bin/env bash
# build_va_cap_nhat.sh
# Script Bash bien dich ban release standalone va cap nhat ChatCMD.exe

set -euo pipefail

# 1. Mau sac hien thi
XANH='\033[0;32m'
DO='\033[0;31m'
VANG='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# 2. Xac dinh thu muc goc va duong dan
TM_GOC="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TM_GOC"

TEP_NGUON="$TM_GOC/target/release/chat-cmd-client.exe"
TEP_DICH="/c/Tools/ChatCMD-windows-x64/ChatCMD.exe"

printf "${CYAN}================================================================${RESET}\n"
printf "${CYAN}     CHATCMD - BIEN DICH VA CAP NHAT RELEASE (BASH)             ${RESET}\n"
printf "${CYAN}================================================================${RESET}\n"

# 3. Kiem tra frontend web/dist
TEP_WEB="$TM_GOC/web/dist/index.html"
if [ ! -f "$TEP_WEB" ]; then
    printf "${VANG}[*] Web dist chua co san. Dang build frontend web...${RESET}\n"
    (cd "$TM_GOC/web" && npm run build)
fi
printf "${XANH}[PASS] 1. Frontend web/dist san sang.${RESET}\n"

# 4. Bien dich Rust Release binary voi embedded-web
printf "${VANG}[*] 2. Dang bien dich Rust release (embedded-web)...${RESET}\n"
bat_dau=$(date +%s)
cargo build --release --features embedded-web --bin chat-cmd-client
ket_thuc=$(date +%s)
thoi_gian=$((ket_thuc - bat_dau))

if [ ! -f "$TEP_NGUON" ]; then
    printf "${DO}[FAIL] 2. Khong tim thay file binary sau khi build!${RESET}\n"
    exit 1
fi
dung_luong=$(du -m "$TEP_NGUON" | cut -f1)
printf "${XANH}[PASS] 2. Bien dich Rust thanh cong (%ss, dung luong: %s MB).${RESET}\n" "$thoi_gian" "$dung_luong"

# 5. Dung tien trinh cu neu dang chay (su dung taskkill tren Windows)
if tasklist //FI "IMAGENAME eq ChatCMD.exe" 2>/dev/null | grep -i "ChatCMD.exe" >/dev/null 2>&1; then
    printf "${VANG}[*] 3. Dang dung tien trinh ChatCMD cu...${RESET}\n"
    taskkill //F //IM ChatCMD.exe >/dev/null 2>&1 || true
    sleep 0.5
fi
printf "${XANH}[PASS] 3. Da giai phong tien trinh.${RESET}\n"

# 6. Sao chep binary sang thu muc thuc thi
cp -f "$TEP_NGUON" "$TEP_DICH"
printf "${XANH}[PASS] 4. Da cap nhat thanh cong sang %s${RESET}\n" "$TEP_DICH"

printf "\n${CYAN}================================================================${RESET}\n"
printf "${XANH}>>> KET LUAN: BUILD VA CAP NHAT RELEASE [PASS] (THANH CONG) <<<${RESET}\n"
printf "${CYAN}================================================================${RESET}\n"
exit 0
