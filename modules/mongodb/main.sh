#!/bin/bash
# ============================================================
#  modules/mongodb/main.sh — Main Router & Session MongoDB
# ============================================================
[[ -n "${_MONGODB_MAIN_LOADED:-}" ]] && return 0
_MONGODB_MAIN_LOADED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Shared Libraries
# shellcheck source=lib/common.sh
source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=lib/cloudflare.sh
source "${REPO_ROOT}/lib/cloudflare.sh"
# shellcheck source=lib/ssl.sh
source "${REPO_ROOT}/lib/ssl.sh"

# State & Config
MONGOD_CONF="${MONGOD_CONF:-/etc/mongod.conf}"
MONGO_HOST="${MONGO_HOST:-127.0.0.1}"
MONGO_PORT="${MONGO_PORT:-27017}"
MONGO_AUTH="${MONGO_AUTH:-no}"
MONGO_ADMIN_USER="${MONGO_ADMIN_USER:-}"
MONGO_ADMIN_PASS="${MONGO_ADMIN_PASS:-}"
ADMIN_CLI_ARGS=""

show_banner() {
    clear
    echo -e "${BLD}${CYN}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║        MongoDB Manager v1.1              ║"
    echo "  ║        Ubuntu/Debian                     ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${NC}"
}

mongo_exec() {
    local js_code="$1"
    local target_db="${2:-admin}"
    local cmd=(mongosh --quiet)
    [[ -n "$MONGO_HOST" ]] && cmd+=(--host "$MONGO_HOST")
    [[ -n "$MONGO_PORT" ]] && cmd+=(--port "$MONGO_PORT")
    if [[ "$MONGO_AUTH" == "yes" && -n "$MONGO_ADMIN_USER" ]]; then
        cmd+=(-u "$MONGO_ADMIN_USER" -p "$MONGO_ADMIN_PASS" --authenticationDatabase admin)
    fi
    cmd+=("$target_db" --eval "$js_code")
    "${cmd[@]}"
}

parse_mongod_conf() {
    local key="$1"
    [[ ! -f "$MONGOD_CONF" ]] && return 1
    grep -E "^\s*${key}\s*:" "$MONGOD_CONF" 2>/dev/null \
        | awk -F':' '{gsub(/[[:space:]]/, "", $2); print $2}' | head -1
}

load_from_etc() {
    [[ ! -f "$MONGOD_CONF" ]] && return 1
    local p; p=$(parse_mongod_conf "port")
    [[ -n "$p" ]] && MONGO_PORT="$p"

    local b; b=$(parse_mongod_conf "bindIp")
    if [[ -n "$b" ]]; then
        if echo "$b" | grep -q "127.0.0.1"; then
            MONGO_HOST="127.0.0.1"
        else
            MONGO_HOST=$(echo "$b" | awk -F',' '{print $1}' | tr -d ' ')
        fi
    fi

    if grep -qE "^\s*authorization\s*:\s*enabled" "$MONGOD_CONF" 2>/dev/null; then
        MONGO_AUTH="yes"
    else
        MONGO_AUTH="no"
    fi
}

ensure_admin_creds() {
    [[ "$MONGO_AUTH" != "yes" ]] && return 0
    [[ -n "$MONGO_ADMIN_USER" && -n "$MONGO_ADMIN_PASS" ]] && return 0

    echo
    warn "Autentikasi MongoDB aktif di /etc/mongod.conf."
    info "Masukkan kredensial admin untuk sesi ini:"
    local u="" p=""
    read -rp "  Username admin: " u
    read -rsp "  Password admin: " p; echo
    MONGO_ADMIN_USER="$u"
    MONGO_ADMIN_PASS="$p"
}

mongo_ping() {
    local cmd=(mongosh --quiet)
    [[ -n "$MONGO_HOST" ]] && cmd+=(--host "$MONGO_HOST")
    [[ -n "$MONGO_PORT" ]] && cmd+=(--port "$MONGO_PORT")
    if [[ "$MONGO_AUTH" == "yes" && -n "$MONGO_ADMIN_USER" ]]; then
        cmd+=(-u "$MONGO_ADMIN_USER" -p "$MONGO_ADMIN_PASS" --authenticationDatabase admin)
    fi
    cmd+=(admin --eval "db.runCommand({ping:1}).ok")
    local res; res=$("${cmd[@]}" 2>/dev/null | tr -d '[:space:]')
    [[ "$res" == "1" ]]
}

prepare_conn() {
    load_from_etc
    ensure_admin_creds
    if ! mongo_ping; then
        warn "Tidak dapat terhubung ke MongoDB ($MONGO_HOST:$MONGO_PORT)."
        warn "Pastikan service mongod berjalan dan kredensial benar."
    fi
}

# Submodules
# shellcheck source=modules/mongodb/install.sh
source "${SCRIPT_DIR}/install.sh"
# shellcheck source=modules/mongodb/config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=modules/mongodb/user.sh
source "${SCRIPT_DIR}/user.sh"
# shellcheck source=modules/mongodb/database.sh
source "${SCRIPT_DIR}/database.sh"
# shellcheck source=modules/mongodb/backup.sh
source "${SCRIPT_DIR}/backup.sh"
# shellcheck source=modules/mongodb/service.sh
source "${SCRIPT_DIR}/service.sh"
# shellcheck source=modules/mongodb/uninstall.sh
source "${SCRIPT_DIR}/uninstall.sh"

main_menu() {
    local choice=""
    while true; do
        show_banner
        echo -e "${BLD}  Menu Utama:${NC}"
        echo
        echo "    1)  Setup MongoDB (instalasi / konfigurasi baru)"
        echo "    2)  Manage User (buat, update, hapus, role)"
        echo "    3)  Manage Database (buat, hapus, collections)"
        echo "    4)  Backup database (dump + kompres .tar.gz)"
        echo "    5)  Restore database (dari .tar.gz / direktori)"
        echo "    6)  Service MongoDB (status, start, stop, restart, log)"
        echo "    7)  Hapus/Uninstall MongoDB (package, config, repo; data opsional)"
        echo "    8)  Keluar"
        echo
        line
        read -rp "  Pilihan [1-8]: " choice

        case "$choice" in
            1) setup_mongodb ;;
            2) manage_user_menu ;;
            3) manage_database_menu ;;
            4) backup_db ;;
            5) restore_db ;;
            6) service_menu ;;
            7) uninstall_mongodb ;;
            8) echo -e "\n  ${GRN}Sampai jumpa!${NC}\n"; exit 0 ;;
            *) warn "Pilihan tidak valid."; sleep 1 ;;
        esac
    done
}

mongodb_main() {
    main_menu
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    require_root "$@"
    mongodb_main
fi
