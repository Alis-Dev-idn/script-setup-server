#!/bin/bash
# ============================================================
#  modules/nodejs-pm2/app.sh — PM2 Application Lifecycle
# ============================================================
[[ -n "${_NODEJS_PM2_APP_LOADED:-}" ]] && return 0
_NODEJS_PM2_APP_LOADED=1

pm2_app_menu() {
    local app_choice=""
    while true; do
        clear
        echo -e "${CYAN}--- MANAGE APLIKASI PM2 ---${NC}\n"
        if cmd_exists pm2; then
            pm2 list 2>/dev/null
        else
            error "PM2 belum terinstall!"
            pause; return 0
        fi

        echo -e "\n  1) Start aplikasi baru"
        echo "  2) Stop aplikasi"
        echo "  3) Restart aplikasi"
        echo "  4) Delete aplikasi dari PM2"
        echo "  5) Lihat log aplikasi"
        echo "  6) Lihat detail aplikasi (monit)"
        echo "  7) Simpan daftar aplikasi (pm2 save)"
        echo "  8) Kembali\n"

        read -rp "Pilihan (1-8): " app_choice
        case "$app_choice" in
            1) _pm2_start_app ;;
            2) _pm2_stop_app ;;
            3) _pm2_restart_app ;;
            4) _pm2_delete_app ;;
            5) _pm2_logs_app ;;
            6) pm2 monit 2>/dev/null ;;
            7) pm2 save 2>/dev/null && success "Daftar aplikasi tersimpan!" ;;
            8|"") return 0 ;;
            *) error "Pilihan tidak valid."; sleep 1 ;;
        esac
        sleep 1
    done
}

_pm2_start_app() {
    echo -e "\n  Format start: pm2 start app.js --name myapp"
    local start_cmd=""
    read -rp "  Masukkan command pm2 start: " start_cmd
    if [[ -n "$start_cmd" ]]; then
        # shellcheck disable=SC2086
        pm2 $start_cmd 2>/dev/null && success "Aplikasi dimulai!"
    fi
}

_pm2_stop_app() {
    local stop_name=""
    read -rp "  Nama atau ID aplikasi yang akan di-stop: " stop_name
    [[ -n "$stop_name" ]] && pm2 stop "$stop_name" 2>/dev/null && success "Aplikasi '$stop_name' di-stop."
}

_pm2_restart_app() {
    local restart_name=""
    read -rp "  Nama atau ID aplikasi yang akan direstart: " restart_name
    [[ -n "$restart_name" ]] && pm2 restart "$restart_name" 2>/dev/null && success "Aplikasi '$restart_name' direstart."
}

_pm2_delete_app() {
    local del_name=""
    read -rp "  Nama atau ID aplikasi yang akan dihapus: " del_name
    if [[ -n "$del_name" ]] && confirm "Hapus '$del_name' dari PM2?"; then
        pm2 delete "$del_name" 2>/dev/null && success "Aplikasi '$del_name' dihapus dari PM2."
    fi
}

_pm2_logs_app() {
    local log_name=""
    read -rp "  Nama atau ID aplikasi: " log_name
    if [[ -n "$log_name" ]]; then
        info "Menampilkan log 50 baris terakhir:"
        pm2 logs "$log_name" --lines 50 --nostream 2>/dev/null
        echo -e "\n  ${YELLOW}Tip: Jalankan 'pm2 logs $log_name' di terminal untuk streaming live${NC}"
    fi
}
