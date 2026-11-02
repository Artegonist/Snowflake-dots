#!/usr/bin/env bash
set -Eeuo pipefail

# ------------------------- CONFIG -------------------------
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODE="update"
PULLED=0
NO_BUILD=0
LOG="(no log yet)"

source "$REPO_DIR/install.sh"

usage() {
    cat <<EOF
Usage: ${0##*/} [options]

  (no option)    update: keep your own changes (binds, settings) and merge new ones in
  --reset        reinstall configs: everything back to the Snowflake defaults (with a backup)
  --check        only show which new commits are on GitHub, change nothing
  --dry-run      show what update would do with your files, change nothing
  --no-build     update configs only, do not rebuild Quickshell / Waybar / tools
  --yes          do not ask before --reset
  --full-log     show the full build output instead of progress lines
  -h, --help     show this help
EOF
}

# ------------------------- PULL -------------------------
pull_repo() {
    step "Downloading the new Snowflake version"
    git -C "$REPO_DIR" diff --quiet && git -C "$REPO_DIR" diff --cached --quiet \
        || die "The Snowflake-dots folder has local changes. Commit or stash them, or run: git -C \"$REPO_DIR\" stash"
    local before after
    before="$(git -C "$REPO_DIR" rev-parse HEAD)"
    git -C "$REPO_DIR" pull --ff-only
    after="$(git -C "$REPO_DIR" rev-parse HEAD)"
    if [[ "$before" == "$after" ]]; then
        ok "Already the latest version"
    else
        ok "Updated $(git -C "$REPO_DIR" rev-list --count "$before..$after") commit(s)"
    fi
}

check_only() {
    step "Checking for updates"
    git -C "$REPO_DIR" fetch --quiet
    local ahead
    ahead="$(git -C "$REPO_DIR" rev-list --count 'HEAD..@{u}')"
    if (( ahead == 0 )); then
        ok "Snowflake is up to date"
        return 0
    fi
    info "$ahead new commit(s):"
    git -C "$REPO_DIR" log --oneline 'HEAD..@{u}'
    info "Files that change:"
    git -C "$REPO_DIR" diff --stat 'HEAD..@{u}'
}

# ------------------------- CONFIGS -------------------------
GENERATED_FILES=(
    .config/hypr/colors.conf
    .config/waybar/colors.css
    .config/wofi/colors.css
    .config/quickshell/snowflake/colors.json
    .config/quickshell/clipboard-module/colors.json
)

is_generated() {
    local g
    for g in "${GENERATED_FILES[@]}"; do [[ "$1" == "$g" ]] && return 0; done
    return 1
}

same_content() {
    cmp -s <(sed -e '$a\' "$1") <(sed -e '$a\' "$2")
}
merge_dots() {
    step "Updating configs, keeping your changes"
    local backup="$HOME/.snowflake-backup/$(date +%F-%H%M%S)" src rel dst base tmp
    local updated=0 kept=0 merged=0 conflicts=() unknown=()

    while IFS= read -r -d '' src; do
        rel="${src#"$REPO_DIR"/}"
        dst="$HOME/$rel"
        base="$BASE_DIR/$rel"

        if [[ ! -e "$dst" ]]; then
            install -Dm644 "$src" "$dst"
            install -Dm644 "$src" "$base"
            updated=$((updated + 1))
            continue
        fi
        if [[ "$rel" == .local/share/* ]] || is_generated "$rel"; then
            continue
        fi
        if same_content "$src" "$dst"; then
            install -Dm644 "$src" "$base"
            continue
        fi
        if [[ ! -f "$base" ]]; then
            install -Dm644 "$src" "$dst.snowflake-new"
            install -Dm644 "$src" "$base"
            unknown+=("$rel")
            continue
        fi
        if same_content "$dst" "$base"; then
            install -Dm644 "$src" "$dst"
            install -Dm644 "$src" "$base"
            updated=$((updated + 1))
            continue
        fi
        if same_content "$src" "$base"; then
            kept=$((kept + 1))
            continue
        fi

        tmp="$(mktemp)"
        cp -a "$dst" "$tmp"
        if git merge-file -q -L yours -L old -L snowflake "$tmp" "$base" "$src"; then
            mkdir -p "$backup/$(dirname "$rel")"
            cp -a "$dst" "$backup/$rel"
            install -Dm644 "$tmp" "$dst"
            install -Dm644 "$src" "$base"
            merged=$((merged + 1))
        else
            install -Dm644 "$src" "$dst.snowflake-new"
            conflicts+=("$rel")
        fi
        rm -f "$tmp"
    done < <(find "$REPO_DIR/.config" "$REPO_DIR/.local" -type f -print0)

    post_deploy
    fix_temperature_sensor
    ok "$updated updated, $merged merged with your changes, $kept kept as you changed them"
    if (( merged )); then
        info "Copies of files before merging are in $backup"
    fi
    if (( ${#conflicts[@]} )); then
        warn "Your changes and the update touch the same lines, your version was kept:"
        for rel in "${conflicts[@]}"; do warn "   ~/$rel  → new version in ~/$rel.snowflake-new"; done
    fi
    if (( ${#unknown[@]} )); then
        warn "These files differ from Snowflake and were installed before update.sh existed, your version was kept:"
        for rel in "${unknown[@]}"; do warn "   ~/$rel  → new version in ~/$rel.snowflake-new"; done
        info "From the next update on these files are merged automatically."
    fi
}

reset_dots() {
    step "Resetting configs to the Snowflake defaults"
    FORCE_LOCAL=1 deploy_dots
    local f
    while IFS= read -r -d '' f; do
        rm -f "$f"
    done < <(find "$HOME/.config" -name '*.snowflake-new' -print0 2>/dev/null)
    fix_temperature_sensor
}

plan_dots() {
    step "Dry run: what would happen to your files (nothing is changed)"
    local src rel dst base
    local -a new=() replace=() merge=() keep=() conflict=() unknown=()

    while IFS= read -r -d '' src; do
        rel="${src#"$REPO_DIR"/}"
        dst="$HOME/$rel"
        base="$BASE_DIR/$rel"
        if [[ ! -e "$dst" ]]; then new+=("$rel"); continue; fi
        [[ "$rel" == .local/share/* ]] && continue
        is_generated "$rel" && continue
        same_content "$src" "$dst" && continue
        if [[ ! -f "$base" ]]; then unknown+=("$rel"); continue; fi
        if same_content "$dst" "$base"; then replace+=("$rel"); continue; fi
        if same_content "$src" "$base"; then keep+=("$rel"); continue; fi
        if git merge-file -p -q "$dst" "$base" "$src" >/dev/null 2>&1; then
            merge+=("$rel")
        else
            conflict+=("$rel")
        fi
    done < <(find "$REPO_DIR/.config" "$REPO_DIR/.local" -type f -print0)

    local rel_
    if (( ${#new[@]} )); then info "Would be added (${#new[@]}):"; for rel_ in "${new[@]}"; do printf '     ~/%s\n' "$rel_"; done; fi
    if (( ${#replace[@]} )); then info "Would be replaced, you never changed them (${#replace[@]}):"; for rel_ in "${replace[@]}"; do printf '     ~/%s\n' "$rel_"; done; fi
    if (( ${#merge[@]} )); then info "Would be merged with your changes (${#merge[@]}):"; for rel_ in "${merge[@]}"; do printf '     ~/%s\n' "$rel_"; done; fi
    if (( ${#keep[@]} )); then info "Kept as you changed them (${#keep[@]}):"; for rel_ in "${keep[@]}"; do printf '     ~/%s\n' "$rel_"; done; fi
    if (( ${#conflict[@]} )); then warn "Conflict, your version kept + .snowflake-new next to it (${#conflict[@]}):"; for rel_ in "${conflict[@]}"; do printf '     ~/%s\n' "$rel_" >&2; done; fi
    if (( ${#unknown[@]} )); then warn "Differ from Snowflake, no record of the last install, your version kept + .snowflake-new (${#unknown[@]}):"; for rel_ in "${unknown[@]}"; do printf '     ~/%s\n' "$rel_" >&2; done; fi
    if (( ${#new[@]} + ${#replace[@]} + ${#merge[@]} + ${#keep[@]} + ${#conflict[@]} + ${#unknown[@]} == 0 )); then ok "Your configs already match Snowflake"; fi

    step "Dry run: what would be rebuilt"
    local name now was any=0
    for name in "${COMPONENTS[@]}"; do
        now="$(fingerprint "$name")"
        was="$(installed_fingerprint "$name")"
        [[ "$now" == "$was" ]] && continue
        any=1
        if [[ "$name" == hyprland ]]; then
            if [[ -n "$was" ]]; then info "hyprland: changed, would only warn (rebuilt by install.sh)"; fi
        elif [[ -z "$was" ]]; then
            info "$name: would be rebuilt (no record of how it was installed)"
        else
            info "$name: would be rebuilt (new version or patch)"
        fi
    done
    (( any )) || ok "Nothing would be rebuilt"
    info "Dry run finished, nothing was changed. Run without --dry-run to apply."
}

# ------------------------- COLORS -------------------------
regenerate_colors() {
    step "Colors"
    local wt="${XDG_DATA_HOME:-$HOME/.local/share}/snowflake/hub/wallpaper-theme.json"
    local wt_cache="${XDG_CACHE_HOME:-$HOME/.cache}/hub-module/wallpaper-theme.json"
    local name=""

    if [[ "$MODE" == reset ]]; then
        apply_theme
        return 0
    fi
    if [[ -f "$wt" && -f "$wt_cache" ]] && [[ "$(jq -r '.active // false' "$wt" 2>/dev/null)" == true ]]; then
        matugen json "$wt_cache" || warn "matugen reported errors"
        ok "Colors regenerated from your wallpaper theme"
        return 0
    fi
    [[ -r "$HOME/.cache/hub-module/theme_name" ]] && IFS= read -r name < "$HOME/.cache/hub-module/theme_name"
    if [[ -n "$name" && -f "$HOME/.config/matugen/themes/$name.json" ]]; then
        THEME="$name"
    fi
    matugen json "$HOME/.config/matugen/themes/$THEME.json" || warn "matugen reported errors"
    ok "Colors regenerated for theme $THEME"
}

# ------------------------- BUILD -------------------------
# ------------------------- RESTART -------------------------
restart_session_parts() {
    step "Applying"
    if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        info "Not inside Hyprland, the changes apply at the next login"
        return 0
    fi
    hyprctl reload >/dev/null || true
    pkill -x waybar 2>/dev/null || true
    pkill -f -- 'qs -c snowflake' 2>/dev/null || true
    sleep 0.5
    hyprctl dispatch exec waybar >/dev/null
    hyprctl dispatch exec "qs -c snowflake" >/dev/null
    ok "Hyprland reloaded, Waybar and Snowflake restarted"
}

# ------------------------- MAIN -------------------------
while (( $# )); do
    case "$1" in
        --reset) MODE="reset" ;;
        --check) MODE="check" ;;
        --dry-run) MODE="dry" ;;
        --no-build) NO_BUILD=1 ;;
        --yes) UI_YES=1 ;;
        --verbose | --full-log) UI_VERBOSE=1 ;;
        --pulled) PULLED=1 ;;
        -h | --help) usage; exit 0 ;;
        *) usage; die "Unknown option: $1" ;;
    esac
    shift
done

if [[ -t 1 ]]; then UI_TTY=1; fi
ui_colors

if [[ "$MODE" == check ]]; then
    ui_banner "Snowflake update" "Checking GitHub for a new version" nologo
    check_only
    exit 0
fi

if [[ "$MODE" == dry ]]; then
    ui_banner "Snowflake update" "Dry run, nothing will be changed" nologo
    plan_dots
    exit 0
fi

if (( ! PULLED )); then
    ui_banner "Snowflake update" "Simply beautiful · keeps your own changes" nologo
    pull_repo
    args=(--pulled)
    if [[ "$MODE" == reset ]]; then args+=(--reset); fi
    if (( NO_BUILD )); then args+=(--no-build); fi
    if (( UI_YES )); then args+=(--yes); fi
    if (( UI_VERBOSE )); then args+=(--verbose); fi
    exec bash "$REPO_DIR/update.sh" "${args[@]}"
fi

(( EUID != 0 )) || die "Run as your normal user, not root."
mkdir -p "$BUILD_DIR"
ui_start "$BUILD_DIR/update-$(date +%F-%H%M%S).log"

CHANGED=()
HYPRLAND_CHANGED=0
for name in "${COMPONENTS[@]}"; do
    now="$(fingerprint "$name")"
    was="$(installed_fingerprint "$name")"
    [[ "$now" == "$was" ]] && continue
    if [[ "$name" == hyprland ]]; then
        if [[ -n "$was" ]]; then HYPRLAND_CHANGED=1; else record_component hyprland; fi
        continue
    fi
    CHANGED+=("$name")
done

printf '\n'
if [[ "$MODE" == reset ]]; then
    ui_summary_row "Mode" "reset all configs to the Snowflake defaults (backup is kept)"
else
    ui_summary_row "Mode" "update, your own changes are kept"
fi
if (( NO_BUILD )); then
    ui_summary_row "Rebuild" "skipped (--no-build)"
elif (( ${#CHANGED[@]} )); then
    ui_summary_row "Rebuild" "${CHANGED[*]}"
else
    ui_summary_row "Rebuild" "nothing changed"
fi
ui_summary_row "Log" "$LOG"
if [[ "$MODE" == reset ]] && ! ui_confirm; then
    info "Cancelled, nothing was changed."
    exit 0
fi
printf '\n'
ui_sudo_keepalive

phase_add quiet "System packages" install_packages
if (( ! NO_BUILD )); then
    for name in "${CHANGED[@]}"; do
        case "$name" in
            quickshell) phase_add quiet "Quickshell 0.3.0" p_quickshell ;;
            waybar)     phase_add quiet "Waybar 0.15.0 + Snowflake patches" p_waybar ;;
            wofi)       phase_add quiet "wofi" p_wofi ;;
            hyprshot)   phase_add quiet "hyprshot" p_hyprshot ;;
            matugen)    phase_add quiet "matugen $MATUGEN_VERSION" p_matugen ;;
        esac
    done
fi
if [[ "$MODE" == reset ]]; then
    phase_add shown "Configs, reset to defaults" reset_dots
else
    phase_add shown "Configs, merged with your changes" merge_dots
fi
phase_add quiet "Colors" regenerate_colors
phase_add shown "Services" enable_services
phase_add shown "Apply" restart_session_parts
phase_run_all

printf '\n  %s%s❄  Snowflake is updated%s  %sin %s%s\n' "$C_BOLD" "$C_ICE" "$C_RESET" "$C_DIM" "$(ui_total_time)" "$C_RESET"
if (( HYPRLAND_CHANGED )); then
    printf '     %s!%s  The Hyprland part changed, update it with: %sbash install.sh%s\n' "$C_WARN" "$C_RESET" "$C_BOLD" "$C_RESET"
fi
printf '     %sLog: %s%s\n\n' "$C_DIM" "$LOG" "$C_RESET"
