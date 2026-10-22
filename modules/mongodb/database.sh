#!/bin/bash
# ============================================================
#  modules/mongodb/database.sh — Database & Collection Manager
# ============================================================
[[ -n "${_MONGODB_DATABASE_LOADED:-}" ]] && return 0
_MONGODB_DATABASE_LOADED=1

_list_databases() {
    info "Daftar database:\n"
    mongo_exec "
        var dbs = db.adminCommand({ listDatabases: 1 }).databases;
        dbs.forEach(function(d) {
            var size = (d.sizeOnDisk / 1024 / 1024).toFixed(2);
            print('    • ' + d.name + '  (' + size + ' MB)');
        });
    " admin
}

_create_database() {
    show_banner
    echo -e "${BLD}  [3] Manage Database › Buat Database${NC}"; line; echo
    local new_dbname="" new_colname="default"

    read -rp "  Nama database baru: " new_dbname
    [[ -z "$new_dbname" ]] && { error "Nama database tidak boleh kosong."; pause; return 0; }

    read -rp "  Nama collection pertama [default]: " new_colname
    new_colname="${new_colname:-default}"

    mongo_exec "
        db = db.getSiblingDB('$new_dbname');
        db.createCollection('$new_colname');
        print('Database dan collection berhasil dibuat.');
    " admin

    echo; success "Database '$new_dbname' dengan collection '$new_colname' berhasil dibuat."
    warn "MongoDB membuat database secara lazy — database muncul setelah ada data/collection."
    pause
}

_drop_database() {
    show_banner
    echo -e "${BLD}  [3] Manage Database › Hapus Database${NC}"; line; echo
    _list_databases; echo
    local drop_dbname="" confirm=""

    read -rp "  Nama database yang akan dihapus: " drop_dbname
    [[ -z "$drop_dbname" ]] && { error "Nama database tidak boleh kosong."; pause; return 0; }

    echo; warn "PERINGATAN: Database '$drop_dbname' dan SEMUA datanya akan dihapus permanen!"
    read -rp "  Ketik 'HAPUS' untuk konfirmasi: " confirm
    [[ "$confirm" != "HAPUS" ]] && { warn "Dibatalkan."; pause; return 0; }

    mongo_exec "
        db = db.getSiblingDB('$drop_dbname');
        db.dropDatabase();
        print('Database berhasil dihapus.');
    " admin
    echo; success "Database '$drop_dbname' berhasil dihapus."; pause
}

_show_collections() {
    show_banner
    echo -e "${BLD}  [3] Manage Database › Lihat Collections${NC}"; line; echo
    _list_databases; echo
    local col_db=""

    read -rp "  Nama database: " col_db
    [[ -z "$col_db" ]] && { error "Nama database tidak boleh kosong."; pause; return 0; }

    echo; info "Collections di database '$col_db':\n"
    mongo_exec "
        db = db.getSiblingDB('$col_db');
        var cols = db.getCollectionInfos();
        if (cols.length === 0) { print('    (belum ada collection)'); }
        cols.forEach(function(c) {
            var stats = db.getCollection(c.name).stats();
            var count = stats.count || 0;
            var size  = ((stats.size || 0) / 1024).toFixed(1);
            print('    • ' + c.name + '  (' + count + ' dokumen, ' + size + ' KB)');
        });
    " admin
    pause
}

_create_collection() {
    show_banner
    echo -e "${BLD}  [3] Manage Database › Buat Collection${NC}"; line; echo
    _list_databases; echo
    local cc_db="" cc_name=""

    read -rp "  Nama database target: " cc_db
    [[ -z "$cc_db" ]] && { error "Nama database tidak boleh kosong."; pause; return 0; }

    read -rp "  Nama collection baru: " cc_name
    [[ -z "$cc_name" ]] && { error "Nama collection tidak boleh kosong."; pause; return 0; }

    mongo_exec "
        db = db.getSiblingDB('$cc_db');
        db.createCollection('$cc_name');
        print('Collection berhasil dibuat.');
    " admin
    echo; success "Collection '$cc_name' berhasil dibuat di database '$cc_db'."; pause
}

_drop_collection() {
    show_banner
    echo -e "${BLD}  [3] Manage Database › Hapus Collection${NC}"; line; echo
    _list_databases; echo
    local dc_db="" dc_name="" confirm=""

    read -rp "  Nama database: " dc_db
    [[ -z "$dc_db" ]] && { error "Nama database tidak boleh kosong."; pause; return 0; }

    echo; info "Collections di '$dc_db':"
    mongo_exec "
        db = db.getSiblingDB('$dc_db');
        db.getCollectionNames().forEach(c => print('    • ' + c));
    " admin
    echo

    read -rp "  Nama collection yang akan dihapus: " dc_name
    [[ -z "$dc_name" ]] && { error "Nama collection tidak boleh kosong."; pause; return 0; }

    warn "PERINGATAN: Collection '$dc_name' dan semua isinya akan dihapus permanen!"
    read -rp "  Ketik 'HAPUS' untuk konfirmasi: " confirm
    [[ "$confirm" != "HAPUS" ]] && { warn "Dibatalkan."; pause; return 0; }

    mongo_exec "
        db = db.getSiblingDB('$dc_db');
        db.getCollection('$dc_name').drop();
        print('Collection berhasil dihapus.');
    " admin
    echo; success "Collection '$dc_name' berhasil dihapus."; pause
}

manage_database_menu() {
    prepare_conn
    local choice=""
    while true; do
        show_banner
        echo -e "${BLD}  [3] Manage Database${NC}"; line; echo
        _list_databases; echo; line
        echo -e "  ${BLD}Pilih aksi:${NC}\n"
        echo "    1)  Lihat collections dalam database"
        echo "    2)  Buat database baru"
        echo "    3)  Hapus database"
        echo "    4)  Buat collection baru"
        echo "    5)  Hapus collection"
        echo "    6)  Kembali ke menu utama\n"; line
        read -rp "  Pilihan [1-6]: " choice
        case "$choice" in
            1) _show_collections ;;
            2) _create_database ;;
            3) _drop_database ;;
            4) _create_collection ;;
            5) _drop_collection ;;
            6) return 0 ;;
            *) warn "Pilihan tidak valid."; sleep 1 ;;
        esac
    done
}
