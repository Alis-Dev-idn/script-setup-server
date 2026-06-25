#!/bin/bash
# ============================================================
#  lib/common.sh — Warna, logging & helper umum
#  Di-source oleh modules/* dan setup-server.sh
# ============================================================
# Guard agar tidak di-source dua kali
[[ -n "${_LIB_COMMON_LOADED:-}" ]] && return 0
_LIB_COMMON_LOADED=1

# ---------- Warna ----------
# Nama kanonik + alias agar kompatibel dengan kedua gaya script lama
RED='\033[0;31m'
GREEN='\033[0;32m';  GRN="$GREEN"
YELLOW='\033[1;33m'; YLW="$YELLOW"
BLUE='\033[0;34m'          # gaya setup-hosting (normal)
BLU='\033[1;34m'           # gaya mongodb-manager (bold)
CYAN='\033[0;36m';   CYN="$CYAN"
BLD='\033[1m'
NC='\033[0m'

# ---------- Logging gaya mongodb-manager ----------
info()    { echo -e "${BLU}[INFO]${NC} $*"; }
success() { echo -e "${GRN}[OK]${NC}   $*"; }
warn()    { echo -e "${YLW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*"; }
ask()     { echo -e "${CYN}[?]${NC}    $*"; }
line()    { echo -e "${BLD}──────────────────────────────────────────${NC}"; }
pause()   { echo; read -rp "  Tekan [Enter] untuk kembali ke menu..." _; }

# ---------- Logging gaya setup-hosting ----------
log_ok()   { echo -e "   ${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "   ${YELLOW}[!!]${NC} $1"; }
log_err()  { echo -e "   ${RED}[ERR]${NC} $1"; }
log_info() { echo -e "   ${CYAN}[--]${NC} $1"; }

# ---------- Helper interaktif & path ----------
confirm() {
    read -rp "   ${1:-Lanjutkan?} (y/n): " _ans
    [[ "$_ans" == "y" || "$_ans" == "Y" ]]
}

# Expand ~ dan hapus trailing slash dari path
normalize_path() {
    local p="${1/#\~/$HOME}"
    echo "${p%/}"
}

domain_to_slug() { echo "$1" | tr '.' '_'; }
