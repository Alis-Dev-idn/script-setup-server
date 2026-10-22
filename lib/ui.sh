#!/bin/bash
# ============================================================
#  lib/ui.sh — Desain UI & Terminal CLI Modern
#  Sesuai spesifikasi design/cli-ux-specification.md
# ============================================================
[[ -n "${_LIB_UI_LOADED:-}" ]] && return 0
_LIB_UI_LOADED=1

# ---------- Palet Warna Semantic (ANSI 256 Colors Fallback) ----------
PRIMARY='\033[38;5;39m'     # Cyan Bright
SUCCESS='\033[38;5;82m'     # Neon Green
WARNING='\033[38;5;214m'    # Warm Amber
DANGER='\033[38;5;196m'     # Vivid Red
MUTED='\033[38;5;244m'      # Medium Gray
TEXT='\033[38;5;255m'       # White
ACCENT='\033[38;5;141m'     # Soft Violet
BOLD='\033[1m'
NC='\033[0m'

# Simbol Glyphs
GLYPH_CHECK="✔"
GLYPH_WARN="⚠"
GLYPH_CROSS="✖"
GLYPH_ARROW="➜"
GLYPH_BULLET="•"

# Header Box Modern
ui_header() {
    local title="${1:-SETUP SERVER}"
    local subtitle="${2:-}"
    local width=63
    local line_top="╭$(printf '─%.0s' $(seq 1 $width))╮"
    local line_bot="╰$(printf '─%.0s' $(seq 1 $width))╯"

    echo -e "${PRIMARY}${line_top}${NC}"
    printf "${PRIMARY}│${NC}  ${BOLD}%-40s${NC} ${ACCENT}%19s${NC} ${PRIMARY}│${NC}\n" "$title" "v1.1.0-modular"
    if [[ -n "$subtitle" ]]; then
        printf "${PRIMARY}│${NC}  ${MUTED}%-60s${NC} ${PRIMARY}│${NC}\n" "$subtitle"
    else
        local os_info="Linux $(uname -m 2>/dev/null || echo 'x86_64')"
        if [[ -f /etc/os-release ]]; then
            os_info="$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"') • ${os_info}"
        fi
        printf "${PRIMARY}│${NC}  ${MUTED}%-60s${NC} ${PRIMARY}│${NC}\n" "$os_info"
    fi
    echo -e "${PRIMARY}${line_bot}${NC}"
    echo
}

# Inisiasi Step Progress
ui_step_start() {
    local step="$1"
    local total="$2"
    local desc="$3"
    local width=61
    local header_text="── [${step}/${total}] ${desc} "
    local len=${#header_text}
    local fill_len=$(( width - len ))
    [[ $fill_len -lt 2 ]] && fill_len=2
    local fill_line
    fill_line="$(printf '─%.0s' $(seq 1 $fill_len))"

    echo -e "${PRIMARY}╭${header_text}${fill_line}╮${NC}"
    echo -e "${PRIMARY}│${NC}"
}

ui_step_end() {
    local width=63
    local line_bot="╰$(printf '─%.0s' $(seq 1 $width))╯"
    echo -e "${PRIMARY}│${NC}"
    echo -e "${PRIMARY}${line_bot}${NC}"
    echo
}

# Menjalankan Task dengan Single-Line In-Place Spinner & Anti Wall-of-Text
ui_run_task() {
    local task_desc="$1"
    shift
    local log_file
    log_file="$(mktemp /tmp/setup-server-task-XXXXXX.log 2>/dev/null || echo "/tmp/setup-server-task-$$.log")"

    local start_time
    start_time="$(date +%s)"

    # Fallback jika non-TTY
    if [[ ! -t 1 && ! -t 2 ]]; then
        echo -e "  ${ACCENT}${GLYPH_ARROW}${NC} ${task_desc}..."
        "$@" >"$log_file" 2>&1
        local rc=$?
        local end_time; end_time="$(date +%s)"
        local elapsed=$(( end_time - start_time ))
        if [[ $rc -eq 0 ]]; then
            echo -e "  ${SUCCESS}${GLYPH_CHECK}${NC} ${task_desc} (${elapsed}s)"
            rm -f "$log_file"
        else
            echo -e "  ${DANGER}${GLYPH_CROSS}${NC} ${task_desc} (${elapsed}s)"
            ui_card_error "Gagal mengeksekusi: ${task_desc}" "$log_file"
        fi
        return $rc
    fi

    # Eksekusi background
    "$@" >"$log_file" 2>&1 &
    local pid=$!

    local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    printf '\033[?25l' >&2

    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i + 1) % ${#frames} ))
        printf "\r  ${PRIMARY}%s${NC} %s" "${frames:$i:1}" "$task_desc" >&2
        sleep 0.08
    done

    wait "$pid"
    local rc=$?
    local end_time
    end_time="$(date +%s)"
    local elapsed=$(( end_time - start_time ))

    printf '\033[?25h' >&2

    if [[ $rc -eq 0 ]]; then
        printf "\r\033[K  ${SUCCESS}${GLYPH_CHECK}${NC} %s ${MUTED}(%ds)${NC}\n" "$task_desc" "$elapsed" >&2
        rm -f "$log_file"
    else
        printf "\r\033[K  ${DANGER}${GLYPH_CROSS}${NC} %s ${MUTED}(%ds)${NC}\n" "$task_desc" "$elapsed" >&2
        ui_card_error "Langkah gagal: ${task_desc}" "$log_file"
    fi

    return $rc
}

# Tampilan Card Error Collapsible
ui_card_error() {
    local err_msg="$1"
    local log_file="$2"
    local width=63
    local line_top="╭── ${DANGER}${GLYPH_CROSS} Terjadi Kesalahan${NC} $(printf '─%.0s' $(seq 1 40))╮"
    local line_bot="╰$(printf '─%.0s' $(seq 1 $width))╯"

    echo
    echo -e "${DANGER}${line_top}${NC}"
    echo -e "${DANGER}│${NC}  ${BOLD}${err_msg}${NC}"
    echo -e "${DANGER}│${NC}"
    if [[ -f "$log_file" && -s "$log_file" ]]; then
        echo -e "${DANGER}│${NC}  ${MUTED}Cuplikan Log Error (10 baris terakhir):${NC}"
        while IFS= read -r line; do
            printf "${DANGER}│${NC}  ${MUTED}│${NC} %-56.56s\n" "$line"
        done < <(tail -n 10 "$log_file")
        echo -e "${DANGER}│${NC}"
        echo -e "${DANGER}│${NC}  Log lengkap disimpan di: ${WARNING}${log_file}${NC}"
    else
        echo -e "${DANGER}│${NC}  Tidak ada detail log yang terekam."
    fi
    echo -e "${DANGER}${line_bot}${NC}"
    echo
}

# Tampilan Card Sukses
ui_card_success() {
    local msg="$1"
    local width=63
    local line_top="╭$(printf '─%.0s' $(seq 1 $width))╮"
    local line_bot="╰$(printf '─%.0s' $(seq 1 $width))╯"

    echo
    echo -e "${SUCCESS}${line_top}${NC}"
    printf "${SUCCESS}│${NC}  ${SUCCESS}${GLYPH_CHECK}${NC} ${BOLD}%-58s${NC} ${SUCCESS}│${NC}\n" "$msg"
    echo -e "${SUCCESS}${line_bot}${NC}"
    echo
}

# Prompt Pilihan Interaktif
ui_prompt_choice() {
    local label="${1:-Masukkan pilihan}"
    local min="${2:-0}"
    local max="${3:-9}"
    local out_var="${4:-CHOICE}"
    local val=""

    while true; do
        read -rp "  ${PRIMARY}${GLYPH_ARROW}${NC} ${label} [${min}-${max}]: " val
        if [[ "$val" =~ ^[0-9]+$ ]] && [[ "$val" -ge "$min" ]] && [[ "$val" -le "$max" ]]; then
            eval "$out_var=\"\$val\""
            return 0
        fi
        echo -e "  ${WARNING}${GLYPH_WARN} Input tidak valid. Masukkan angka antara ${min} dan ${max}.${NC}"
    done
}
