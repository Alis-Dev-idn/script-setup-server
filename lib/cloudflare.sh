#!/bin/bash
# ============================================================
#  lib/cloudflare.sh — Cloudflare API token & (nanti) DNS API
#  Membutuhkan: lib/common.sh (confirm, log_*, warna)
# ============================================================
[[ -n "${_LIB_CLOUDFLARE_LOADED:-}" ]] && return 0
_LIB_CLOUDFLARE_LOADED=1

# Lokasi credential certbot-dns-cloudflare
CF_CRED_FILE="${CF_CRED_FILE:-/root/.secrets/certbot/cloudflare.ini}"

# ------------------------------------------------------------
# Setup / simpan Cloudflare API token (dipakai certbot DNS-01)
# (dipindah apa adanya dari setup-hosting.sh — perilaku tidak berubah)
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
        confirm "Timpa dengan token baru?" || { read -rp "   Tekan Enter untuk kembali..." _; return; }
    fi

    echo -e "   ${CYAN}Cara mendapatkan Cloudflare API Token:${NC}"
    echo "   1. dash.cloudflare.com -> My Profile -> API Tokens -> Create Token"
    echo "   2. Template: Edit zone DNS"
    echo "   3. Zone Resources: Include -> Specific zone -> domain kamu"
    echo "   4. Copy token yang dihasilkan"
    echo ""

    read -rp "   Masukkan Cloudflare API Token: " CF_TOKEN
    if [[ -z "$CF_TOKEN" ]]; then
        log_err "Token tidak boleh kosong."
        read -rp "   Tekan Enter untuk kembali..." _; return
    fi

    mkdir -p "$(dirname "$CF_CRED_FILE")"
    echo "dns_cloudflare_api_token = $CF_TOKEN" > "$CF_CRED_FILE"
    chmod 600 "$CF_CRED_FILE"
    log_ok "Credentials disimpan: $CF_CRED_FILE (chmod 600)"

    echo ""
    read -rp "   Tekan Enter untuk kembali..." _
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

# ------------------------------------------------------------
# TODO (fitur lanjutan — disetujui pakai API langsung/curl):
#   cf_zone_id <domain>            -> resolve zone id via GET /zones
#   cf_upsert_dns_record <zone> <name> <type> <content>
#                                  -> buat/update A record domain->IP
# Fungsi ini akan dipakai oleh menu "Setup TLS-only MongoDB" agar
# domain otomatis menunjuk ke IP server sebelum issue sertifikat.
# Belum diimplementasikan pada tahap refactor ini.
# ------------------------------------------------------------
