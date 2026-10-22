#!/bin/bash
# ============================================================
#  modules/mongodb/user.sh — RBAC User Management
# ============================================================
[[ -n "${_MONGODB_USER_LOADED:-}" ]] && return 0
_MONGODB_USER_LOADED=1

_list_users() {
    info "Daftar user yang terdaftar:\n"
    mongo_exec "
        var users = db.system.users.find({}, {user:1, db:1, roles:1, _id:0}).toArray();
        if (users.length === 0) { print('    (belum ada user)'); }
        users.forEach(function(u) {
            var roles = u.roles.map(function(r){ return r.role + '@' + r.db; }).join(', ');
            print('    • ' + u.user + ' [db: ' + u.db + '] — roles: ' + roles);
        });
    " admin
}

_create_user() {
    show_banner
    echo -e "${BLD}  [2] Manage User › Buat User Baru${NC}"; line; echo
    local new_user="" new_pass="" new_pass2="" new_db="admin" role_choice="1" role="readWrite"

    read -rp "  Nama user baru: " new_user
    [[ -z "$new_user" ]] && { error "Username tidak boleh kosong."; pause; return 0; }

    while true; do
        read -rsp "  Password: " new_pass; echo
        read -rsp "  Konfirmasi password: " new_pass2; echo
        [[ "$new_pass" == "$new_pass2" && -n "$new_pass" ]] && break
        error "Password tidak cocok atau kosong, coba lagi."
    done

    read -rp "  Database target [admin]: " new_db; new_db="${new_db:-admin}"

    echo; ask "Role:"
    echo "    1) readWrite            — baca & tulis (default)"
    echo "    2) read                 — hanya baca"
    echo "    3) dbAdmin              — admin 1 database"
    echo "    4) dbOwner              — pemilik penuh 1 database"
    echo "    5) readWriteAnyDatabase — baca-tulis semua DB"
    echo "    6) userAdminAnyDatabase — admin semua user"
    read -rp "  Pilihan [1]: " role_choice
    case "$role_choice" in
        2) role="read" ;;
        3) role="dbAdmin" ;;
        4) role="dbOwner" ;;
        5) role="readWriteAnyDatabase" ;;
        6) role="userAdminAnyDatabase" ;;
        *) role="readWrite" ;;
    esac

    mongo_exec "
        db = db.getSiblingDB('$new_db');
        db.createUser({ user: '$new_user', pwd: '$new_pass', roles: [{ role: '$role', db: '$new_db' }] });
        print('User berhasil dibuat.');
    " admin

    echo; line
    success "User '$new_user' berhasil dibuat!"
    echo "    Database : $new_db  |  Role: $role"
    echo -e "\n  Koneksi:\n  ${CYN}mongosh mongodb://${new_user}:${new_pass}@${MONGO_HOST}:${MONGO_PORT}/${new_db}${NC}"
    line; pause
}

_update_user() {
    show_banner
    echo -e "${BLD}  [2] Manage User › Update User${NC}"; line; echo
    _list_users; echo
    local upd_user="" upd_db="admin" upd_choice="" new_pass_upd="" new_role_upd="" js_update=""

    read -rp "  Nama user yang akan diupdate: " upd_user
    [[ -z "$upd_user" ]] && { error "Username tidak boleh kosong."; pause; return 0; }
    read -rp "  Database user tersebut [admin]: " upd_db; upd_db="${upd_db:-admin}"

    echo; ask "Apa yang ingin diupdate? (1=Password, 2=Role, 1,2=Keduanya)"
    read -rp "  Pilihan: " upd_choice

    if [[ "$upd_choice" == *"1"* ]]; then
        local p1="" p2=""
        while true; do
            read -rsp "  Password baru: " p1; echo
            read -rsp "  Konfirmasi password: " p2; echo
            [[ "$p1" == "$p2" && -n "$p1" ]] && { new_pass_upd="$p1"; break; }
            error "Password tidak cocok, coba lagi."
        done
        js_update="${js_update} updateFields.pwd = '$new_pass_upd';"
    fi

    if [[ "$upd_choice" == *"2"* ]]; then
        local rc="1"
        read -rp "  Role baru (1=readWrite, 2=read, 3=dbAdmin, 4=dbOwner, 5=readWriteAny, 6=userAdminAny) [1]: " rc
        case "$rc" in
            2) new_role_upd="read" ;;
            3) new_role_upd="dbAdmin" ;;
            4) new_role_upd="dbOwner" ;;
            5) new_role_upd="readWriteAnyDatabase" ;;
            6) new_role_upd="userAdminAnyDatabase" ;;
            *) new_role_upd="readWrite" ;;
        esac
        js_update="${js_update} updateFields.roles = [{ role: '$new_role_upd', db: '$upd_db' }];"
    fi

    [[ -z "$js_update" ]] && { warn "Tidak ada perubahan yang dipilih."; pause; return 0; }

    mongo_exec "
        db = db.getSiblingDB('$upd_db');
        var updateFields = {};
        ${js_update}
        db.updateUser('$upd_user', updateFields);
        print('User berhasil diupdate.');
    " admin
    echo; success "User '$upd_user' berhasil diupdate."; pause
}

_reset_password() {
    show_banner
    echo -e "${BLD}  [2] Manage User › Reset Password${NC}"; line; echo
    _list_users; echo
    local rst_user="" rst_db="admin" rst_pass="" rst_pass2=""

    read -rp "  Nama user: " rst_user
    [[ -z "$rst_user" ]] && { error "Username tidak boleh kosong."; pause; return 0; }
    read -rp "  Database user tersebut [admin]: " rst_db; rst_db="${rst_db:-admin}"

    while true; do
        read -rsp "  Password baru: " rst_pass; echo
        read -rsp "  Konfirmasi password: " rst_pass2; echo
        [[ "$rst_pass" == "$rst_pass2" && -n "$rst_pass" ]] && break
        error "Password tidak cocok, coba lagi."
    done

    mongo_exec "
        db = db.getSiblingDB('$rst_db');
        db.updateUser('$rst_user', { pwd: '$rst_pass' });
        print('Password berhasil direset.');
    " admin
    echo; success "Password user '$rst_user' berhasil direset."; pause
}

_delete_user() {
    show_banner
    echo -e "${BLD}  [2] Manage User › Hapus User${NC}"; line; echo
    _list_users; echo
    local del_user="" del_db="admin" confirm=""

    read -rp "  Nama user yang akan dihapus: " del_user
    [[ -z "$del_user" ]] && { error "Username tidak boleh kosong."; pause; return 0; }
    read -rp "  Database user tersebut [admin]: " del_db; del_db="${del_db:-admin}"

    warn "PERINGATAN: User '$del_user' akan dihapus permanen dari database '$del_db'!"
    read -rp "  Ketik 'HAPUS' untuk konfirmasi: " confirm
    [[ "$confirm" != "HAPUS" ]] && { warn "Dibatalkan."; pause; return 0; }

    mongo_exec "
        db = db.getSiblingDB('$del_db');
        db.dropUser('$del_user');
        print('User berhasil dihapus.');
    " admin
    echo; success "User '$del_user' berhasil dihapus."; pause
}

_change_role() {
    show_banner
    echo -e "${BLD}  [2] Manage User › Ganti Role${NC}"; line; echo
    _list_users; echo
    local chr_user="" chr_db="admin" role_choice="1" new_role="readWrite"

    read -rp "  Nama user: " chr_user
    [[ -z "$chr_user" ]] && { error "Username tidak boleh kosong."; pause; return 0; }
    read -rp "  Database user tersebut [admin]: " chr_db; chr_db="${chr_db:-admin}"

    echo; ask "Role baru:"
    echo "    1) readWrite            — baca & tulis (default)"
    echo "    2) read                 — hanya baca"
    echo "    3) dbAdmin              — admin 1 database"
    echo "    4) dbOwner              — pemilik penuh 1 database"
    echo "    5) readWriteAnyDatabase — baca-tulis semua DB"
    echo "    6) userAdminAnyDatabase — admin semua user"
    read -rp "  Pilihan [1]: " role_choice
    case "$role_choice" in
        2) new_role="read" ;;
        3) new_role="dbAdmin" ;;
        4) new_role="dbOwner" ;;
        5) new_role="readWriteAnyDatabase" ;;
        6) new_role="userAdminAnyDatabase" ;;
        *) new_role="readWrite" ;;
    esac

    mongo_exec "
        db = db.getSiblingDB('$chr_db');
        db.updateUser('$chr_user', { roles: [{ role: '$new_role', db: '$chr_db' }] });
        print('Role berhasil diubah.');
    " admin
    echo; success "Role user '$chr_user' diubah menjadi '$new_role'."; pause
}

manage_user_menu() {
    prepare_conn
    local choice=""
    while true; do
        show_banner
        echo -e "${BLD}  [2] Manage User${NC}"; line; echo
        _list_users; echo; line
        echo -e "  ${BLD}Pilih aksi:${NC}\n"
        echo "    1)  Buat user baru"
        echo "    2)  Update user (password & role)"
        echo "    3)  Reset password"
        echo "    4)  Hapus user"
        echo "    5)  Ganti role"
        echo "    6)  Kembali ke menu utama\n"; line
        read -rp "  Pilihan [1-6]: " choice
        case "$choice" in
            1) _create_user ;;
            2) _update_user ;;
            3) _reset_password ;;
            4) _delete_user ;;
            5) _change_role ;;
            6) return 0 ;;
            *) warn "Pilihan tidak valid."; sleep 1 ;;
        esac
    done
}
