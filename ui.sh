#!/usr/bin/env bash

# ------------------------- STATE -------------------------
UI_TTY=0
UI_VERBOSE=${UI_VERBOSE:-0}
UI_YES=${UI_YES:-0}
UI_IN_PHASE=0
UI_STEP=0
UI_TOTAL=0
UI_START=$SECONDS
UI_WARN_FILE=""
UI_SUDO_PID=""
UI_PHASES=()
UI_ERR_TRAP=""
UI_PHASE_PID=""

# ------------------------- COLORS -------------------------
ui_colors() {
    if (( UI_TTY )) && [[ -z "${NO_COLOR:-}" ]]; then
        C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
        C_ICE=$'\033[38;5;153m'; C_ICE2=$'\033[38;5;117m'; C_ICE3=$'\033[38;5;111m'
        C_OK=$'\033[38;5;114m'; C_WARN=$'\033[38;5;221m'; C_ERR=$'\033[38;5;203m'
        C_MERGE=$'\033[38;5;75m'
    else
        C_RESET=""; C_BOLD=""; C_DIM=""; C_ICE=""; C_ICE2=""; C_ICE3=""
        C_OK=""; C_WARN=""; C_ERR=""; C_MERGE=""
    fi
}
ui_colors

# ------------------------- MESSAGES -------------------------
ui_pad() { (( UI_IN_PHASE )) && printf '       ' || printf '  '; }
info() { printf '%s%s::%s %s\n' "$(ui_pad)" "$C_ICE2" "$C_RESET" "$*"; }
ok()   { printf '%s%s✓%s  %s\n' "$(ui_pad)" "$C_OK" "$C_RESET" "$*"; }
warn() {
    printf '%s%s!%s  %s\n' "$(ui_pad)" "$C_WARN" "$C_RESET" "$*" >&2
    [[ -n "$UI_WARN_FILE" ]] && printf '%s\n' "$*" >> "$UI_WARN_FILE"
    return 0
}
die()  { printf '%s%s✗%s  %s\n' "$(ui_pad)" "$C_ERR" "$C_RESET" "$*" >&2; exit 1; }
step() {
    if (( UI_IN_PHASE )); then
        printf '==> %s\n' "$*" >> "${LOG:-/dev/null}"
    else
        printf '\n%s%s  ❄  %s%s\n' "$C_BOLD" "$C_ICE" "$*" "$C_RESET"
    fi
}

ui_time() {
    local s=$1
    if (( s >= 3600 )); then
        printf '%d:%02d:%02d' $((s / 3600)) $((s % 3600 / 60)) $((s % 60))
    else
        printf '%d:%02d' $((s / 60)) $((s % 60))
    fi
}

ui_tty() {
    if (( UI_TTY )); then printf "$@" >&3; else printf "$@"; fi
}

# ------------------------- BANNER -------------------------
ui_banner() {
    local title="$1" subtitle="$2" logo="$REPO_DIR/.local/share/snowflake/snowflake.txt"
    [[ "${3:-}" == nologo ]] && logo=""
    local -a shades=("$C_ICE" "$C_ICE" "$C_ICE2" "$C_ICE2" "$C_ICE3" "$C_ICE3" "$C_ICE2" "$C_ICE2" "$C_ICE")
    local line i=0 n
    printf '\n'
    if [[ -n "$logo" && -r "$logo" ]] && (( UI_TTY )); then
        n=$(wc -l < "$logo")
        while IFS= read -r line; do
            printf '  %s%s%s\n' "${shades[$(( i * ${#shades[@]} / (n + 1) ))]}" "$line" "$C_RESET"
            i=$((i + 1))
        done < "$logo"
        printf '\n'
    fi
    printf '  %s%s%s\n' "$C_BOLD$C_ICE" "$title" "$C_RESET"
    printf '  %s%s%s\n\n' "$C_DIM" "$subtitle" "$C_RESET"
}

ui_summary_row() {
    printf '  %s%-12s%s %s\n' "$C_DIM" "$1" "$C_RESET" "$2"
}

ui_confirm() {
    local answer
    (( UI_TTY )) || return 0
    [[ "${UI_YES:-0}" == 1 ]] && return 0
    printf '\n  %sContinue? [Y/n]%s ' "$C_BOLD" "$C_RESET"
    read -r answer
    [[ -z "$answer" || "${answer,,}" == y || "${answer,,}" == yes ]]
}

# ------------------------- SUDO -------------------------
ui_sudo_keepalive() {
    sudo -v || die "sudo is required"
    ( while kill -0 "$$" 2>/dev/null; do sudo -n -v 2>/dev/null; sleep 45; done ) &
    UI_SUDO_PID=$!
}

ui_interrupt() {
    if [[ -n "$UI_PHASE_PID" ]]; then
        pkill -TERM -P "$UI_PHASE_PID" 2>/dev/null
        kill -TERM "$UI_PHASE_PID" 2>/dev/null
    fi
    printf '\r\033[K\n  %s✗  Interrupted.%s Log: %s\n\n' "$C_ERR" "$C_RESET" "${LOG:-}" >&3
    exit 130
}

ui_cleanup() {
    [[ -n "$UI_SUDO_PID" ]] && kill "$UI_SUDO_PID" 2>/dev/null
    (( UI_TTY )) && printf '\033[?25h' >&3 2>/dev/null
    return 0
}

# ------------------------- PHASES -------------------------
phase_add() {
    UI_PHASES+=("$1|$2|$3")
}

phase_line() {
    local mark="$1" color="$2" label="$3" secs="$4"
    printf '  %s%s%s  %s[%2d/%d]%s  %-46s %s%s%s\n' \
        "$color" "$mark" "$C_RESET" "$C_DIM" "$UI_STEP" "$UI_TOTAL" "$C_RESET" \
        "$label" "$C_DIM" "$(ui_time "$secs")" "$C_RESET"
}

phase_warnings() {
    local w
    [[ -s "$UI_WARN_FILE" ]] || return 0
    while IFS= read -r w; do
        ui_tty '         %s!%s %s%s%s\n' "$C_WARN" "$C_RESET" "$C_DIM" "$w" "$C_RESET"
    done < "$UI_WARN_FILE"
    : > "$UI_WARN_FILE"
}

phase_fail() {
    local label="$1" secs="$2"
    ui_tty '%s' "$(phase_line "✗" "$C_ERR" "$label" "$secs")"
    ui_tty '\n'
    ui_tty '\n  %sLast lines of the log:%s\n' "$C_BOLD" "$C_RESET"
    tail -n 25 "$LOG" | sed 's/\x1b\[[0-9;?]*[A-Za-z]//g; s/^/    /' >&3
    ui_tty '\n  %sFull log:%s %s\n\n' "$C_BOLD" "$C_RESET" "$LOG"
    exit 1
}

phase_quiet() {
    local label="$1" fn="$2" start=$SECONDS pid i=0
    local -a frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    printf '\n==> %s\n' "$label" >> "$LOG"
    ( UI_IN_PHASE=1; "$fn" ) >> "$LOG" 2>&1 < /dev/null &
    pid=$!
    UI_PHASE_PID=$pid
    if (( UI_TTY )); then
        printf '\033[?25l' >&3
        while kill -0 "$pid" 2>/dev/null; do
            printf '\r  %s%s%s  %s[%2d/%d]%s  %-46s %s%s%s' \
                "$C_ICE2" "${frames[i]}" "$C_RESET" "$C_DIM" "$UI_STEP" "$UI_TOTAL" "$C_RESET" \
                "$label" "$C_DIM" "$(ui_time $((SECONDS - start)))" "$C_RESET" >&3
            i=$(( (i + 1) % ${#frames[@]} ))
            sleep 0.1
        done
        printf '\r\033[K\033[?25h' >&3
    fi
    if wait "$pid"; then
        UI_PHASE_PID=""
        ui_tty '%s' "$(phase_line "✓" "$C_OK" "$label" $((SECONDS - start)))"
        ui_tty '\n'
        phase_warnings
    else
        UI_PHASE_PID=""
        phase_fail "$label" $((SECONDS - start))
    fi
}

phase_shown() {
    local label="$1" fn="$2" start=$SECONDS rc
    printf '\n  %s❄%s  %s[%2d/%d]%s  %s%s%s\n' "$C_ICE2" "$C_RESET" "$C_DIM" "$UI_STEP" "$UI_TOTAL" "$C_RESET" \
        "$C_BOLD" "$label" "$C_RESET"
    trap - ERR
    set +e
    ( set -e; eval "$UI_ERR_TRAP"; UI_IN_PHASE=1; "$fn" )
    rc=$?
    set -e
    eval "$UI_ERR_TRAP"
    if (( rc == 0 )); then
        phase_line "✓" "$C_OK" "$label" $((SECONDS - start))
        : > "$UI_WARN_FILE"
    else
        phase_fail "$label" $((SECONDS - start))
    fi
}

phase_run_all() {
    local entry mode label fn
    UI_TOTAL=${#UI_PHASES[@]}
    UI_STEP=0
    for entry in "${UI_PHASES[@]}"; do
        IFS='|' read -r mode label fn <<<"$entry"
        UI_STEP=$((UI_STEP + 1))
        if [[ "$mode" == quiet ]] && (( ! UI_VERBOSE )); then
            phase_quiet "$label" "$fn"
        else
            phase_shown "$label" "$fn"
        fi
    done
}

# ------------------------- START -------------------------
ui_start() {
    local logfile="$1"
    [[ -t 1 ]] && UI_TTY=1
    ui_colors
    exec 3>&1
    LOG="$logfile"
    mkdir -p "$(dirname "$LOG")"
    : > "$LOG"
    UI_WARN_FILE="$(mktemp)"
    UI_START=$SECONDS
    UI_ERR_TRAP="$(trap -p ERR)"
    trap ui_cleanup EXIT
    trap ui_interrupt INT TERM
    exec > >(tee -a "$LOG") 2>&1
}

ui_total_time() {
    ui_time $((SECONDS - UI_START))
}
