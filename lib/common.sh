#!/bin/bash
# ============================================================
#  lib/common.sh — Logging, helper sistem, prompt, & OS check
#  Di-source oleh seluruh modul dan setup-server.sh
# ============================================================
[[ -n "${_LIB_COMMON_LOADED:-}" ]] && return 0
_LIB_COMMON_LOADED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Load UI styling & modern terminal helpers
if [[ -f "${SCRIPT_DIR}/ui.sh" ]]; then
    # shellcheck source=lib/ui.sh
    source "${SCRIPT_DIR}/ui.sh"
fi

# ---------- Warna Klasik (Backward Compatible) ----------
RED='\033[0;31m'
GREEN='\033[0;32m';  GRN="$GREEN"
YELLOW='\033[1;33m'; YLW="$YELLOW"
BLUE='\033[0;34m'
BLU='\033[1;34m'
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

# ---------- System Guard & OS Compatibility ----------
require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        echo -e "${YELLOW}Akses root dibutuhkan. Menjalankan ulang dengan sudo...${NC}"
        exec sudo bash "$0" "$@"
    fi
}

check_os_compatibility() {
    if [[ ! -f /etc/os-release ]]; then
        echo -e "${RED}[ERROR] Sistem operasi tidak teridentifikasi (/etc/os-release tidak ada).${NC}"
        echo -e "${YELLOW}Target platform skrip ini adalah Linux (Ubuntu/Debian).${NC}"
        return 1
    fi

    local os_id=""
    local os_like=""
    os_id="$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')"
    os_like="$(grep -E '^ID_LIKE=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')"

    if [[ "$os_id" =~ ^(ubuntu|debian)$ || "$os_like" =~ (ubuntu|debian) ]]; then
        return 0
    else
        echo -e "${YELLOW}[PERINGATAN] OS terdeteksi: '${os_id}'. Skrip ini dioptimasi khusus untuk Ubuntu/Debian.${NC}"
        return 0
    fi
}

# ---------- Helper Interaktif & Input ----------
confirm() {
    local prompt_msg="${1:-Lanjutkan?}"
    local ans=""
    read -rp "   ${prompt_msg} (y/n): " ans
    [[ "$ans" == "y" || "$ans" == "Y" ]]
}

prompt_confirm() {
    local prompt_msg="${1:-Apakah Anda yakin?}"
    local ans=""
    read -rp "  ${PRIMARY}${GLYPH_ARROW:-➜}${NC} ${prompt_msg} [y/N]: " ans
    [[ "$ans" =~ ^[yY]([eE][sS])?$ ]]
}

prompt_input() {
    local var_name="$1"
    local prompt_text="$2"
    local default_val="${3:-}"
    local user_val=""

    if [[ -n "$default_val" ]]; then
        read -rp "  ${PRIMARY}${GLYPH_ARROW:-➜}${NC} ${prompt_text} [${default_val}]: " user_val
        user_val="${user_val:-$default_val}"
    else
        read -rp "  ${PRIMARY}${GLYPH_ARROW:-➜}${NC} ${prompt_text}: " user_val
    fi
    eval "$var_name=\"\$user_val\""
}

# Expand ~ dan hapus trailing slash dari path
normalize_path() {
    local p="${1/#\~/$HOME}"
    echo "${p%/}"
}

domain_to_slug() {
    local domain="$1"
    echo "$domain" | tr '.' '_'
}

# ---------- Spinner / Loading Wrapper ----------
run_with_spinner() {
    local msg="$1"
    shift
    local tmp
    tmp="$(mktemp 2>/dev/null || echo "/tmp/spin.$$")"

    if [[ ! -t 2 ]]; then
        echo -e "   ${CYAN}${msg}${NC}" >&2
        "$@" >"$tmp" 2>&1
        local rc=$?
        cat "$tmp"
        rm -f "$tmp"
        return $rc
    fi

    "$@" >"$tmp" 2>&1 &
    local pid=$!
    local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    printf '\033[?25l' >&2

    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i + 1) % ${#frames} ))
        printf "\r   ${CYAN}%s${NC} %s" "${frames:$i:1}" "$msg" >&2
        sleep 0.1
    done

    wait "$pid"
    local rc=$?
    printf '\r\033[K\033[?25h' >&2
    cat "$tmp"
    rm -f "$tmp"
    return $rc
}
