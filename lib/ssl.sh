#!/bin/bash
# ============================================================
#  lib/ssl.sh — Deteksi & resolusi sertifikat TLS/SSL bersama
#  Membutuhkan: lib/common.sh, lib/cloudflare.sh (CF_CRED_FILE)
# ============================================================
[[ -n "${_LIB_SSL_LOADED:-}" ]] && return 0
_LIB_SSL_LOADED=1

# ------------------------------------------------------------
# detect_ssl_certs — scan lokasi umum sertifikat TLS/SSL di server
# Mengisi: DETECTED_CERT, DETECTED_KEY, DETECTED_CA (bisa kosong)
# (dipindah apa adanya dari mongodb-manager.sh)
# ------------------------------------------------------------
detect_ssl_certs() {
  DETECTED_CERT=""
  DETECTED_KEY=""
  DETECTED_CA=""
  local found=0

  echo
  info "Mendeteksi sertifikat TLS/SSL yang tersedia..."
  echo

  # 1. Let's Encrypt
  if [[ -d /etc/letsencrypt/live ]]; then
    local le_domain
    le_domain=$(ls /etc/letsencrypt/live/ 2>/dev/null | grep -v README | head -1)
    if [[ -n "$le_domain" ]]; then
      local le_cert="/etc/letsencrypt/live/${le_domain}/fullchain.pem"
      local le_key="/etc/letsencrypt/live/${le_domain}/privkey.pem"
      if [[ -f "$le_cert" && -f "$le_key" ]]; then
        echo -e "  ${GRN}[DITEMUKAN]${NC} Let's Encrypt — domain: ${BLD}${le_domain}${NC}"
        echo    "    Cert : $le_cert"
        echo    "    Key  : $le_key"
        echo
        warn "Catatan: MongoDB butuh file PEM gabungan (cert + key dalam 1 file)."
        echo "  Akan dibuat otomatis di /etc/mongodb/tls/ jika dipilih."
        DETECTED_CERT="$le_cert"
        DETECTED_KEY="$le_key"
        found=1
      fi
    fi
  fi

  # 2. /etc/ssl/certs & /etc/ssl/private
  local ssl_cert ssl_key
  ssl_cert=$(find /etc/ssl/certs   -maxdepth 1 -name "*.pem" ! -name "ca-*" 2>/dev/null | head -1)
  ssl_key=$(find  /etc/ssl/private -maxdepth 1 -name "*.pem" 2>/dev/null | head -1)
  if [[ -n "$ssl_cert" && -n "$ssl_key" ]]; then
    echo -e "  ${GRN}[DITEMUKAN]${NC} /etc/ssl/"
    echo    "    Cert : $ssl_cert"
    echo    "    Key  : $ssl_key"
    echo
    [[ -z "$DETECTED_CERT" ]] && { DETECTED_CERT="$ssl_cert"; DETECTED_KEY="$ssl_key"; }
    found=1
  fi

  # 3. /etc/mongodb/tls/ (custom / sudah pernah setup)
  if [[ -f /etc/mongodb/tls/mongodb.pem ]]; then
    echo -e "  ${GRN}[DITEMUKAN]${NC} /etc/mongodb/tls/mongodb.pem (PEM gabungan siap pakai)"
    echo    "    PEM  : /etc/mongodb/tls/mongodb.pem"
    [[ -f /etc/mongodb/tls/ca.pem ]] && echo "    CA   : /etc/mongodb/tls/ca.pem"
    echo
    DETECTED_CERT="/etc/mongodb/tls/mongodb.pem"
    DETECTED_KEY=""   # sudah digabung
    [[ -f /etc/mongodb/tls/ca.pem ]] && DETECTED_CA="/etc/mongodb/tls/ca.pem"
    found=1
  fi

  # 4. /etc/nginx/ssl/ (sering ada kalau server sudah pakai Nginx + SSL)
  local ng_cert ng_key
  ng_cert=$(find /etc/nginx/ssl -maxdepth 2 -name "*.crt" -o -name "*.pem" 2>/dev/null | grep -v chain | head -1)
  ng_key=$(find  /etc/nginx/ssl -maxdepth 2 -name "*.key" 2>/dev/null | head -1)
  if [[ -n "$ng_cert" && -n "$ng_key" ]]; then
    echo -e "  ${GRN}[DITEMUKAN]${NC} /etc/nginx/ssl/"
    echo    "    Cert : $ng_cert"
    echo    "    Key  : $ng_key"
    echo
    [[ -z "$DETECTED_CERT" ]] && { DETECTED_CERT="$ng_cert"; DETECTED_KEY="$ng_key"; }
    found=1
  fi

  if [[ "$found" -eq 0 ]]; then
    warn "Tidak ada sertifikat yang terdeteksi otomatis."
    echo    "  Anda bisa tetap aktifkan TLS dengan memasukkan path manual."
    echo
  fi
}

# ------------------------------------------------------------
# resolve_ssl_cert — cari sertifikat Let's Encrypt yang cocok untuk
# sebuah domain (exact / wildcard / scan), atau tawarkan generate/manual/skip.
# Mengisi: SSL_CERT, SSL_KEY
# (dipindah apa adanya dari setup-hosting.sh)
# ------------------------------------------------------------
resolve_ssl_cert() {
    local domain="$1"
    SSL_CERT=""; SSL_KEY=""

    local parts; IFS='.' read -ra parts <<< "$domain"
    local total=${#parts[@]}
    local candidates=()
    for (( i=1; i<total-1; i++ )); do
        candidates+=("$(IFS='.'; echo "${parts[*]:$i}")")
    done

    log_info "Mendeteksi sertifikat untuk: $domain"

    # Cek 1: exact match
    if [[ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
        log_ok "Sertifikat exact match ditemukan: $domain"
        SSL_CERT="/etc/letsencrypt/live/$domain/fullchain.pem"
        SSL_KEY="/etc/letsencrypt/live/$domain/privkey.pem"
        return 0
    fi

    # Fungsi pencocokan domain
    _cert_covers_domain() {
        local cert_file="$1" check_domain="$2"
        local cert_domains
        cert_domains=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null \
            | grep -oP '(?<=DNS:)[^\s,]+' | tr -d '\r')
        while IFS= read -r cd; do
            [[ "$cd" == "$check_domain" ]] && return 0
            if [[ "$cd" == \** ]]; then
                local wb="${cd#\*.}"
                [[ "${check_domain#*.}" == "$wb" ]] && return 0
            fi
        done <<< "$cert_domains"
        return 1
    }

    # Cek 2: kandidat wildcard
    for candidate in "${candidates[@]}"; do
        local wpath="/etc/letsencrypt/live/$candidate"
        [[ -f "$wpath/fullchain.pem" ]] || continue
        if _cert_covers_domain "$wpath/fullchain.pem" "$domain"; then
            log_ok "Wildcard cert cocok: $wpath"
            SSL_CERT="$wpath/fullchain.pem"; SSL_KEY="$wpath/privkey.pem"
            return 0
        fi
    done

    # Cek 3: scan semua
    log_info "Scanning semua sertifikat di /etc/letsencrypt/live/ ..."
    for cert_dir in /etc/letsencrypt/live/*/; do
        [[ -f "$cert_dir/fullchain.pem" ]] || continue
        if _cert_covers_domain "$cert_dir/fullchain.pem" "$domain"; then
            log_ok "Ditemukan via scan: $cert_dir"
            SSL_CERT="$cert_dir/fullchain.pem"; SSL_KEY="$cert_dir/privkey.pem"
            return 0
        fi
    done

    # Tidak ditemukan — tampilkan opsi
    log_warn "Tidak ada sertifikat yang cocok untuk '$domain'."
    echo ""
    echo "   Pilihan:"
    echo "   [1] Generate sertifikat baru (Certbot via Cloudflare DNS)"
    echo "   [2] Input path sertifikat manual"
    echo "   [3] Skip SSL (HTTP saja)"
    echo ""
    read -rp "   Pilih [1/2/3]: " SSL_CHOICE

    case "$SSL_CHOICE" in
        1)
            if [[ ! -f "$CF_CRED_FILE" ]]; then
                log_err "Cloudflare credentials belum ada. Jalankan Menu 2 dulu."
                return 1
            fi
            local root_domain="${candidates[0]:-$domain}"
            log_info "Root domain: $root_domain"
            if confirm "Generate wildcard untuk *.$root_domain juga?"; then
                sudo certbot certonly \
                    --dns-cloudflare --dns-cloudflare-credentials "$CF_CRED_FILE" \
                    -d "$root_domain" -d "*.$root_domain" \
                    --non-interactive --agree-tos -m "admin@$root_domain"
                SSL_CERT="/etc/letsencrypt/live/$root_domain/fullchain.pem"
                SSL_KEY="/etc/letsencrypt/live/$root_domain/privkey.pem"
            else
                sudo certbot certonly \
                    --dns-cloudflare --dns-cloudflare-credentials "$CF_CRED_FILE" \
                    -d "$domain" --non-interactive --agree-tos -m "admin@$root_domain"
                SSL_CERT="/etc/letsencrypt/live/$domain/fullchain.pem"
                SSL_KEY="/etc/letsencrypt/live/$domain/privkey.pem"
            fi
            [[ -f "$SSL_CERT" ]] && { log_ok "Sertifikat berhasil di-generate."; return 0; }
            log_err "Generate sertifikat gagal."
            return 1
            ;;
        2)
            read -rp "   Path fullchain.pem: " _raw
            SSL_CERT=$(normalize_path "$_raw")
            read -rp "   Path privkey.pem  : " _raw
            SSL_KEY=$(normalize_path "$_raw")

            if sudo test -f "$SSL_CERT" && sudo test -f "$SSL_KEY"; then
                log_ok "Path sertifikat diterima."
                log_info "  cert: $SSL_CERT"
                log_info "  key : $SSL_KEY"
                return 0
            else
                log_err "File tidak ditemukan. Path yang dicek:"
                log_err "  cert: $SSL_CERT"
                log_err "  key : $SSL_KEY"
                log_warn "Pastikan path absolut dan file ada (cek: ls -la PATH)"
                return 1
            fi
            ;;
        3)
            log_warn "SSL dilewati. Domain akan berjalan di HTTP saja."
            SSL_CERT=""; SSL_KEY=""
            return 0
            ;;
        *)
            log_err "Pilihan tidak valid."
            return 1
            ;;
    esac
}
