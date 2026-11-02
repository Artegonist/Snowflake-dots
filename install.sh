#!/usr/bin/env bash
set -Eeuo pipefail

# ------------------------- CONFIG -------------------------
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SNOWFLAKE_BUILD_DIR:-$HOME/.cache/snowflake-build}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/snowflake"
BASE_DIR="$STATE_DIR/base"
INSTALLED_ENV="$STATE_DIR/installed.env"
THEME="bloodsnow"
SKIP_HYPRLAND=0
DOTS_ONLY=0

DH_REPO="https://github.com/LinuxBeginnings/Debian-Hyprland.git"
DH_REV="82f81c6f76dceb99a05f7236003244253248a1ae"
CLI11_REPO="https://github.com/CLIUtils/CLI11.git"
CLI11_REV="b595bb40e129e06368ed0b202f02de818896ec8b"
CPPTRACE_REPO="https://github.com/jeremy-rifkin/cpptrace.git"
CPPTRACE_REV="91b6b78e408a8b1c0b7146c9034a03156c082da2"
QS_REPO="https://github.com/quickshell-mirror/quickshell.git"
QS_REV="1661ef100a431a470ed2c42e6d06539b77edf826"
WAYBAR_REPO="https://github.com/Alexays/Waybar.git"
WAYBAR_REV="084d87401d0a91182c16aa7e5f674a7dde767185"
WOFI_REPO="https://hg.sr.ht/~scoopta/wofi"
WOFI_REV="d51dd3f850f6"
HYPRSHOT_REPO="https://github.com/Gustash/hyprshot.git"
HYPRSHOT_REV="f95068db7765b85a2bbae0f083e29074d7bee027"
MATUGEN_VERSION="4.1.0"
NERD_FONTS_VERSION="v3.4.0"
FLAT_REMIX_ICONS_REPO="https://github.com/daniruiz/flat-remix.git"
GTK_THEME="Adwaita"
ICON_THEME="Adwaita"
CURSOR_THEME="Flat-Remix-Blue-Dark"
CURSOR_SIZE=24

RUNTIME_PKGS=(
    git curl wget unzip jq socat python3 file
    kitty nautilus firefox-esr fastfetch
    swaybg cliphist wl-clipboard wtype grim slurp
    cava playerctl brightnessctl easyeffects
    network-manager rfkill upower power-profiles-daemon
    bluez bluez-tools
    pipewire pipewire-pulse wireplumber
    uwsm libnotify-bin sway-notification-center mate-polkit xdg-user-dirs
    xdg-desktop-portal xdg-desktop-portal-gtk
    qt6-wayland qt6-svg-plugins libqt6svg6
    qml6-module-qtquick qml6-module-qtquick-layouts qml6-module-qtquick-shapes
    qml6-module-qtquick-effects qml6-module-qtquick-window qml6-module-qtquick-controls
    qml6-module-qtquick-templates qml6-module-qtqml-models qml6-module-qtqml-workerscript
    fontconfig gsettings-desktop-schemas libglib2.0-bin
)

BUILD_PKGS=(
    build-essential cmake meson ninja-build pkgconf mercurial
    qt6-base-dev qt6-base-private-dev qt6-declarative-dev qt6-declarative-private-dev
    qt6-wayland-dev qt6-wayland-private-dev qt6-shadertools-dev qt6-svg-dev spirv-tools
    libdrm-dev libgbm-dev libegl-dev libgl-dev libvulkan-dev
    libpipewire-0.3-dev libpam0g-dev libpolkit-agent-1-dev libpolkit-gobject-1-dev
    libglib2.0-dev libjemalloc-dev libxcb1-dev libwayland-dev libwayland-bin libxkbcommon-dev
    libunwind-dev libdwarf-dev libzstd-dev
    libgtk-3-dev libgtkmm-3.0-dev libgtk-layer-shell-dev libjsoncpp-dev libsigc++-2.0-dev
    libfmt-dev libspdlog-dev libdbusmenu-gtk3-dev libepoxy-dev libfftw3-dev
    libjack-jackd2-dev libevdev-dev libinput-dev libmpdclient-dev libnl-3-dev libnl-genl-3-dev
    libpulse-dev libsystemd-dev libudev-dev libncurses-dev libplayerctl-dev scdoc libsndio-dev
    libupower-glib-dev libwireplumber-0.5-dev libxkbregistry-dev libiniparser-dev
    wayland-protocols
)

# ------------------------- OUTPUT -------------------------
source "$REPO_DIR/installer/ui.sh"

trap 'die "Failed at line $LINENO: $BASH_COMMAND (log: $LOG)"' ERR

ask() {
    local answer
    read -r -p "$1 [y/N] " answer
    [[ "${answer,,}" == y || "${answer,,}" == yes ]]
}

usage() {
    cat <<EOF
Usage: ${0##*/} [options]

  --theme NAME       default theme from .config/matugen/themes (default: $THEME)
  --skip-hyprland    do not run Debian-Hyprland (Hyprland is already installed)
  --dots-only        only copy configs, fonts and themes, build nothing
  --yes              do not ask for confirmation before starting
  --full-log         show the full build output instead of progress lines
  -h, --help         show this help
EOF
}

# ------------------------- HELPERS -------------------------
apt_install() {
    local pkg available=() missing=()
    for pkg in "$@"; do
        if apt-cache show "$pkg" >/dev/null 2>&1; then
            available+=("$pkg")
        else
            missing+=("$pkg")
        fi
    done
    (( ${#missing[@]} )) && warn "Not found in apt, skipped: ${missing[*]}"
    (( ${#available[@]} )) && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${available[@]}"
    return 0
}

fetch_git() {
    local url="$1" dir="$2" rev="$3"
    if [[ ! -d "$dir/.git" ]]; then
        git clone --filter=blob:none "$url" "$dir"
    fi
    git -C "$dir" fetch --tags --force origin
    git -C "$dir" checkout --force --detach "$rev"
    git -C "$dir" reset --hard --quiet
    git -C "$dir" clean -fdxq
    git -C "$dir" submodule update --init --recursive
}

apply_patch() {
    git -C "$1" apply --whitespace=nowarn "$REPO_DIR/patches/$2"
    ok "Applied $2"
}

# ------------------------- CHECKS -------------------------
preflight() {
    step "Checking the system"
    (( EUID != 0 )) || die "Run as your normal user, not root. sudo is used when needed."
    command -v sudo >/dev/null || die "sudo is required"
    [[ -d "$REPO_DIR/.config" && -d "$REPO_DIR/patches" ]] || die "Run install.sh from the Snowflake-dots folder"
    [[ -f "$REPO_DIR/.config/matugen/themes/$THEME.json" ]] || die "Theme not found: $THEME"

    . /etc/os-release
    if [[ "${ID:-}" != debian || "${VERSION_ID:-}" != 13 ]]; then
        warn "Snowflake is made for Debian 13 (trixie). Detected: ${PRETTY_NAME:-unknown}"
        ask "Continue anyway?" || exit 1
    fi

    ok "Debian ${VERSION_ID:-?}, user $(id -un)"
}

ensure_deb_src() {
    (( SKIP_HYPRLAND )) && return 0
    if grep -rqsE '^(deb-src|Types:.*deb-src)' /etc/apt/sources.list /etc/apt/sources.list.d/; then
        return 0
    fi
    warn "Debian-Hyprland builds from source and needs deb-src enabled in APT."
    local f=/etc/apt/sources.list.d/debian.sources
    if [[ -f "$f" ]] && ask "Add deb-src to $f?"; then
        sudo cp -a "$f" "$f.snowflake-bak"
        sudo sed -i 's/^Types: deb$/Types: deb deb-src/' "$f"
        ok "deb-src enabled (backup: $f.snowflake-bak)"
    else
        die "Enable deb-src in your APT sources and run the installer again"
    fi
}

# ------------------------- PACKAGES -------------------------
disable_yazi_repo() {
    local f=/etc/apt/sources.list.d/yazi.list
    [[ -f "$f" ]] || return 0
    sudo mv -f "$f" "$f.disabled"
    info "Disabled the yazi APT repository added by Debian-Hyprland (unsigned, not needed by Snowflake)"
}

install_packages() {
    step "Installing packages"
    disable_yazi_repo
    sudo DEBIAN_FRONTEND=noninteractive apt-get update || warn "apt update reported errors (often a broken third-party repository), continuing with the package lists that loaded"
    apt_install "${RUNTIME_PKGS[@]}"
    (( DOTS_ONLY )) || apt_install "${BUILD_PKGS[@]}"
}

# ------------------------- HYPRLAND -------------------------
install_hyprland() {
    (( SKIP_HYPRLAND )) && { info "Skipping Hyprland (--skip-hyprland)"; return 0; }
    step "Hyprland 0.55.3 via Debian-Hyprland v3.2.3"
    local dir="$BUILD_DIR/Debian-Hyprland"
    fetch_git "$DH_REPO" "$dir" "$DH_REV"
    apply_patch "$dir" debian-hyprland-preset-defaults.patch
    cp "$REPO_DIR/installer/debian-hyprland-preset.sh" "$dir/snowflake-preset.sh"

    cat <<'EOF'

  Debian-Hyprland opens its own menu now:
    * only "bluetooth" should be checked, confirm with Tab + Enter;
    * when asked about KooL dotfiles, choose "Continue" (Snowflake has its own);
    * answer "n" when it offers to reboot at the end, the Snowflake install is not finished yet.

EOF
    read -r -p "Press Enter to start Debian-Hyprland... " _
    (cd "$dir" && LC_ALL=C.UTF-8 LANG=C.UTF-8 LANGUAGE= ./install.sh --mode source --preset snowflake-preset.sh) </dev/tty >/dev/tty 2>/dev/tty

    disable_yazi_repo
    sudo DEBIAN_FRONTEND=noninteractive apt-get update || warn "apt update reported errors"

    command -v Hyprland >/dev/null || die "Hyprland was not installed, see Debian-Hyprland logs in $dir/Install-Logs"
    ok "$(Hyprland --version | head -1)"

}

use_apt_hyprlock() {
    LC_ALL=C apt-cache policy hyprlock | grep -q 'Candidate: [0-9]' || { warn "hyprlock is not in apt, keeping the current one"; return 0; }
    apt_install hyprlock
    if [[ -x /usr/local/bin/hyprlock ]]; then
        sudo mv -f /usr/local/bin/hyprlock /usr/local/bin/hyprlock.disabled
        ok "hyprlock from apt, source build kept as /usr/local/bin/hyprlock.disabled"
    else
        ok "hyprlock from apt"
    fi
}

# ------------------------- SESSION -------------------------
ensure_uwsm_session() {
    step "Hyprland session through uwsm"
    command -v uwsm >/dev/null || apt_install uwsm
    command -v uwsm >/dev/null || die "uwsm is not installed"
    local f src=""
    for f in /usr/share/wayland-sessions/hyprland-uwsm.desktop /usr/local/share/wayland-sessions/hyprland-uwsm.desktop; do
        [[ -f "$f" ]] && { src="$f"; break; }
    done
    if [[ -z "$src" ]]; then
        sudo install -d /usr/share/wayland-sessions
        printf '%s\n' '[Desktop Entry]' 'Name=Hyprland (uwsm-managed)' 'Comment=Hyprland compositor managed by UWSM' \
            'Exec=uwsm start -e -D Hyprland hyprland.desktop' 'TryExec=uwsm' 'DesktopNames=Hyprland' 'Type=Application' \
            | sudo tee /usr/share/wayland-sessions/hyprland-uwsm.desktop >/dev/null
        ok "Created /usr/share/wayland-sessions/hyprland-uwsm.desktop"
    elif [[ "$src" == /usr/local/* && ! -e /usr/share/wayland-sessions/hyprland-uwsm.desktop ]]; then
        sudo install -d /usr/share/wayland-sessions
        sudo ln -s "$src" /usr/share/wayland-sessions/hyprland-uwsm.desktop
        ok "Linked $src into /usr/share/wayland-sessions so every login manager sees it"
    else
        ok "Session file: $src"
    fi
    [[ -e /usr/share/wayland-sessions/hyprland.desktop || -e /usr/local/share/wayland-sessions/hyprland.desktop ]] \
        || warn "hyprland.desktop not found, uwsm needs it to start Hyprland"
}

# ------------------------- QUICKSHELL -------------------------
install_quickshell() {
    step "Quickshell v0.3.0-10 (with CLI11 and cpptrace)"
    local dir

    dir="$BUILD_DIR/CLI11"
    fetch_git "$CLI11_REPO" "$dir" "$CLI11_REV"
    cmake -S "$dir" -B "$dir/build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCLI11_BUILD_TESTS=OFF -DCLI11_BUILD_EXAMPLES=OFF -DCLI11_BUILD_DOCS=OFF
    cmake --build "$dir/build"
    sudo cmake --install "$dir/build"

    dir="$BUILD_DIR/cpptrace"
    fetch_git "$CPPTRACE_REPO" "$dir" "$CPPTRACE_REV"
    cmake -S "$dir" -B "$dir/build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCPPTRACE_UNWIND_WITH_LIBUNWIND=ON
    cmake --build "$dir/build"
    sudo cmake --install "$dir/build"

    dir="$BUILD_DIR/quickshell"
    fetch_git "$QS_REPO" "$dir" "$QS_REV"
    cmake -S "$dir" -B "$dir/build" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_INSTALL_PREFIX=/usr/local -DDISTRIBUTOR="Snowflake-dots"
    cmake --build "$dir/build"
    sudo cmake --install "$dir/build"
    [[ -e /usr/local/bin/qs ]] || sudo ln -s quickshell /usr/local/bin/qs
    sudo ldconfig
    ok "$(qs --version | head -1)"
}

# ------------------------- WAYBAR -------------------------
install_waybar() {
    step "Waybar 0.15.0 with the Snowflake patches"
    local dir="$BUILD_DIR/Waybar"
    fetch_git "$WAYBAR_REPO" "$dir" "$WAYBAR_REV"
    apply_patch "$dir" waybar-hyprland-legacy-ipc.patch
    apply_patch "$dir" waybar-taskbar-squash-fix.patch
    grep -q 'FORCE: this Hyprland build lacks real hl.dsp Lua support' "$dir/src/modules/hyprland/backend.cpp" \
        || die "Waybar patch is not in place, refusing to build an unpatched Waybar"

    meson setup "$dir/build" "$dir" --prefix=/usr/local --buildtype=release \
        -Dexperimental=true -Dtests=disabled \
        -Dcava=enabled -Ddbusmenu-gtk=enabled -Djack=enabled -Dlibnl=enabled -Dmpd=enabled \
        -Dmpris=enabled -Dpulseaudio=enabled -Drfkill=enabled -Dupower_glib=enabled
    ninja -C "$dir/build"
    sudo ninja -C "$dir/build" install
    hash -r
    [[ "$(command -v waybar)" == /usr/local/bin/waybar ]] || warn "waybar in PATH is $(command -v waybar), not the patched /usr/local/bin/waybar"
    ok "Waybar installed to /usr/local/bin/waybar"
}

# ------------------------- WOFI -------------------------
install_wofi() {
    step "wofi"
    local dir="$BUILD_DIR/wofi"
    rm -rf "$dir"
    if hg clone -r "$WOFI_REV" "$WOFI_REPO" "$dir"; then
        meson setup "$dir/build" "$dir" --prefix=/usr/local --buildtype=release
        ninja -C "$dir/build"
        sudo ninja -C "$dir/build" install
        ok "wofi $WOFI_REV installed to /usr/local"
    else
        warn "Could not fetch wofi from sourcehut, installing wofi from apt instead"
        apt_install wofi
    fi
}

# ------------------------- TOOLS -------------------------
install_hyprshot() {
    step "hyprshot"
    local dir="$BUILD_DIR/hyprshot"
    fetch_git "$HYPRSHOT_REPO" "$dir" "$HYPRSHOT_REV"
    apply_patch "$dir" hyprshot-no-busy-wait.patch
    sudo install -Dm755 "$dir/hyprshot" /usr/local/bin/hyprshot
    ok "hyprshot installed to /usr/local/bin"
}

install_matugen() {
    step "matugen $MATUGEN_VERSION"
    if command -v matugen >/dev/null && matugen --version | grep -q "$MATUGEN_VERSION"; then
        ok "matugen $MATUGEN_VERSION already installed"
        return 0
    fi
    if [[ ! -x "$HOME/.cargo/bin/cargo" ]]; then
        apt_install rustup
        rustup default stable
    fi
    "$HOME/.cargo/bin/cargo" install matugen --version "$MATUGEN_VERSION" --locked
    sudo install -m755 "$HOME/.cargo/bin/matugen" /usr/local/bin/matugen
    ok "$(matugen --version)"
}

# ------------------------- LOOK -------------------------
install_fonts() {
    step "Nerd Fonts $NERD_FONTS_VERSION"
    local font dest tmp
    tmp="$(mktemp -d)"
    for font in JetBrainsMono NerdFontsSymbolsOnly; do
        dest="$HOME/.local/share/fonts/$font"
        if [[ -d "$dest" ]] && compgen -G "$dest/*.ttf" >/dev/null; then
            ok "$font already installed"
            continue
        fi
        curl -fL --retry 3 -o "$tmp/$font.zip" \
            "https://github.com/ryanoasis/nerd-fonts/releases/download/$NERD_FONTS_VERSION/$font.zip"
        mkdir -p "$dest"
        unzip -oq "$tmp/$font.zip" '*.ttf' -d "$dest"
        ok "$font"
    done
    rm -rf "$tmp"
    fc-cache -f >/dev/null
}

install_themes() {
    step "GTK, icons and cursor"
    local dir="$BUILD_DIR/flat-remix" v
    if [[ ! -d "$HOME/.icons/$CURSOR_THEME" ]]; then
        rm -rf "$dir"
        git clone --depth 1 --filter=blob:none --sparse "$FLAT_REMIX_ICONS_REPO" "$dir"
        git -C "$dir" sparse-checkout set "$CURSOR_THEME"
        mkdir -p "$HOME/.icons"
        cp -a "$dir/$CURSOR_THEME" "$HOME/.icons/"
    fi
    ok "$CURSOR_THEME"

    gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME" || true
    gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME" || true
    gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR_THEME" || true
    gsettings set org.gnome.desktop.interface cursor-size "$CURSOR_SIZE" || true

    for v in gtk-3.0 gtk-4.0; do
        mkdir -p "$HOME/.config/$v"
        if [[ ! -f "$HOME/.config/$v/settings.ini" ]]; then
            printf '[Settings]\ngtk-cursor-theme-name=%s\ngtk-cursor-theme-size=%s\n' "$CURSOR_THEME" "$CURSOR_SIZE" \
                > "$HOME/.config/$v/settings.ini"
        fi
    done
    ok "GTK $GTK_THEME, icons $ICON_THEME, cursor $CURSOR_THEME $CURSOR_SIZE"
}

# ------------------------- DOTFILES -------------------------
deploy_dots() {
    step "Copying Snowflake configs"
    local backup="$HOME/.snowflake-backup/$(date +%F-%H%M%S)" src rel dst backed=0
    while IFS= read -r -d '' src; do
        rel="${src#"$REPO_DIR"/}"
        dst="$HOME/$rel"
        if [[ "$rel" == .local/share/* && -e "$dst" && "$rel" != .local/share/snowflake/wallpapers/* ]] && (( ! ${FORCE_LOCAL:-0} )); then
            continue
        fi
        if [[ -e "$dst" ]] && ! cmp -s "$src" "$dst"; then
            mkdir -p "$backup/$(dirname "$rel")"
            cp -a "$dst" "$backup/$rel"
            backed=1
        fi
        install -Dm644 "$src" "$dst"
        install -Dm644 "$src" "$BASE_DIR/$rel"
    done < <(find "$REPO_DIR/.config" "$REPO_DIR/.local" -type f -print0)

    (( backed )) && info "Your previous versions of changed files are in $backup"
    post_deploy
}

post_deploy() {
    local d
    for d in "$HOME/.config/hypr/scripts" "$HOME/.config/waybar/scripts" "$HOME/.config/quickshell/snowflake"; do
        [[ -d "$d" ]] && find "$d" -type f -name '*.sh' -exec chmod +x {} +
    done

    mkdir -p "$HOME/.config/quickshell/clipboard-module"
    mkdir -p "$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/screenshots"

    mkdir -p "$HOME/.config/autostart"
    printf '[Desktop Entry]\nHidden=true\n' > "$HOME/.config/autostart/blueman.desktop"
    ok "Configs copied"
}

fix_temperature_sensor() {
    local cfg="$HOME/.config/waybar/config.jsonc" h name path=""
    [[ -d /sys/devices/platform/coretemp.0/hwmon ]] && return 0
    for h in /sys/class/hwmon/hwmon*; do
        name="$(cat "$h/name" 2>/dev/null)" || continue
        case "$name" in
            k10temp | zenpower)
                path="$(readlink -f "$h/device")/hwmon"
                break
                ;;
        esac
    done
    if [[ -n "$path" ]]; then
        sed -i "s#\"/sys/devices/platform/coretemp.0/hwmon\"#\"$path\"#" "$cfg"
        ok "Waybar temperature sensor: $name ($path)"
    else
        sed -i '/"hwmon-path-abs": "\/sys\/devices\/platform\/coretemp.0\/hwmon",/d' "$cfg"
        sed -i '/"input-filename": "temp1_input",/d' "$cfg"
        warn "No coretemp/k10temp sensor found, Waybar uses its default thermal zone"
    fi
}

apply_theme() {
    step "Theme: $THEME"
    matugen json "$HOME/.config/matugen/themes/$THEME.json" || warn "matugen reported errors (normal outside a Hyprland session)"
    mkdir -p "$HOME/.cache/hub-module"
    printf '%s\n' "$THEME" > "$HOME/.cache/hub-module/theme_name"
    ok "Colors generated"
}

enable_services() {
    step "Services"
    local unit
    for unit in bluetooth.service NetworkManager.service power-profiles-daemon.service upower.service; do
        sudo systemctl enable --now "$unit" 2>/dev/null || warn "Could not enable $unit"
    done
    for unit in pipewire.socket pipewire-pulse.socket wireplumber.service swaync.service; do
        systemctl --user enable "$unit" 2>/dev/null || warn "Could not enable user $unit"
    done
    if systemctl --user is-enabled waybar.service >/dev/null 2>&1; then
        systemctl --user disable --now waybar.service 2>/dev/null || true
        info "Disabled waybar.service from the Debian package, Hyprland starts the patched Waybar itself"
    fi
    ok "Services enabled"
}

# ------------------------- STATE -------------------------
patch_sum() {
    local f
    for f in "$@"; do cat "$REPO_DIR/patches/$f"; done | sha256sum | cut -c1-16
}

fingerprint() {
    local body
    case "$1" in
        hyprland)   body="$DH_REV $(patch_sum debian-hyprland-preset-defaults.patch) $(sha256sum < "$REPO_DIR/installer/debian-hyprland-preset.sh")" ;;
        quickshell) body="$CLI11_REV $CPPTRACE_REV $QS_REV $(declare -f install_quickshell)" ;;
        waybar)     body="$WAYBAR_REV $(patch_sum waybar-hyprland-legacy-ipc.patch waybar-taskbar-squash-fix.patch) $(declare -f install_waybar)" ;;
        wofi)       body="$WOFI_REV $(declare -f install_wofi)" ;;
        hyprshot)   body="$HYPRSHOT_REV $(patch_sum hyprshot-no-busy-wait.patch)" ;;
        matugen)    body="$MATUGEN_VERSION" ;;
        *)          die "Unknown component: $1" ;;
    esac
    printf '%s' "$body" | sha256sum | cut -c1-16
}

COMPONENTS=(hyprland quickshell waybar wofi hyprshot matugen)

installed_fingerprint() {
    [[ -f "$INSTALLED_ENV" ]] || return 0
    sed -n "s/^$1=//p" "$INSTALLED_ENV"
}

record_component() {
    local name="$1" fp
    fp="$(fingerprint "$name")"
    mkdir -p "$STATE_DIR"
    touch "$INSTALLED_ENV"
    sed -i "/^$name=/d" "$INSTALLED_ENV"
    printf '%s=%s\n' "$name" "$fp" >> "$INSTALLED_ENV"
}

# ------------------------- CHECK -------------------------
verify() {
    local cmd fail=0 fonts path
    fonts="$(fc-list : family)"
    printf '\n  %sResult%s\n' "$C_BOLD" "$C_RESET"
    for cmd in Hyprland hyprctl uwsm hypridle hyprlock qs waybar wofi matugen hyprshot swaybg cliphist kitty fastfetch nmcli; do
        if path="$(command -v "$cmd")"; then
            printf '  %s✓%s  %-12s %s%s%s\n' "$C_OK" "$C_RESET" "$cmd" "$C_DIM" "$path" "$C_RESET"
        else
            printf '  %s✗%s  %-12s %smissing%s\n' "$C_ERR" "$C_RESET" "$cmd" "$C_ERR" "$C_RESET"
            fail=1
        fi
    done
    if (( ! DOTS_ONLY )); then
        if grep -q 'FORCE: this Hyprland build' "$BUILD_DIR/Waybar/src/modules/hyprland/backend.cpp" 2>/dev/null; then
            printf '  %s✓%s  %-12s %sbuilt with the Snowflake patches%s\n' "$C_OK" "$C_RESET" "Waybar" "$C_DIM" "$C_RESET"
        else
            printf '  %s✗%s  %-12s %sSnowflake patch not confirmed%s\n' "$C_ERR" "$C_RESET" "Waybar" "$C_ERR" "$C_RESET"
            fail=1
        fi
    fi
    for path in "JetBrainsMono Nerd Font" "Symbols Nerd Font"; do
        if grep -q "$path" <<<"$fonts"; then
            printf '  %s✓%s  %s\n' "$C_OK" "$C_RESET" "$path"
        else
            printf '  %s✗%s  %s %smissing%s\n' "$C_ERR" "$C_RESET" "$path" "$C_ERR" "$C_RESET"
            fail=1
        fi
    done
    return "$fail"
}

# ------------------------- PHASES -------------------------
p_hyprland()   { install_hyprland; if (( ! SKIP_HYPRLAND )); then record_component hyprland; fi; }
p_quickshell() { install_quickshell; record_component quickshell; }
p_waybar()     { install_waybar; record_component waybar; }
p_wofi()       { install_wofi; record_component wofi; }
p_hyprshot()   { install_hyprshot; record_component hyprshot; }
p_matugen()    { install_matugen; record_component matugen; }

# ------------------------- MAIN -------------------------
main() {
while (( $# )); do
    case "$1" in
        --theme) THEME="${2:?--theme needs a name}"; shift ;;
        --skip-hyprland) SKIP_HYPRLAND=1 ;;
        --dots-only) DOTS_ONLY=1; SKIP_HYPRLAND=1 ;;
        --yes) UI_YES=1 ;;
        --verbose | --full-log) UI_VERBOSE=1 ;;
        -h | --help) usage; exit 0 ;;
        *) usage; die "Unknown option: $1" ;;
    esac
    shift
done

mkdir -p "$BUILD_DIR"
ui_start "$BUILD_DIR/install-$(date +%F-%H%M%S).log"

ui_banner "Snowflake installer" "Simply beautiful · Hyprland rice for Debian 13"
if (( DOTS_ONLY )); then
    ui_summary_row "Mode" "configs, fonts and theme only (--dots-only)"
elif (( SKIP_HYPRLAND )); then
    ui_summary_row "Will build" "Quickshell 0.3.0 · Waybar 0.15.0 (patched) · wofi · hyprshot"
    ui_summary_row "Hyprland" "skipped (--skip-hyprland)"
else
    ui_summary_row "Will build" "Hyprland 0.55.3 · Quickshell 0.3.0 · Waybar 0.15.0 (patched) · wofi · hyprshot"
fi
ui_summary_row "Theme" "$THEME"
if (( ! DOTS_ONLY )); then
    if (( SKIP_HYPRLAND )); then
        ui_summary_row "Time" "about 20–40 minutes, mostly compiling"
    else
        ui_summary_row "Time" "about 1–2 hours, mostly compiling"
    fi
fi
ui_summary_row "Log" "$LOG"
if ! ui_confirm; then
    info "Cancelled, nothing was changed."
    exit 0
fi
printf '\n'
ui_sudo_keepalive

phase_add shown "System check" preflight
phase_add shown "APT sources" ensure_deb_src
phase_add quiet "System packages" install_packages
if (( ! DOTS_ONLY )); then
    if (( ! SKIP_HYPRLAND )); then
        phase_add shown "Hyprland 0.55.3 (Debian-Hyprland)" p_hyprland
    fi
    phase_add quiet "Quickshell 0.3.0" p_quickshell
    phase_add quiet "Waybar 0.15.0 + Snowflake patches" p_waybar
    phase_add quiet "wofi" p_wofi
    phase_add quiet "hyprshot" p_hyprshot
    phase_add shown "Login session (uwsm)" ensure_uwsm_session
    phase_add quiet "hyprlock" use_apt_hyprlock
fi
phase_add quiet "matugen $MATUGEN_VERSION" p_matugen
phase_add quiet "Nerd Fonts" install_fonts
phase_add quiet "GTK, icons and cursor" install_themes
phase_add shown "Snowflake configs" deploy_dots
phase_add shown "Temperature sensor" fix_temperature_sensor
phase_add quiet "Theme $THEME" apply_theme
phase_add shown "Services" enable_services
phase_run_all

if verify; then
    printf '\n  %s%s❄  Snowflake is installed%s  %sin %s%s\n' "$C_BOLD" "$C_ICE" "$C_RESET" "$C_DIM" "$(ui_total_time)" "$C_RESET"
    printf '     Reboot, then on the login screen pick %sHyprland (uwsm-managed)%s.\n' "$C_BOLD" "$C_RESET"
else
    printf '\n  %s%s!  Snowflake is installed with warnings%s  %sin %s%s\n' "$C_BOLD" "$C_WARN" "$C_RESET" "$C_DIM" "$(ui_total_time)" "$C_RESET"
    printf '     See the list above.\n'
fi
printf '     %sLog: %s%s\n\n' "$C_DIM" "$LOG" "$C_RESET"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
