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
  --check        only show what would be updated, change nothing
  --no-build     update configs only, do not rebuild Quickshell / Waybar / tools
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
        if [[ "$rel" == .local/share/* ]]; then
            continue
        fi
        if cmp -s "$src" "$dst"; then
            install -Dm644 "$src" "$base"
            continue
        fi
        if [[ ! -f "$base" ]]; then
            install -Dm644 "$src" "$dst.snowflake-new"
            install -Dm644 "$src" "$base"
            unknown+=("$rel")
            continue
        fi
        if cmp -s "$dst" "$base"; then
            install -Dm644 "$src" "$dst"
            install -Dm644 "$src" "$base"
            updated=$((updated + 1))
            continue
        fi
        if cmp -s "$src" "$base"; then
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
rebuild_changed() {
    step "Rebuilding what changed"
    local name now was any=0
    for name in "${COMPONENTS[@]}"; do
        now="$(fingerprint "$name")"
        was="$(installed_fingerprint "$name")"
        [[ "$now" == "$was" ]] && continue
        any=1
        case "$name" in
            hyprland)
                if [[ -n "$was" ]]; then
                    warn "The Hyprland part of Snowflake changed. It is rebuilt only by: bash install.sh"
                else
                    record_component hyprland
                fi
                ;;
            quickshell) install_quickshell; record_component quickshell ;;
            waybar)     install_waybar; record_component waybar ;;
            wofi)       install_wofi; record_component wofi ;;
            hyprshot)   install_hyprshot; record_component hyprshot ;;
            matugen)    install_matugen; record_component matugen ;;
        esac
    done
    (( any )) || ok "Nothing to rebuild"
}

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
        --no-build) NO_BUILD=1 ;;
        --pulled) PULLED=1 ;;
        -h | --help) usage; exit 0 ;;
        *) usage; die "Unknown option: $1" ;;
    esac
    shift
done

if [[ "$MODE" == check ]]; then
    check_only
    exit 0
fi

if (( ! PULLED )); then
    pull_repo
    args=(--pulled)
    if [[ "$MODE" == reset ]]; then args+=(--reset); fi
    if (( NO_BUILD )); then args+=(--no-build); fi
    exec bash "$REPO_DIR/update.sh" "${args[@]}"
fi

mkdir -p "$BUILD_DIR"
LOG="$BUILD_DIR/update-$(date +%F-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

(( EUID != 0 )) || die "Run as your normal user, not root."
sudo -v
install_packages
if (( ! NO_BUILD )); then
    rebuild_changed
fi
if [[ "$MODE" == reset ]]; then
    reset_dots
else
    merge_dots
fi
regenerate_colors
enable_services
restart_session_parts

printf '\n\033[1;32mSnowflake is updated.\033[0m\n'
printf 'Log: %s\n' "$LOG"
