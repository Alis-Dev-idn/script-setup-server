#!/bin/bash
# ============================================================
#  modules/hosting/site.sh — Manajemen Website & User FTP
# ============================================================
[[ -n "${_HOSTING_SITE_LOADED:-}" ]] && return 0
_HOSTING_SITE_LOADED=1

_show_site_list() {
    echo -e "   ${CYAN}--- DAFTAR WEBSITE & USER FTP ---${NC}\n"
    printf "   ${CYAN}%-35s %-9s %-20s %s${NC}\n" "Domain / Folder" "Mode" "FTP User" "Root FTP"
    printf "   %-35s %-9s %-20s %s\n" "-----------------------------------" "---------" "--------------------" "---------"

    local has_entry=0
    local nginx_domains=()
    local f="" d="" mode="" ftp_user="" ftp_root="" uf=""

    for f in /etc/nginx/sites-enabled/*; do
        [[ -f "$f" ]] || continue
        d=$(basename "$f")
        [[ "$d" == "default" ]] && continue
        nginx_domains+=("$d")
        mode="HTTP"
        grep -q "listen 443" "$f" 2>/dev/null && mode="HTTPS"

        ftp_user="-"
        ftp_root="-"
        if [[ -d "$VSFTPD_USER_DIR" ]]; then
            uf=$(grep -rl "local_root=$BASE_DIR/$d" "$VSFTPD_USER_DIR" 2>/dev/null | head -1)
            if [[ -n "$uf" ]]; then
                ftp_user=$(basename "$uf")
                ftp_root=$(grep -oP "(?<=local_root=).*" "$uf" 2>/dev/null || echo "-")
            fi
        fi
        printf "   %-35s ${GREEN}%-9s${NC} %-20s %s\n" "$d" "[$mode]" "$ftp_user" "$ftp_root"
        has_entry=1
    done

    if [[ -d "$VSFTPD_USER_DIR" ]]; then
        for uf in "$VSFTPD_USER_DIR"/*; do
            [[ -f "$uf" ]] || continue
            ftp_user=$(basename "$uf")
            ftp_root=$(grep -oP "(?<=local_root=).*" "$uf" 2>/dev/null || echo "-")
            local folder_name; folder_name=$(basename "$ftp_root")

            local already=0
            local nd=""
            for nd in "${nginx_domains[@]}"; do
                [[ "$nd" == "$folder_name" ]] && { already=1; break; }
            done
            [[ $already -eq 1 ]] && continue

            printf "   %-35s ${YELLOW}%-9s${NC} %-20s %s\n" "$folder_name" "[FTP]" "$ftp_user" "$ftp_root"
            has_entry=1
        done
    fi

    [[ $has_entry -eq 0 ]] && echo "   (belum ada website / akun FTP terdaftar)"
    echo ""
}

show_manage_menu() {
    clear
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}         MANAGE WEBSITE & FTP                                  ${NC}"
    echo -e "${CYAN}================================================================${NC}"
    _show_site_list
    echo " 1. Buat Website + FTP baru"
    echo " 2. Buat FTP saja (tanpa Website)"
    echo " 3. Hapus Website & FTP"
    echo " 4. Ubah Password FTP"
    echo " 5. Kembali ke menu utama"
    echo -e "${CYAN}================================================================${NC}"
}

create_site() {
    clear
    echo -e "${CYAN}--- BUAT WEBSITE + FTP BARU ---${NC}\n"

    local domain="" ftp_user="" ftp_pass="" ftp_pass2="" api_port="" site_type="1"
    while true; do
        read -rp "   Domain (contoh: app.example.com): " domain
        [[ -n "$domain" ]] && break; log_err "Domain tidak boleh kosong."
    done

    while true; do
        read -rp "   Username FTP baru: " ftp_user
        if [[ -z "$ftp_user" ]]; then log_err "Username tidak boleh kosong."
        elif id "$ftp_user" &>/dev/null; then log_err "User '$ftp_user' sudah ada."
        else break; fi
    done

    while true; do
        read -rsp "   Password FTP: " ftp_pass; echo
        read -rsp "   Konfirmasi  : " ftp_pass2; echo
        [[ -z "$ftp_pass" ]] && { log_err "Password tidak boleh kosong."; continue; }
        [[ "$ftp_pass" != "$ftp_pass2" ]] && { log_err "Password tidak cocok."; continue; }
        break
    done

    while true; do
        read -rp "   Port Node.js API (contoh: 3000): " api_port
        [[ "$api_port" =~ ^[0-9]+$ ]] && break; log_err "Port harus angka."
    done

    echo -e "\n   Tipe website:\n   [1] SPA - React / Vue / Angular\n   [2] Static / HTML biasa"
    read -rp "   Pilih [1/2, default 1]: " site_type; [[ -z "$site_type" ]] && site_type="1"

    local deploy_user="" deploy_key_priv=""
    confirm "Buat deploy user untuk CI/CD (SSH key, tanpa password)?" && deploy_user="deploy_$(domain_to_slug "$domain")"

    resolve_ssl_cert "$domain" || { read -rp "   Tekan Enter untuk kembali..." _; return 0; }

    local domain_dir="$BASE_DIR/$domain"
    local folder_fe="$domain_dir/fe"
    local folder_api="$domain_dir/api"

    _confirm_site_summary "$domain" "$ftp_user" "$deploy_user" "$folder_fe" "$folder_api" "$api_port" "$site_type" || return 0

    echo -e "\n${BLUE}[1/6] Membuat folder...${NC}"
    sudo mkdir -p "$folder_fe" "$folder_api" && log_ok "Folder dibuat: $domain_dir/{fe,api}" || { log_err "Gagal membuat folder."; return 1; }

    echo -e "${BLUE}[2/6] Membuat deploy user...${NC}"
    [[ -n "$deploy_user" ]] && deploy_key_priv=$(_create_deploy_user "$deploy_user" "$domain") || log_info "Deploy user dilewati."

    echo -e "${BLUE}[3/6] Membuat FTP user & ACL...${NC}"
    _create_ftp_user "$ftp_user" "$ftp_pass" "$domain_dir" "$deploy_user" || return 1

    echo -e "${BLUE}[4/6] Membuat index.html placeholder...${NC}"
    _generate_index_html "$folder_fe" "$domain" "$site_type"

    echo -e "${BLUE}[5/6] Menulis konfigurasi Nginx...${NC}"
    _generate_nginx_vhost "$domain" "$folder_fe" "$api_port" "$site_type" "$SSL_CERT" "$SSL_KEY"

    echo -e "${BLUE}[6/6] Restart vsftpd...${NC}"
    sudo systemctl restart vsftpd &>/dev/null && log_ok "vsftpd direstart." || log_err "vsftpd gagal restart."

    _show_site_summary "$domain" "$ftp_user" "$domain_dir" "$SSL_CERT" "$deploy_user" "$deploy_key_priv"
}

_confirm_site_summary() {
    local domain="$1" ftp_user="$2" deploy_user="$3" folder_fe="$4" folder_api="$5" api_port="$6" site_type="$7"
    echo -e "\n   ${YELLOW}--- Ringkasan ---${NC}"
    echo "   Domain      : $domain"
    echo "   FTP User    : $ftp_user"
    echo "   Deploy User : ${deploy_user:-tidak dibuat}"
    echo "   Folder FE   : $folder_fe"
    echo "   Folder API  : $folder_api"
    echo "   API Port    : $api_port"
    echo "   Tipe Site   : $([ "$site_type" == "1" ] && echo "SPA" || echo "Static")"
    echo "   SSL         : ${SSL_CERT:-HTTP only}\n"
    confirm "Lanjutkan?" || { read -rp "   Tekan Enter untuk kembali..." _; return 1; }
    return 0
}

_generate_index_html() {
    local folder_fe="$1" domain="$2" site_type="$3"
    [[ -f "$folder_fe/index.html" ]] && { log_warn "index.html sudah ada, skip."; return 0; }
    local badge="SPA Ready"
    [[ "$site_type" != "1" ]] && badge="Website Aktif"
    sudo tee "$folder_fe/index.html" > /dev/null << HTMLEOF
<!DOCTYPE html><html lang="id"><head><meta charset="UTF-8"><title>$domain</title>
<style>body{font-family:sans-serif;background:#0f172a;color:#e2e8f0;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;}
.card{background:#1e293b;border-radius:12px;padding:40px;text-align:center;max-width:480px;}
.badge{background:#38bdf820;color:#38bdf8;padding:4px 12px;border-radius:99px;font-size:12px;}
h1{font-size:20px;margin-top:16px;}</style></head>
<body><div class="card"><span class="badge">$badge</span><h1>$domain</h1><p>Website berhasil dikonfigurasi.</p></div></body></html>
HTMLEOF
    log_ok "index.html placeholder dibuat."
}

_generate_nginx_vhost() {
    local domain="$1" folder_fe="$2" api_port="$3" site_type="$4" ssl_cert="$5" ssl_key="$6"
    local conf="/etc/nginx/sites-available/$domain"
    local try_files='try_files $uri $uri/ =404'
    [[ "$site_type" == "1" ]] && try_files='try_files $uri $uri/ /index.html'

    local ssl_block=""
    if [[ -n "$ssl_cert" && -f "$ssl_cert" ]]; then
        sudo tee "$conf" > /dev/null << NGINXEOF
server {
    listen 80;
    server_name $domain;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name $domain;
    ssl_certificate     $ssl_cert;
    ssl_certificate_key $ssl_key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    root  $folder_fe;
    index index.html index.htm;
    location / { $try_files; }
    location /api/ {
        proxy_pass         http://127.0.0.1:$api_port;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection 'upgrade';
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
NGINXEOF
    else
        sudo tee "$conf" > /dev/null << NGINXEOF
server {
    listen 80;
    server_name $domain;
    root  $folder_fe;
    index index.html index.htm;
    location / { $try_files; }
    location /api/ {
        proxy_pass         http://127.0.0.1:$api_port;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection 'upgrade';
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
NGINXEOF
    fi
    sudo ln -sf "$conf" "/etc/nginx/sites-enabled/$domain"
    sudo nginx -t &>/dev/null && sudo systemctl reload nginx && log_ok "Nginx config dibuat & direload." || log_err "Nginx config error!"
}

_show_site_summary() {
    local domain="$1" ftp_user="$2" domain_dir="$3" ssl_cert="$4" deploy_user="$5" deploy_key_priv="$6"
    echo -e "\n${CYAN}============================================================${NC}"
    echo -e "${CYAN} RINGKASAN                                                  ${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo "  Domain       : $domain"
    echo "  FTP User     : $ftp_user"
    echo "  Folder       : $domain_dir"
    [[ -n "$ssl_cert" ]] && echo "  Akses Web    : https://$domain" || echo "  Akses Web    : http://$domain"
    if [[ -n "$deploy_user" ]]; then
        echo "  Deploy User  : $deploy_user (SSH, folder sama dengan FTP)"
        if [[ -n "$deploy_key_priv" ]]; then
            echo -e "\n  ${YELLOW}!! SIMPAN PRIVATE KEY INI KE GITHUB SECRETS (SSH_PRIVATE_KEY) !!${NC}\n$deploy_key_priv\n"
        fi
    fi
    echo -e "${CYAN}============================================================${NC}\n"
    read -rp "   Tekan Enter untuk kembali..." _
}

create_ftp_only() {
    clear
    echo -e "${CYAN}--- BUAT FTP SAJA (tanpa Website) ---${NC}\n"
    local domain="" ftp_user="" ftp_pass="" ftp_pass2="" deploy_user=""

    read -rp "   Domain / nama folder (contoh: api.example.com): " domain
    [[ -z "$domain" ]] && { log_err "Tidak boleh kosong."; return 1; }

    read -rp "   Username FTP baru: " ftp_user
    [[ -z "$ftp_user" ]] && { log_err "Tidak boleh kosong."; return 1; }
    id "$ftp_user" &>/dev/null && { log_err "User '$ftp_user' sudah ada."; return 1; }

    read -rsp "   Password FTP: " ftp_pass; echo
    read -rsp "   Konfirmasi  : " ftp_pass2; echo
    [[ "$ftp_pass" != "$ftp_pass2" || -z "$ftp_pass" ]] && { log_err "Password tidak cocok."; return 1; }

    confirm "Buat deploy user untuk CI/CD?" && deploy_user="deploy_$(domain_to_slug "$domain")"
    local domain_dir="$BASE_DIR/$domain"

    confirm "Lanjutkan?" || { read -rp "   Tekan Enter untuk kembali..." _; return 0; }

    sudo mkdir -p "$domain_dir" && log_ok "Folder dibuat: $domain_dir" || { log_err "Gagal membuat folder."; return 1; }
    [[ -n "$deploy_user" ]] && _create_deploy_user "$deploy_user" "$domain" >/dev/null
    _create_ftp_user "$ftp_user" "$ftp_pass" "$domain_dir" "$deploy_user" || return 1
    sudo systemctl restart vsftpd &>/dev/null && log_ok "vsftpd direstart."
    log_ok "Akun FTP '$ftp_user' siap. Root FTP: $domain_dir"
    read -rp "   Tekan Enter untuk kembali..." _
}

delete_site() {
    clear
    echo -e "${RED}--- HAPUS WEBSITE & FTP ---${NC}\n"
    _show_site_list
    local del_domain="" del_ftp_user=""
    read -rp "   Domain yang ingin dihapus: " del_domain; [[ -z "$del_domain" ]] && return 0
    read -rp "   FTP Username terkait: " del_ftp_user; [[ -z "$del_ftp_user" ]] && return 0
    local del_deploy_user="deploy_$(domain_to_slug "$del_domain")"

    confirm "Yakin hapus website & FTP untuk $del_domain?" || { read -rp "   Enter untuk kembali..." _; return 0; }

    sudo rm -f "/etc/nginx/sites-enabled/$del_domain" "/etc/nginx/sites-available/$del_domain"
    sudo nginx -t &>/dev/null && sudo systemctl reload nginx && log_ok "Nginx direload."

    sudo rm -f "$VSFTPD_USER_DIR/$del_ftp_user"
    [[ -f "$VSFTPD_USERLIST" ]] && sudo sed -i "/^$del_ftp_user$/d" "$VSFTPD_USERLIST"
    id "$del_ftp_user" &>/dev/null && sudo deluser --remove-home "$del_ftp_user" &>/dev/null && log_ok "FTP user dihapus."

    [[ -f "$SSH_DENY_CONF" ]] && {
        sudo sed -i "s/ $del_ftp_user//g; s/$del_ftp_user //g" "$SSH_DENY_CONF"
        sudo systemctl reload sshd &>/dev/null || sudo systemctl reload ssh &>/dev/null
    }

    id "$del_deploy_user" &>/dev/null && confirm "Hapus deploy user '$del_deploy_user'?" && sudo deluser --remove-home "$del_deploy_user" &>/dev/null
    local del_folder="$BASE_DIR/$del_domain"
    [[ -d "$del_folder" ]] && confirm "Hapus folder data $del_folder?" && sudo rm -rf "$del_folder" && log_ok "Folder dihapus."

    sudo systemctl restart vsftpd &>/dev/null && log_ok "vsftpd direstart."
    read -rp "   Tekan Enter untuk kembali..." _
}

change_password() {
    clear
    echo -e "${CYAN}--- UBAH PASSWORD FTP ---${NC}\n"
    _show_site_list
    local target_user="" new_pass="" new_pass2=""
    read -rp "   Username FTP: " target_user
    if ! id "$target_user" &>/dev/null; then log_err "User '$target_user' tidak ada."; read -rp "   Tekan Enter..."; return 0; fi

    while true; do
        read -rsp "   Password baru : " new_pass; echo
        read -rsp "   Konfirmasi    : " new_pass2; echo
        [[ -z "$new_pass" ]] && { log_err "Tidak boleh kosong."; continue; }
        [[ "$new_pass" != "$new_pass2" ]] && { log_err "Password tidak cocok."; continue; }
        break
    done

    echo "$target_user:$new_pass" | sudo chpasswd && log_ok "Password '$target_user' diubah." || log_err "Gagal ubah password."
    read -rp "   Tekan Enter untuk kembali..." _
}

manage_menu() {
    local sub_choice=""
    while true; do
        show_manage_menu
        read -rp "Pilih sub-menu (1-5): " sub_choice
        echo ""
        case "$sub_choice" in
            1) create_site ;;
            2) create_ftp_only ;;
            3) delete_site ;;
            4) change_password ;;
            5) return 0 ;;
            *) echo -e "${RED}   Pilihan tidak valid.${NC}"; sleep 1 ;;
        esac
    done
}
