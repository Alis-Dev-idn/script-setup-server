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

# ---------- Spinner / loading ----------
# run_with_spinner <pesan> <command...>
# Jalankan command sambil menampilkan spinner. Output (stdout+stderr) command
# ditangkap dan ditampilkan ke STDOUT setelah selesai; animasi spinner ditulis ke
# STDERR. Dengan begitu pemanggil bisa menyembunyikan output (mis. `... >/dev/null`)
# tanpa mematikan spinner. Mengembalikan exit code asli command.
run_with_spinner() {
    local msg="$1"; shift
    local tmp; tmp="$(mktemp 2>/dev/null || echo "/tmp/spin.$$")"

    # Fallback bila stderr bukan TTY: tanpa animasi
    if [[ ! -t 2 ]]; then
        echo -e "   ${CYAN}${msg}${NC}" >&2
        "$@" >"$tmp" 2>&1
        local rc=$?
        cat "$tmp"; rm -f "$tmp"
        return $rc
    fi

    "$@" >"$tmp" 2>&1 &
    local pid=$!
    local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    printf '\033[?25l' >&2                      # sembunyikan kursor
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i + 1) % ${#frames} ))
        printf "\r   ${CYAN}%s${NC} %s" "${frames:$i:1}" "$msg" >&2
        sleep 0.1
    done
    wait "$pid"; local rc=$?
    printf '\r\033[K\033[?25h' >&2              # bersihkan baris & tampilkan kursor
    cat "$tmp"; rm -f "$tmp"
    return $rc
}
