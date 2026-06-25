#!/bin/bash
# ============================================================
#  Script Setup Server - Online Installer
#  Jalankan dengan: curl -fsSL https://raw.githubusercontent.com/Alis-Dev-idn/script-setup-server/main/install.sh | sudo bash
# ============================================================
set -euo pipefail

REPO_URL="https://github.com/Alis-Dev-idn/script-setup-server.git"
INSTALL_DIR="/opt/script-setup-server"
BRANCH="main"

# ---------- Warna ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_ok()   { echo -e "   ${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "   ${YELLOW}[!!]${NC} $1"; }
log_err()  { echo -e "   ${RED}[ERR]${NC} $1"; }
log_info() { echo -e "   ${CYAN}[--]${NC} $1"; }

# ---------- Cek root ----------
if [[ "$EUID" -ne 0 ]]; then
    echo -e "${YELLOW}Script membutuhkan root. Menjalankan ulang dengan sudo...${NC}"
    exec sudo bash "$0" "$@"
fi

echo ""
echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}     Script Setup Server - Online Installer${NC}"
echo -e "${CYAN}================================================================${NC}"
echo ""

# ---------- Cek dependensi ----------
for cmd in git curl; do
    if ! command -v "$cmd" &>/dev/null; then
        log_err "$cmd belum terinstall. Install dulu: sudo apt install -y $cmd"
        exit 1
    fi
done
log_ok "Dependensi terpenuhi (git, curl)"

# ---------- Clone atau update repo ----------
if [[ -d "$INSTALL_DIR/.git" ]]; then
    log_info "Repo sudah ada di $INSTALL_DIR, memperbarui..."
    cd "$INSTALL_DIR"
    git pull origin "$BRANCH" --ff-only 2>/dev/null || {
        log_warn "Gagal pull, menghapus dan clone ulang..."
        rm -rf "$INSTALL_DIR"
        git clone --branch "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
        cd "$INSTALL_DIR"
    }
    log_ok "Repo diperbarui"
else
    log_info "Mengclone repo ke $INSTALL_DIR..."
    git clone --branch "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    log_ok "Repo berhasil diclone"
fi

# ---------- Buat symlink global ----------
log_info "Membuat symlink global..."
ln -sf "$INSTALL_DIR/setup-server.sh" /usr/local/bin/setup-server 2>/dev/null
chmod +x "$INSTALL_DIR/setup-server.sh"
chmod +x "$INSTALL_DIR"/*.sh
chmod +x "$INSTALL_DIR/modules/"*.sh
log_ok "Symlink dibuat: /usr/local/bin/setup-server"

echo ""
echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}     Instalasi selesai!${NC}"
echo -e "${GREEN}================================================================${NC}"
echo ""
echo "  Jalankan panel utama:"
echo -e "    ${CYAN}setup-server${NC}"
echo ""
echo "  Atau langsung jalankan:"
echo -e "    ${CYAN}bash $INSTALL_DIR/setup-server.sh${NC}"
echo ""
echo "  Jalankan modul secara langsung:"
echo -e "    ${CYAN}bash $INSTALL_DIR/setup-server.sh${NC}  (pilih modul)"
echo -e "    ${CYAN}bash $INSTALL_DIR/nodejs-pm2-manager.sh${NC}"
echo ""
echo -e "  Update ke versi terbaru:"
echo -e "    ${CYAN}cd $INSTALL_DIR && git pull${NC}"
echo ""
echo -e "${GREEN}================================================================${NC}"
