#!/bin/bash
# ============================================================
#  modules/hosting/ssl.sh — Manajemen SSL Certbot & Cloudflare
# ============================================================
[[ -n "${_HOSTING_SSL_LOADED:-}" ]] && return 0
_HOSTING_SSL_LOADED=1

_show_ssl_list() {
    echo -e "   ${CYAN}--- DAFTAR SERTIFIKAT SSL ---${NC}\n"
    local live_dir="/etc/letsencrypt/live"
    [[ ! -d "$live_dir" ]] && { echo "   (direktori $live_dir tidak ditemukan)\n"; return 0; }

    local found=0
    local now; now=$(date +%s)
    printf "   %-4s %-35s %-22s %-12s %s\n" "No" "Domain / Cert Name" "Domains (SAN)" "Expiry" "Status"
    printf "   %-4s %-35s %-22s %-12s %s\n" "----" "-----------------------------------" "----------------------" "------------" "------"

    local idx=0 cert_dir="" cert_name="" san_domains="" expiry_str="" expiry_ts=0 days_left=0 expiry_fmt="" status_label=""
    for cert_dir in "$live_dir"/*/; do
        [[ -f "$cert_dir/fullchain.pem" ]] || continue
        cert_name=$(basename "$cert_dir")
        [[ "$cert_name" == "README" ]] && continue

        san_domains=$(openssl x509 -in "$cert_dir/fullchain.pem" -noout -text 2>/dev/null \
            | grep -oP '(?<=DNS:)[^\s,]+' | tr '\n' ',' | sed 's/,$//')
        [[ -z "$san_domains" ]] && san_domains="-"

        expiry_str=$(openssl x509 -in "$cert_dir/fullchain.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
        expiry_ts=$(date -d "$expiry_str" +%s 2>/dev/null || echo "0")
        days_left=$(( (expiry_ts - now) / 86400 ))
        expiry_fmt=$(date -d "$expiry_str" +"%Y-%m-%d" 2>/dev/null || echo "unknown")

        if [[ $days_left -lt 0 ]]; then status_label="${RED}EXPIRED${NC}"
        elif [[ $days_left -le 14 ]]; then status_label="${RED}${days_left}h lagi${NC}"
        elif [[ $days_left -le 30 ]]; then status_label="${YELLOW}${days_left}h lagi${NC}"
        else status_label="${GREEN}${days_left}h lagi${NC}"; fi

        printf "   %-4s %-35s %-22s %-12s " "$idx" "$cert_name" "${san_domains:0:22}" "$expiry_fmt"
        echo -e "$status_label"
        (( idx++ ))
        found=1
    done

    [[ $found -eq 0 ]] && echo "   (belum ada sertifikat Let's Encrypt)"
    echo ""
}

ssl_list() {
    clear
    echo -e "${CYAN}--- LIST SERTIFIKAT SSL ---${NC}\n"
    _show_ssl_list
    local live_dir="/etc/letsencrypt/live"
    local cert_dirs=()
    while IFS= read -r d; do cert_dirs+=("$d"); done \
        < <(find "$live_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | grep -v "README" | sort)

    if [[ ${#cert_dirs[@]} -gt 0 ]]; then
        local sel=""
        read -rp "   Masukkan nomor untuk melihat detail (Enter = skip): " sel
        if [[ "$sel" =~ ^[0-9]+$ && "$sel" -lt ${#cert_dirs[@]} ]]; then
            local chosen="${cert_dirs[$sel]}"
            echo -e "\n   ${CYAN}--- Detail: $(basename "$chosen") ---${NC}"
            sudo openssl x509 -in "$chosen/fullchain.pem" -noout \
                -subject -issuer -dates -fingerprint -ext subjectAltName 2>/dev/null | sed 's/^/   /'
            echo -e "\n   File:\n     fullchain : $chosen/fullchain.pem\n     privkey   : $chosen/privkey.pem"
        fi
    fi
    echo ""
    read -rp "   Tekan Enter untuk kembali..." _
}

ssl_create() {
    clear
    echo -e "${CYAN}--- BUAT SERTIFIKAT SSL BARU ---${NC}\n"
    if [[ ! -f "$CF_CRED_FILE" ]]; then
        log_err "Cloudflare credentials belum ada. Jalankan Menu 2 terlebih dahulu."
        read -rp "   Tekan Enter untuk kembali..." _; return 0
    fi

    echo -e "   Metode pembuatan:\n   [1] Cloudflare DNS (wildcard support)\n   [2] HTTP-01 Challenge\n"
    local method="1" main_domain="" extra_domains="" le_email=""
    read -rp "   Pilih metode [1/2, default 1]: " method; [[ -z "$method" ]] && method="1"

    read -rp "   Domain utama (contoh: example.com): " main_domain
    [[ -z "$main_domain" ]] && { log_err "Domain tidak boleh kosong."; read -rp "   Enter..."; return 0; }

    read -rp "   Domain tambahan (opsional): " extra_domains
    read -rp "   Email notifikasi [admin@$main_domain]: " le_email; [[ -z "$le_email" ]] && le_email="admin@$main_domain"

    local d_args="-d $main_domain"
    local ed=""
    for ed in $extra_domains; do d_args="$d_args -d $ed"; done

    if [[ "$method" == "1" ]] && confirm "Tambahkan wildcard *.$main_domain?"; then
        d_args="$d_args -d *.$main_domain"
    fi

    confirm "Generate sertifikat sekarang?" || { read -rp "   Tekan Enter untuk kembali..." _; return 0; }

    if [[ "$method" == "1" ]]; then
        log_info "Menjalankan certbot (DNS challenge)..."
        sudo certbot certonly --dns-cloudflare --dns-cloudflare-credentials "$CF_CRED_FILE" \
            $d_args --non-interactive --agree-tos -m "$le_email"
    else
        log_info "Menjalankan certbot (HTTP challenge)..."
        sudo certbot certonly --nginx $d_args --non-interactive --agree-tos -m "$le_email"
    fi

    local cert_path="/etc/letsencrypt/live/$main_domain/fullchain.pem"
    if [[ -f "$cert_path" ]]; then
        log_ok "Sertifikat berhasil dibuat!"
        if confirm "Pasang sertifikat ini ke Nginx site sekarang?"; then
            _ssl_apply_to_nginx "$main_domain" "$cert_path" "/etc/letsencrypt/live/$main_domain/privkey.pem"
        fi
    else
        log_err "Sertifikat gagal dibuat. Periksa output certbot."
    fi
    read -rp "   Tekan Enter untuk kembali..." _
}

_ssl_apply_to_nginx() {
    local cert_domain="$1" cert_path="$2" key_path="$3"
    local nginx_sites=()
    while IFS= read -r f; do nginx_sites+=("$f"); done < <(find /etc/nginx/sites-available -type f ! -name "default" | sort)
    [[ ${#nginx_sites[@]} -eq 0 ]] && { log_warn "Tidak ada Nginx site."; return 0; }

    echo -e "\n   Pilih Nginx site yang akan dipasang SSL:"
    local i=0 site_name="" has_ssl=""
    for i in "${!nginx_sites[@]}"; do
        site_name=$(basename "${nginx_sites[$i]}")
        has_ssl="HTTP"
        grep -q "listen 443" "${nginx_sites[$i]}" 2>/dev/null && has_ssl="HTTPS"
        echo "     [$i] $site_name [$has_ssl]"
    done
    echo "     [s] Skip\n"
    local site_sel=""
    read -rp "   Pilih: " site_sel
    [[ "$site_sel" == "s" || -z "$site_sel" ]] && return 0
    if ! [[ "$site_sel" =~ ^[0-9]+$ && "$site_sel" -lt ${#nginx_sites[@]} ]]; then
        log_err "Pilihan tidak valid."; return 0
    fi

    local target_conf="${nginx_sites[$site_sel]}"
    sudo cp "$target_conf" "${target_conf}.bak.$(date +%Y%m%d%H%M%S)"
    if grep -q "listen 443" "$target_conf" 2>/dev/null; then
        sudo sed -i -e "s|ssl_certificate .*;|ssl_certificate     $cert_path;|" \
                    -e "s|ssl_certificate_key .*;|ssl_certificate_key $key_path;|" "$target_conf"
    else
        local s_name r_dir i_dir locs
        s_name=$(grep -oP "(?<=server_name )[^;]+" "$target_conf" | head -1 | tr -d ' ')
        r_dir=$(grep -oP "(?<=root )[^;]+" "$target_conf" | head -1 | tr -d ' ')
        i_dir=$(grep -oP "(?<=index )[^;]+" "$target_conf" | head -1)
        locs=$(awk '/location /,/^}/' "$target_conf" 2>/dev/null | head -40)
        sudo tee "$target_conf" > /dev/null << SSLEOF
server {
    listen 80;
    server_name $s_name;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name $s_name;
    ssl_certificate     $cert_path;
    ssl_certificate_key $key_path;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    root  $r_dir;
    index $i_dir;
$locs
}
SSLEOF
    fi
    sudo nginx -t &>/dev/null && sudo systemctl reload nginx && log_ok "SSL diaplikasikan ke Nginx." || log_err "Nginx syntax error!"
}

ssl_renew() {
    clear
    echo -e "${CYAN}--- RENEW SERTIFIKAT SSL ---${NC}\n"
    _show_ssl_list
    echo -e "   Pilihan renew:\n   [1] Renew semua sertifikat\n   [2] Renew sertifikat tertentu\n   [3] Dry-run (simulasi)\n"
    local renew_choice=""
    read -rp "   Pilih [1/2/3]: " renew_choice
    case "$renew_choice" in
        1)
            sudo certbot renew && { sudo systemctl reload nginx &>/dev/null; log_ok "Renew semua selesai."; }
            ;;
        2)
            local live_dir="/etc/letsencrypt/live"
            local cert_dirs=()
            while IFS= read -r d; do cert_dirs+=("$d"); done \
                < <(find "$live_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | grep -v "README" | sort)
            local i=0 cert_sel=""
            for i in "${!cert_dirs[@]}"; do echo "     [$i] $(basename "${cert_dirs[$i]}")"; done
            read -rp "   Nomor: " cert_sel
            if [[ "$cert_sel" =~ ^[0-9]+$ && "$cert_sel" -lt ${#cert_dirs[@]} ]]; then
                local chosen_name; chosen_name=$(basename "${cert_dirs[$cert_sel]}")
                sudo certbot renew --cert-name "$chosen_name" --force-renewal \
                    && { sudo systemctl reload nginx &>/dev/null; log_ok "Sertifikat '$chosen_name' diperbarui."; }
            fi
            ;;
        3)
            sudo certbot renew --dry-run && log_info "Dry-run selesai."
            ;;
        *) log_err "Pilihan tidak valid." ;;
    esac
    read -rp "   Tekan Enter untuk kembali..." _
}

show_ssl_menu() {
    clear
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}         MANAGE SSL                                            ${NC}"
    echo -e "${CYAN}================================================================${NC}"
    _show_ssl_list
    echo " 1. List & Detail Sertifikat"
    echo " 2. Buat Sertifikat Baru"
    echo " 3. Renew Sertifikat"
    echo " 4. Kembali ke menu utama"
    echo -e "${CYAN}================================================================${NC}"
}

ssl_menu() {
    local ssl_choice=""
    while true; do
        show_ssl_menu
        read -rp "Pilih sub-menu (1-4): " ssl_choice
        case "$ssl_choice" in
            1) ssl_list ;;
            2) ssl_create ;;
            3) ssl_renew ;;
            4) return 0 ;;
            *) echo -e "${RED}   Pilihan tidak valid.${NC}"; sleep 1 ;;
        esac
    done
}
