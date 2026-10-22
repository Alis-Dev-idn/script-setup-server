#!/bin/bash
# ============================================================
#  lib/cloudflare.sh — Cloudflare API token & DNS credential
#  Membutuhkan: lib/common.sh (confirm, log_*, warna)
# ============================================================
[[ -n "${_LIB_CLOUDFLARE_LOADED:-}" ]] && return 0
_LIB_CLOUDFLARE_LOADED=1

# Lokasi credential certbot-dns-cloudflare
CF_CRED_FILE="${CF_CRED_FILE:-/root/.secrets/certbot/cloudflare.ini}"

# ------------------------------------------------------------
# Setup / simpan Cloudflare API token (dipakai certbot DNS-01)
# ------------------------------------------------------------
setup_cloudflare_creds() {
    clear
    echo -e "${CYAN}--- SETUP CLOUDFLARE API TOKEN ---${NC}"
    echo ""

    if [[ -f "$CF_CRED_FILE" ]]; then
        log_warn "Credentials sudah ada: $CF_CRED_FILE"
        echo "   Isi saat ini:"
        cat "$CF_CRED_FILE"
        echo ""
        confirm "Timpa dengan token baru?" || { read -rp "   Tekan Enter untuk kembali..." _; return 0; }
    fi

    echo -e "   ${CYAN}Cara mendapatkan Cloudflare API Token:${NC}"
    echo "   1. dash.cloudflare.com -> My Profile -> API Tokens -> Create Token"
    echo "   2. Template: Edit zone DNS"
    echo "   3. Zone Resources: Include -> Specific zone -> domain kamu"
    echo "   4. Copy token yang dihasilkan"
    echo ""

    local cf_token=""
    read -rp "   Masukkan Cloudflare API Token: " cf_token
    if [[ -z "$cf_token" ]]; then
        log_err "Token tidak boleh kosong."
        read -rp "   Tekan Enter untuk kembali..." _
        return 1
    fi

    mkdir -p "$(dirname "$CF_CRED_FILE")"
    echo "dns_cloudflare_api_token = $cf_token" > "$CF_CRED_FILE"
    chmod 600 "$CF_CRED_FILE"
    log_ok "Credentials disimpan: $CF_CRED_FILE (chmod 600)"

    echo ""
    read -rp "   Tekan Enter untuk kembali..." _
    return 0
}

# ------------------------------------------------------------
# Ambil token mentah dari file credential (untuk panggilan API)
# Mengembalikan string token via stdout, kosong jika tidak ada.
# ------------------------------------------------------------
cf_get_token() {
    [[ -f "$CF_CRED_FILE" ]] || { echo ""; return 1; }
    grep -oP '(?<=dns_cloudflare_api_token\s=\s).*' "$CF_CRED_FILE" 2>/dev/null \
        | tr -d '[:space:]'
}
