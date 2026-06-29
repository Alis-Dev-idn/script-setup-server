#!/bin/bash
# ============================================================
#  Setup Server - Panel terpadu
#  Menggabungkan modul Hosting (vsftpd+Nginx+SSL), MongoDB
#  & Node.js/PM2
# ============================================================
# Resolusikan symlink agar tetap benar saat dijalankan via /usr/local/bin/setup-server
_SELF="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
  _SELF="$(readlink -f "$_SELF" 2>/dev/null || echo "$_SELF")"
fi
ROOT_DIR="$(cd "$(dirname "$_SELF")" && pwd)"
export ROOT_DIR

# ---------- Library bersama ----------
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/cloudflare.sh"
source "$ROOT_DIR/lib/ssl.sh"

# ---------- Modul (di-source, tidak auto-run karena guard BASH_SOURCE) ----------
source "$ROOT_DIR/modules/hosting.sh"
source "$ROOT_DIR/modules/mongodb.sh"
source "$ROOT_DIR/modules/nodejs-pm2.sh"
source "$ROOT_DIR/modules/nginx-extra.sh"

server_main_menu() {
  while true; do
    clear
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}          SETUP SERVER - PANEL TERPADU                          ${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo ""
    echo " 1. Hosting Panel  (vsftpd + Nginx + SSL + Deploy User)"
    echo " 2. MongoDB Manager (setup, user, DB, backup, service)"
    echo " 3. Node.js & PM2  (install, update, manage aplikasi)"
    echo " 4. Nginx Extra    (WSS + MQTT TLS + Auto-Renew)"
    echo " 5. Keluar"
    echo ""
    echo -e "${CYAN}================================================================${NC}"
    echo ""
    read -rp "Pilih modul (1-5): " mod_choice
    echo ""
    case "$mod_choice" in
      1) hosting_main ;;
      2) mongodb_main ;;
      3) nodejs_pm2_main ;;
      4) nginx_extra_main ;;
      5) echo -e "${GREEN}Keluar. Sampai jumpa!${NC}"; exit 0 ;;
      *) error "Pilihan tidak valid."; sleep 1 ;;
    esac
  done
}

# Jalankan hanya jika file ini dieksekusi langsung (bukan di-source)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ "$EUID" -ne 0 ]]; then
    echo -e "${YELLOW}Script membutuhkan root. Menjalankan ulang dengan sudo...${NC}"
    exec sudo bash "$0" "$@"
  fi
  server_main_menu
fi
