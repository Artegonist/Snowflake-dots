#!/usr/bin/env bash
set -Eeuo pipefail

# ------------------------- CONFIG -------------------------
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SNOWFLAKE_BUILD_DIR:-$HOME/.cache/snowflake-build}"
THEME="arctic"
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
FLAT_REMIX_GTK_REPO="https://github.com/daniruiz/flat-remix-gtk.git"
GTK_THEME="Flat-Remix-GTK-Blue-Dark"
ICON_THEME="Flat-Remix-Blue-Dark"

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
info() { printf '\033[1;36m::\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m  %s\n' "$*" >&2; }
die()  { printf '\033[1;31m✗\033[0m  %s\n' "$*" >&2; exit 1; }
step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

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
    (( ${#available[@]} )) && sudo apt-get install -y "${available[@]}"
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

    sudo -v
    ok "Debian 13, user $(id -un)"
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
install_packages() {
    step "Installing packages"
    sudo apt-get update
    apt_install "${RUNTIME_PKGS[@]}"
    (( DOTS_ONLY )) || apt_install "${BUILD_PKGS[@]}"
}

# ------------------------- HYPRLAND -------------------------
install_hyprland() {
    (( SKIP_HYPRLAND )) && { info "Skipping Hyprland (--skip-hyprland)"; return 0; }
    step "Hyprland 0.55.3 via Debian-Hyprland v3.2.3"
    local dir="$BUILD_DIR/Debian-Hyprland"
    fetch_git "$DH_REPO" "$dir" "$DH_REV"
    cp "$REPO_DIR/installer/debian-hyprland-preset.sh" "$dir/snowflake-preset.sh"

    cat <<'EOF'

  Debian-Hyprland opens its own menu now:
    * keep the preselected options and confirm;
    * when asked about KooL dotfiles, choose "Continue" (Snowflake has its own);
    * answer "n" when it offers to reboot at the end, the Snowflake install is not finished yet.

EOF
    read -r -p "Press Enter to start Debian-Hyprland... " _
    (cd "$dir" && ./install.sh --mode source --preset snowflake-preset.sh) </dev/tty >/dev/tty 2>/dev/tty

    command -v Hyprland >/dev/null || die "Hyprland was not installed, see Debian-Hyprland logs in $dir/Install-Logs"
    ok "$(Hyprland --version | head -1)"

    if [[ -x /usr/local/bin/hyprlock ]] && apt-cache policy hyprlock | grep -q 'Candidate: [0-9]'; then
        sudo mv -f /usr/local/bin/hyprlock /usr/local/bin/hyprlock.disabled
        apt_install hyprlock
        ok "hyprlock from apt, source build kept as hyprlock.disabled"
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
    cmake -S "$dir" -B "$dir/build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local
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
    step "Waybar 0.15.0 with the Snowflake Hyprland IPC patch"
    local dir="$BUILD_DIR/Waybar"
    fetch_git "$WAYBAR_REPO" "$dir" "$WAYBAR_REV"
    apply_patch "$dir" waybar-hyprland-legacy-ipc.patch
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
    step "Flat Remix GTK and icon themes"
    local dir="$BUILD_DIR/flat-remix"
    if [[ ! -d "$HOME/.icons/$ICON_THEME" ]]; then
        rm -rf "$dir"
        git clone --depth 1 --filter=blob:none --sparse "$FLAT_REMIX_ICONS_REPO" "$dir"
        git -C "$dir" sparse-checkout set "$ICON_THEME"
        mkdir -p "$HOME/.icons"
        cp -a "$dir/$ICON_THEME" "$HOME/.icons/"
    fi
    ok "$ICON_THEME"

    dir="$BUILD_DIR/flat-remix-gtk"
    if [[ ! -d "$HOME/.themes/$GTK_THEME" ]]; then
        rm -rf "$dir"
        git clone --depth 1 --filter=blob:none --sparse "$FLAT_REMIX_GTK_REPO" "$dir"
        git -C "$dir" sparse-checkout set "themes/$GTK_THEME"
        mkdir -p "$HOME/.themes"
        cp -a "$dir/themes/$GTK_THEME" "$HOME/.themes/"
    fi
    ok "$GTK_THEME"

    gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME" || true
    gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME" || true
    gsettings set org.gnome.desktop.interface color-scheme prefer-dark || true
}

# ------------------------- DOTFILES -------------------------
deploy_dots() {
    step "Copying Snowflake configs"
    local backup="$HOME/.snowflake-backup/$(date +%F-%H%M%S)" src rel dst backed=0
    while IFS= read -r -d '' src; do
        rel="${src#"$REPO_DIR"/}"
        dst="$HOME/$rel"
        if [[ "$rel" == .local/share/* && -e "$dst" && "$rel" != .local/share/snowflake/wallpapers/* ]]; then
            continue
        fi
        if [[ -e "$dst" ]] && ! cmp -s "$src" "$dst"; then
            mkdir -p "$backup/$(dirname "$rel")"
            cp -a "$dst" "$backup/$rel"
            backed=1
        fi
        install -Dm644 "$src" "$dst"
    done < <(find "$REPO_DIR/.config" "$REPO_DIR/.local" -type f -print0)

    find "$HOME/.config/hypr/scripts" "$HOME/.config/waybar/scripts" "$HOME/.config/quickshell/snowflake" \
        -type f -name '*.sh' -exec chmod +x {} +
    (( backed )) && info "Your previous versions of changed files are in $backup"

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
    ok "Services enabled"
}

# ------------------------- CHECK -------------------------
verify() {
    step "Checking the result"
    local cmd fail=0
    for cmd in Hyprland hyprctl uwsm hypridle hyprlock qs waybar wofi matugen hyprshot swaybg cliphist kitty fastfetch nmcli; do
        if command -v "$cmd" >/dev/null; then
            ok "$cmd → $(command -v "$cmd")"
        else
            warn "$cmd is missing"
            fail=1
        fi
    done
    grep -q 'FORCE: this Hyprland build' "$BUILD_DIR/Waybar/src/modules/hyprland/backend.cpp" 2>/dev/null \
        && ok "Waybar was built with the Snowflake patch" \
        || { (( DOTS_ONLY )) || { warn "Waybar patch not confirmed"; fail=1; }; }
    fc-list | grep -q 'JetBrainsMono Nerd Font' && ok "JetBrainsMono Nerd Font" || { warn "JetBrainsMono Nerd Font missing"; fail=1; }
    fc-list | grep -q 'Symbols Nerd Font' && ok "Symbols Nerd Font" || { warn "Symbols Nerd Font missing"; fail=1; }
    return "$fail"
}

# ------------------------- MAIN -------------------------
while (( $# )); do
    case "$1" in
        --theme) THEME="${2:?--theme needs a name}"; shift ;;
        --skip-hyprland) SKIP_HYPRLAND=1 ;;
        --dots-only) DOTS_ONLY=1; SKIP_HYPRLAND=1 ;;
        -h | --help) usage; exit 0 ;;
        *) usage; die "Unknown option: $1" ;;
    esac
    shift
done

mkdir -p "$BUILD_DIR"
LOG="$BUILD_DIR/install-$(date +%F-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

preflight
ensure_deb_src
install_packages
if (( ! DOTS_ONLY )); then
    install_hyprland
    install_quickshell
    install_waybar
    install_wofi
    install_hyprshot
fi
(( DOTS_ONLY )) || ensure_uwsm_session
install_matugen
install_fonts
install_themes
deploy_dots
fix_temperature_sensor
apply_theme
enable_services

if verify; then
    printf '\n\033[1;32mSnowflake is installed.\033[0m Reboot and choose the Hyprland (uwsm) session at login.\n'
else
    printf '\n\033[1;33mSnowflake is installed with warnings, see above and %s\033[0m\n' "$LOG"
fi
printf 'Log: %s\n' "$LOG"
