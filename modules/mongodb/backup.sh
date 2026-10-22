#!/bin/bash
# ============================================================
#  modules/mongodb/backup.sh — Backup & Restore Database
# ============================================================
[[ -n "${_MONGODB_BACKUP_LOADED:-}" ]] && return 0
_MONGODB_BACKUP_LOADED=1

backup_db() {
    show_banner
    echo -e "${BLD}  [4] Backup Database${NC}"; line
    prepare_conn; echo

    info "Daftar database yang tersedia:"
    mongo_exec "db.adminCommand({listDatabases:1}).databases.forEach(d => print('    - ' + d.name))" admin
    echo

    local bkp_db="" bkp_dir="/tmp/mongo_backup"
    read -rp "  Nama database yang di-backup (kosong = semua): " bkp_db
    read -rp "  Direktori tujuan backup [/tmp/mongo_backup]: " bkp_dir
    bkp_dir="${bkp_dir:-/tmp/mongo_backup}"

    echo
    if [[ -n "$bkp_db" ]]; then
        info "Collections yang akan di-backup dari '$bkp_db':"
        mongo_exec "
            db = db.getSiblingDB('$bkp_db');
            var cols = db.getCollectionInfos();
            if (cols.length === 0) { print('    (belum ada collection)'); }
            cols.forEach(function(c) { print('    - ' + c.name); });
        " admin
    else
        info "Akan membackup SEMUA database."
    fi
    echo

    local timestamp; timestamp=$(date +%Y%m%d_%H%M%S)
    local out_dir="${bkp_dir}/${timestamp}"
    mkdir -p "$out_dir"

    local auth_args=""
    [[ "$MONGO_AUTH" == "yes" && -n "$MONGO_ADMIN_USER" ]] && \
        auth_args="-u $MONGO_ADMIN_USER -p $MONGO_ADMIN_PASS --authenticationDatabase admin"

    if [[ -n "$bkp_db" ]]; then
        run_with_spinner "Membackup database '$bkp_db'..." \
            mongodump --host "$MONGO_HOST" --port "$MONGO_PORT" $auth_args --db "$bkp_db" --out "$out_dir"
    else
        run_with_spinner "Membackup semua database..." \
            mongodump --host "$MONGO_HOST" --port "$MONGO_PORT" $auth_args --out "$out_dir"
    fi

    info "Mengompres backup..."
    local archive="${bkp_dir}/backup_${timestamp}.tar.gz"
    tar -czf "$archive" -C "$bkp_dir" "$timestamp"
    rm -rf "$out_dir"

    echo; line
    success "Backup selesai!"
    echo "    File  : $archive"
    echo "    Ukuran: $(du -sh "$archive" | cut -f1)"
    line; pause
}

_inspect_backup_dir() {
    local dir="$1"
    _DB_DIRS=()
    _FLAT_MODE="no"

    local sub=""
    while IFS= read -r sub; do
        _DB_DIRS+=("$(basename "$sub")")
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

    if [[ ${#_DB_DIRS[@]} -gt 0 ]]; then
        info "Isi backup terdeteksi (${#_DB_DIRS[@]} database):"
        local db_name="" col=""
        for db_name in "${_DB_DIRS[@]}"; do
            echo "    - $db_name"
            while IFS= read -r col; do
                echo "        - $(basename "$col" .bson)"
            done < <(find "$dir/$db_name" -maxdepth 1 -name '*.bson' 2>/dev/null | sort)
        done
        return 0
    fi

    local has_bson=""
    has_bson=$(find "$dir" -maxdepth 1 -name '*.bson' 2>/dev/null | head -1)
    if [[ -n "$has_bson" ]]; then
        _FLAT_MODE="yes"
        info "Isi backup terdeteksi (1 database, tanpa subfolder):"
        local col=""
        while IFS= read -r col; do
            echo "    - $(basename "$col" .bson)"
        done < <(find "$dir" -maxdepth 1 -name '*.bson' 2>/dev/null | sort)
        return 0
    fi

    return 1
}

restore_db() {
    show_banner
    echo -e "${BLD}  [5] Restore Database${NC}"; line
    prepare_conn; echo

    local rst_path=""
    read -rp "  Path file backup (.tar.gz atau direktori): " rst_path
    [[ -z "$rst_path" ]] && { error "Path tidak boleh kosong."; pause; return 0; }
    [[ ! -e "$rst_path" ]] && { error "File/direktori '$rst_path' tidak ditemukan."; pause; return 0; }

    local auth_args=""
    [[ "$MONGO_AUTH" == "yes" && -n "$MONGO_ADMIN_USER" ]] && \
        auth_args="-u $MONGO_ADMIN_USER -p $MONGO_ADMIN_PASS --authenticationDatabase admin"

    local tmp_dir="" rst_dir="$rst_path"
    if [[ "$rst_path" == *.tar.gz ]]; then
        tmp_dir="/tmp/mongo_restore_$$"
        mkdir -p "$tmp_dir"
        info "Mengekstrak backup..."
        tar -xzf "$rst_path" -C "$tmp_dir"
        rst_dir=$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | head -1)
        [[ -z "$rst_dir" ]] && rst_dir="$tmp_dir"
    fi

    echo
    if ! _inspect_backup_dir "$rst_dir"; then
        error "Tidak ditemukan data backup yang valid di '$rst_dir'."
        [[ -n "$tmp_dir" && -d "$tmp_dir" ]] && rm -rf "$tmp_dir"
        pause; return 0
    fi
    echo

    local src_db="" src_path="$rst_dir"
    _select_restore_source "$rst_dir" src_db src_path || {
        [[ -n "$tmp_dir" && -d "$tmp_dir" ]] && rm -rf "$tmp_dir"
        pause; return 0
    }

    local rst_db="" confirm=""
    read -rp "  Nama database tujuan (kosong = ${src_db:-sesuai backup}): " rst_db
    [[ -z "$rst_db" ]] && rst_db="$src_db"

    warn "PERINGATAN: Data yang ada pada database tujuan akan ditimpa!"
    read -rp "  Ketik 'RESTORE' untuk konfirmasi: " confirm
    if [[ "$confirm" != "RESTORE" ]]; then
        warn "Dibatalkan."
        [[ -n "$tmp_dir" && -d "$tmp_dir" ]] && rm -rf "$tmp_dir"
        pause; return 0
    fi

    local rc=0
    if [[ -n "$rst_db" ]]; then
        run_with_spinner "Merestore ke database '$rst_db'..." \
            mongorestore --host "$MONGO_HOST" --port "$MONGO_PORT" $auth_args --db "$rst_db" --drop "$src_path"
        rc=$?
    else
        run_with_spinner "Merestore semua database..." \
            mongorestore --host "$MONGO_HOST" --port "$MONGO_PORT" $auth_args --drop "$src_path"
        rc=$?
    fi

    [[ -n "$tmp_dir" && -d "$tmp_dir" ]] && rm -rf "$tmp_dir"
    echo
    [[ $rc -eq 0 ]] && success "Restore selesai!" || error "Restore gagal (exit code $rc)."
    pause
}

_select_restore_source() {
    local rst_dir="$1"
    local -n r_db=$2 r_path=$3

    if [[ "$_FLAT_MODE" == "yes" ]]; then
        r_db=""
        r_path="$rst_dir"
        return 0
    elif [[ ${#_DB_DIRS[@]} -eq 1 ]]; then
        r_db="${_DB_DIRS[0]}"
        r_path="$rst_dir/$r_db"
        return 0
    fi

    echo "  Ditemukan beberapa database dalam backup ini:"
    local i=1 db_name=""
    for db_name in "${_DB_DIRS[@]}"; do
        echo "    $i) $db_name"
        i=$((i+1))
    done
    echo "    0) Semua database"
    local db_choice=""
    read -rp "  Pilih database yang akan direstore (kosong = semua): " db_choice
    if [[ -z "$db_choice" || "$db_choice" == "0" ]]; then
        r_db=""
        r_path="$rst_dir"
        return 0
    elif [[ "$db_choice" =~ ^[0-9]+$ ]] && (( db_choice >= 1 && db_choice <= ${#_DB_DIRS[@]} )); then
        r_db="${_DB_DIRS[$((db_choice - 1))]}"
        r_path="$rst_dir/$r_db"
        return 0
    else
        error "Pilihan tidak valid."
        return 1
    fi
}
