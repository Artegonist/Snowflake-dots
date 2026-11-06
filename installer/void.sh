#!/usr/bin/env bash
# Void Linux backend for the Snowflake installer.
#
# Sourced by install.sh (after all its own functions exist) when /etc/os-release says ID=void.
# It overrides the Debian/APT specific steps. The shared steps (Quickshell, Waybar, wofi,
# hyprshot, fonts, themes, dotfiles) are reused unchanged. Dotfiles are NOT touched.
#
# Why everything is built from source into /usr/local:
#   * Void does not package Hyprland (void-linux/void-packages#37544).
#   * the few Hyprland libraries Void does ship (e.g. hyprutils 0.11.0) are far too old
#     for Hyprland 0.55.3, which needs hyprutils >= 0.13.1.
# Every component is pinned to a commit, so the result does not depend on what is newest.
#
# Void has no systemd: services are runit, the seat comes from elogind, and the session is
# started by /usr/local/bin/snowflake-session instead of uwsm.

# ------------------------- PINS -------------------------
# Hyprland 0.55.3 era, matching CODJointOps/hyprland-voidlinux@1834398 (with hyprutils bumped to
# 0.13.1 because Hyprland's CMake demands >= 0.13.1).
VOID_REV_SCANNER="b8632713a6beaf28b56f2a7b0ab2fb7088dbb404"    # hyprwayland-scanner v0.4.6
VOID_REV_PROTOCOLS="bd153e76f751f150a09328dbdeb5e4fab9d23622"  # hyprland-protocols v0.7.0
VOID_REV_UTILS="a2dbd8a4cc51f7cbe4224732668392bb1aa79df2"      # hyprutils v0.13.1
VOID_REV_LANG="3a1c1b25b059dae2c6bbc46991562ba1158d125c"       # hyprlang v0.6.8
VOID_REV_CURSOR="44e91d467bdad8dcf8bbd2ac7cf49972540980a5"     # hyprcursor v0.1.13
VOID_REV_GRAPHICS="482d4b7ec36ffdaf3573086aa586b178fd5404be"   # hyprgraphics v0.5.1
VOID_REV_WIRE="3e6865ce5fd9237b58f5b2ce5de18814df3baff5"       # hyprwire v0.3.1
VOID_REV_AQUAMARINE="01eeae12aa171fc13869b530b0dbb918521fa401" # aquamarine v0.12.0
VOID_REV_GLAZE="ae87b187e2264ad452777bca68e35595406e9dca"      # glaze v7.7.1
VOID_REV_HYPRLAND="fe5fe79a29ac3adaf3e75560b2f4b7a6d58b31c9"   # Hyprland v0.55.3
VOID_REV_HYPRLOCK="d75e93f8ee1721d70549d96f4d14bf2948aab70c"   # hyprlock v0.9.5
VOID_REV_HYPRIDLE="5430b73ddf148651bcf35fa39ed4d757c7534028"   # hypridle v0.1.7
VOID_REV_XDPH="01e13c0a027a2d177df4dead76ac9d069e2cc8e6"       # xdg-desktop-portal-hyprland v1.3.12

VOID_HYPR_DIR="$BUILD_DIR/hypr"
VOID_STAMP_DIR="$VOID_HYPR_DIR/.stamps"
VOID_PATCH_DIR="$REPO_DIR/patches/void"

# ------------------------- PACKAGES -------------------------
VOID_RUNTIME_PKGS=(
    git curl wget unzip jq socat python3 file
    kitty nautilus firefox fastfetch
    swaybg cliphist wl-clipboard wtype grim slurp
    cava playerctl brightnessctl easyeffects
    NetworkManager upower power-profiles-daemon bluez
    libnotify SwayNotificationCenter mate-polkit xdg-user-dirs
    xdg-desktop-portal xdg-desktop-portal-gtk xdg-utils
    pipewire wireplumber libspa-bluetooth alsa-pipewire pulseaudio-utils
    qt6-base qt6-declarative qt6-wayland qt6-svg
    dconf gsettings-desktop-schemas glib fontconfig adwaita-icon-theme gnome-themes-extra
    dbus elogind polkit xorg-server-xwayland mesa-dri util-linux kbd
)

VOID_BUILD_PKGS=(
    base-devel cmake meson ninja pkg-config patch xxd cpio mercurial scdoc gobject-introspection
    # Hyprland stack
    wayland-devel wayland-protocols libdrm-devel MesaLib-devel libgbm-devel libglvnd-devel
    glslang glslang-devel SPIRV-Tools-devel libinput-devel libseat-devel libxkbcommon-devel
    libuuid-devel glib-devel libglib-devel libXcursor-devel cairo-devel pango-devel pixman-devel
    re2-devel muparser-devel lcms2-devel libdisplay-info-devel hwids tomlplusplus-devel lua55-devel
    libzip-devel librsvg-devel libjpeg-turbo-devel libwebp-devel libpng-devel file-devel
    pugixml-devel libffi-devel libxcb-devel xcb-util-errors-devel xcb-util-wm-devel
    xcb-util-renderutil-devel xcb-util-devel pam-devel elogind-devel sdbus-c++-devel
    pipewire-devel eudev-libudev-devel
    # Quickshell
    qt6-base-devel qt6-base-private-devel qt6-declarative-devel qt6-declarative-private-devel
    qt6-wayland-devel qt6-wayland-tools qt6-shadertools qt6-shadertools-devel qt6-svg-devel
    SPIRV-Tools Vulkan-Headers vulkan-loader-devel polkit-devel jemalloc-devel
    libunwind-devel libdwarf-devel libzstd-devel
    # Waybar
    libevdev-devel gtkmm-devel spdlog gtk-layer-shell-devel jsoncpp-devel libsigc++-devel
    fmt-devel chrono-date-devel playerctl-devel upower-devel wireplumber-devel libnl3-devel
    pulseaudio-devel libdbusmenu-gtk3-devel libmpdclient-devel sndio-devel jack-devel
    gtk+3-devel libepoxy-devel fftw-devel iniparser-devel ncurses-devel
)

# ------------------------- OVERRIDDEN KNOBS -------------------------
DISTRO_LABEL="Void Linux"
BANNER_SUBTITLE="Simply beautiful · Hyprland rice for Void Linux"
PHASE_SOURCES_LABEL="Void repositories + system update"
PHASE_HYPRLAND_LABEL="Hyprland 0.55.3 (built from source)"
PHASE_SESSION_LABEL="Login session (snowflake-session)"
VERIFY_CMDS=(Hyprland hyprctl start-hyprland hypridle hyprlock qs waybar wofi matugen hyprshot
    swaybg cliphist kitty fastfetch nmcli loginctl snowflake-session)

# ------------------------- BUILD ENVIRONMENT -------------------------
# Hyprland needs a lot of RAM per compiler job (C++26, heavy templates): about 2.5 GiB each.
void_calc_jobs() {
    local cpus mem_kb jobs
    cpus="$(nproc 2>/dev/null || echo 2)"
    mem_kb="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || true)"
    [[ "$mem_kb" =~ ^[0-9]+$ ]] || mem_kb=4194304
    jobs=$(( mem_kb / 2621440 ))
    (( jobs < 1 )) && jobs=1
    (( jobs > cpus )) && jobs=$cpus
    printf '%s' "$jobs"
}
VOID_JOBS="${SNOWFLAKE_JOBS:-$(void_calc_jobs)}"
export CMAKE_BUILD_PARALLEL_LEVEL="$VOID_JOBS"
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export CMAKE_PREFIX_PATH="/usr/local${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"

# install.sh calls plain `ninja -C ... ` for Waybar/wofi: keep it from using every core at once.
ninja() { command ninja -j "$VOID_JOBS" "$@"; }

# The shared build functions in install.sh are kept byte-identical to the Debian ones (update.sh
# fingerprints their text), so Void-only flags are injected here instead of editing them.
cmake() {
    case " $* " in
        *" -DCPPTRACE_UNWIND_WITH_LIBUNWIND=ON "*)   # cpptrace: use Void's libzstd/libdwarf, no downloads
            command cmake "$@" -DCPPTRACE_USE_EXTERNAL_ZSTD=ON -DCPPTRACE_USE_EXTERNAL_LIBDWARF=ON \
                -DCPPTRACE_FIND_LIBDWARF_WITH_PKGCONFIG=ON ;;
        *) command cmake "$@" ;;
    esac
}
meson() {
    case " $* " in
        *" -Dcava=enabled "*)   # Waybar: elogind ships libsystemd.pc, make sure systemd support stays off
            command meson "$@" -Dsystemd=disabled -Dlibudev=enabled ;;
        *) command meson "$@" ;;
    esac
}

# gsettings needs a D-Bus session bus; outside a desktop session there is none on Void.
gsettings() {
    if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
        command gsettings "$@"
    else
        dbus-run-session -- gsettings "$@"
    fi
}

# ------------------------- PACKAGE HELPERS -------------------------
void_has_pkg() {
    xbps-query -R "$1" >/dev/null 2>&1 || xbps-query "$1" >/dev/null 2>&1
}

# Install what exists, warn about the rest (same behaviour as apt_install on Debian).
void_install() {
    local pkg available=() missing=()
    for pkg in "$@"; do
        if void_has_pkg "$pkg"; then available+=("$pkg"); else missing+=("$pkg"); fi
    done
    (( ${#missing[@]} )) && warn "Not found in xbps, skipped: ${missing[*]}"
    (( ${#available[@]} )) && sudo xbps-install -y "${available[@]}"
    return 0
}

# Install everything or stop: used for build dependencies, a skipped one means a failed build later.
void_install_required() {
    local pkg missing=()
    for pkg in "$@"; do
        void_has_pkg "$pkg" || missing+=("$pkg")
    done
    if (( ${#missing[@]} )); then
        die "These packages are not in the Void repositories (renamed or removed?): ${missing[*]}. Please report it with the log."
    fi
    sudo xbps-install -y "$@"
}

apt_install() { void_install "$@"; }

# ------------------------- CHECKS -------------------------
preflight() {
    step "Checking the system"
    (( EUID != 0 )) || die "Run as your normal user, not root. sudo is used when needed."
    command -v sudo >/dev/null || die "sudo is required. As root: xbps-install -S sudo, then add your user to the wheel group with visudo."
    command -v xbps-install >/dev/null || die "xbps-install not found, is this Void Linux?"
    [[ -d "$REPO_DIR/.config" && -d "$REPO_DIR/patches" ]] || die "Run install.sh from the Snowflake-dots folder"
    [[ -d "$VOID_PATCH_DIR" ]] || die "patches/void is missing, update the Snowflake-dots folder (git pull)"
    [[ -f "$REPO_DIR/.config/matugen/themes/$THEME.json" ]] || die "Theme not found: $THEME"

    if ldd --version 2>&1 | grep -qi musl; then
        die "This Void is musl-based. Only glibc is supported by the Snowflake installer for now."
    fi
    case "$(uname -m)" in
        x86_64) ;;
        aarch64) warn "aarch64 is untested" ;;
        *) die "Unsupported architecture: $(uname -m)" ;;
    esac

    curl -fsSI --max-time 15 https://github.com >/dev/null 2>&1 || die "Cannot reach github.com, check the internet connection"

    local free_gb
    free_gb="$(df -Pk "$BUILD_DIR" | awk 'NR==2 {printf "%d", $4/1048576}')"
    (( free_gb >= 10 )) || warn "Only ${free_gb} GB free in $BUILD_DIR, about 10 GB are needed"

    local total_gb
    total_gb="$(awk '/^MemTotal:/ {printf "%d", $2/1048576}' /proc/meminfo)"
    (( total_gb >= 4 )) || warn "Only ${total_gb} GB of RAM: the Hyprland build may be killed, add swap or set SNOWFLAKE_JOBS=1"

    ok "$DISTRO_LABEL ($(uname -m), glibc), user $(id -un), $VOID_JOBS build job(s)"
}

# Full sync + system update, done once by install.sh (not by update.sh).
ensure_deb_src() {
    (( DOTS_ONLY )) && return 0
    step "Updating Void"
    sudo xbps-install -Sy || die "Could not sync the Void repositories"
    sudo xbps-install -yu xbps || true
    sudo xbps-install -yu || die "System update failed, fix it (xbps-install -Syu) and run the installer again"
    ok "System is up to date"
}

# ------------------------- PACKAGES -------------------------
void_prepare_prefix() {
    local f=/etc/ld.so.conf.d/snowflake-local.conf
    if [[ ! -e "$f" ]]; then
        sudo install -d /etc/ld.so.conf.d
        printf '%s\n' /usr/local/lib /usr/local/lib64 | sudo tee "$f" >/dev/null
    fi
    if ! grep -qs 'ld.so.conf.d' /etc/ld.so.conf; then
        printf 'include /etc/ld.so.conf.d/*.conf\n' | sudo tee -a /etc/ld.so.conf >/dev/null
    fi
    sudo ldconfig
}

install_packages() {
    step "Installing packages"
    void_install "${VOID_RUNTIME_PKGS[@]}"
    (( DOTS_ONLY )) || void_install_required "${VOID_BUILD_PKGS[@]}"
    void_prepare_prefix
}

# ------------------------- BUILD HELPERS -------------------------
void_patch_sum() {
    local p
    for p in "$@"; do cat "$VOID_PATCH_DIR/$p"; done | sha256sum | cut -c1-12
}

void_patch() {
    local dir="$1" file="$VOID_PATCH_DIR/$2"
    patch -p1 -F3 --no-backup-if-mismatch -s -d "$dir" < "$file" || { warn "Patch $2 does not apply"; return 1; }
    ok "Applied $2"
}

# Hyprland 0.55 embeds its example Lua config with C++26 #embed, which GCC 14 (Void) lacks.
# patches/void/hyprland-04 includes this generated header instead.
void_pre_hyprland() {
    (cd "$1" && xxd -i -n EXAMPLE_CONFIG_BYTES_LUA example/hyprland.lua > src/config/lua/example_config_lua_data.h)
}

# void_component NAME KIND URL REV "PATCH PATCH..." [configure args...]
#   KIND: cmake | meson. Built into /usr/local, skipped when the same rev+patches were already installed.
void_component() {
    local name="$1" kind="$2" url="$3" rev="$4" patches="$5"
    shift 5
    local dir="$VOID_HYPR_DIR/$name" stamp p
    # shellcheck disable=SC2086
    stamp="$VOID_STAMP_DIR/$name-${rev:0:12}-$(void_patch_sum $patches)"
    if [[ -e "$stamp" ]]; then
        ok "$name already built (${rev:0:8})"
        return 0
    fi
    info "$name ${rev:0:8}"
    mkdir -p "$VOID_STAMP_DIR"
    fetch_git "$url" "$dir" "$rev" || return 1
    [[ "$(git -C "$dir" rev-parse HEAD)" == "$rev" ]] || { warn "$name is not at $rev"; return 1; }
    for p in $patches; do void_patch "$dir" "$p" || return 1; done
    if declare -F "void_pre_$name" >/dev/null; then "void_pre_$name" "$dir" || return 1; fi

    case "$kind" in
        cmake)
            cmake -S "$dir" -B "$dir/build" -G Ninja --no-warn-unused-cli \
                -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_INSTALL_LIBDIR=lib \
                -DCMAKE_INSTALL_RPATH=/usr/local/lib -DCMAKE_PREFIX_PATH=/usr/local "$@" || return 1
            cmake --build "$dir/build" || return 1
            # shellcheck disable=SC2033  # real cmake on purpose, the function wrapper above is for configure only
            sudo cmake --install "$dir/build" || return 1
            ;;
        meson)
            meson setup "$dir/build" "$dir" --prefix=/usr/local --libdir=lib --buildtype=release "$@" || return 1
            command ninja -C "$dir/build" -j "$VOID_JOBS" || return 1
            # shellcheck disable=SC2033
            sudo meson install -C "$dir/build" || return 1
            ;;
        *) die "void_component: unknown kind $kind" ;;
    esac
    sudo ldconfig
    : > "$stamp"
    ok "$name installed"
}

# ------------------------- HYPRLAND -------------------------
void_fix_hyprlock_pam() {
    [[ -f /etc/pam.d/hyprlock ]] && return 0
    warn "hyprlock did not install its PAM file, creating /etc/pam.d/hyprlock (without it you could not unlock the screen)"
    printf '%s\n' '# PAM configuration file for hyprlock' 'auth        include     login' \
        | sudo tee /etc/pam.d/hyprlock >/dev/null
}

void_portal_config() {
    local f=/usr/local/share/xdg-desktop-portal/hyprland-portals.conf
    [[ -f "$f" || -f /usr/share/xdg-desktop-portal/hyprland-portals.conf ]] && return 0
    sudo install -d "$(dirname "$f")"
    printf '%s\n' '[preferred]' 'default=hyprland;gtk' 'org.freedesktop.impl.portal.FileChooser=gtk' \
        | sudo tee "$f" >/dev/null
}

install_hyprland() {
    (( SKIP_HYPRLAND )) && { info "Skipping Hyprland (--skip-hyprland)"; return 0; }
    step "Hyprland 0.55.3 and its libraries, built from source into /usr/local"
    mkdir -p "$VOID_HYPR_DIR" "$VOID_STAMP_DIR"
    void_prepare_prefix
    local gh=https://github.com/hyprwm glaze_args=() d

    void_component hyprwayland-scanner cmake "$gh/hyprwayland-scanner.git" "$VOID_REV_SCANNER" "" || return 1
    void_component hyprland-protocols meson "$gh/hyprland-protocols.git" "$VOID_REV_PROTOCOLS" "" || return 1
    void_component hyprutils cmake "$gh/hyprutils.git" "$VOID_REV_UTILS" "" || return 1
    void_component hyprlang cmake "$gh/hyprlang.git" "$VOID_REV_LANG" "" || return 1
    void_component hyprcursor cmake "$gh/hyprcursor.git" "$VOID_REV_CURSOR" "" || return 1
    void_component hyprgraphics cmake "$gh/hyprgraphics.git" "$VOID_REV_GRAPHICS" "" || return 1
    void_component hyprwire cmake "$gh/hyprwire.git" "$VOID_REV_WIRE" \
        "hyprwire-01-fix-append-range.patch" -DBUILD_TESTING=OFF || return 1
    void_component aquamarine cmake "$gh/aquamarine.git" "$VOID_REV_AQUAMARINE" "" || return 1
    void_component glaze cmake "https://github.com/stephenberry/glaze.git" "$VOID_REV_GLAZE" "" \
        -DBUILD_TESTING=OFF -Dglaze_ENABLE_FUZZING=OFF || return 1

    for d in /usr/local/share/glaze /usr/local/lib/cmake/glaze /usr/local/lib64/cmake/glaze; do
        if [[ -d "$d" ]]; then glaze_args=(-Dglaze_DIR="$d"); break; fi
    done
    void_component hyprland cmake "$gh/Hyprland.git" "$VOID_REV_HYPRLAND" \
        "hyprland-01-fix-string-view-conversion.patch hyprland-02-fix-monitor-mode-sorting.patch hyprland-03-fix-xcb-connection-cast.patch hyprland-04-replace-embed-with-include.patch" \
        -DNO_SYSTEMD=ON -DNO_UWSM=ON -DBUILD_TESTING=OFF "${glaze_args[@]}" || return 1

    void_component hyprlock cmake "$gh/hyprlock.git" "$VOID_REV_HYPRLOCK" "" \
        -DCMAKE_INSTALL_SYSCONFDIR=/etc || return 1
    void_fix_hyprlock_pam
    void_component hypridle cmake "$gh/hypridle.git" "$VOID_REV_HYPRIDLE" "" || return 1

    # Screen sharing portal. Nice to have, a failure here must not stop the install.
    if void_component xdg-desktop-portal-hyprland cmake "$gh/xdg-desktop-portal-hyprland.git" "$VOID_REV_XDPH" \
        "xdph-fix-gbm-linear-modifier.patch" -DCMAKE_INSTALL_LIBEXECDIR=libexec; then
        void_portal_config
    else
        warn "xdg-desktop-portal-hyprland failed to build, screen sharing will not work (everything else is fine)"
    fi

    hash -r
    command -v Hyprland >/dev/null || die "Hyprland was not installed, see the log"
    local v
    v="$(Hyprland --version 2>&1 | head -1)" || true
    ok "${v:-Hyprland installed}"
    grep -q '0\.55\.3' <<<"$v" || warn "Hyprland reports an unexpected version: ${v:-?}"
}

use_apt_hyprlock() {
    ok "hyprlock is built together with Hyprland"
}

hyprland_fingerprint_body() {
    printf '%s' "void $VOID_REV_SCANNER $VOID_REV_PROTOCOLS $VOID_REV_UTILS $VOID_REV_LANG $VOID_REV_CURSOR $VOID_REV_GRAPHICS $VOID_REV_WIRE $VOID_REV_AQUAMARINE $VOID_REV_GLAZE $VOID_REV_HYPRLAND $VOID_REV_HYPRLOCK $VOID_REV_HYPRIDLE $VOID_REV_XDPH $(cat "$VOID_PATCH_DIR"/*.patch | sha256sum)"
}

# ------------------------- SESSION -------------------------
void_write_root() { # mode path  (content on stdin)
    sudo install -d "$(dirname "$2")"
    sudo tee "$2" >/dev/null
    sudo chmod "$1" "$2"
}

ensure_uwsm_session() {
    step "Hyprland session without systemd"

    # Wrapper: D-Bus session, audio, notification daemon, then Hyprland.
    void_write_root 755 /usr/local/bin/snowflake-session <<'EOF'
#!/bin/sh
# Starts Hyprland for Snowflake on Void Linux (runit + elogind, no systemd, no uwsm).
# Installed by the Snowflake installer. Run it from a text console (tty).
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland
export XDG_SESSION_DESKTOP=Hyprland

# Hyprland cannot start inside another graphical session (XFCE, GNOME, ...): it needs the screen for itself.
if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
    cat >&2 <<'MSG'
snowflake-session must be started from a text console, not from a terminal inside another desktop.
  1. Switch to a console:  Ctrl+Alt+F3  (on laptops often Ctrl+Alt+Fn+F3)  or run:  sudo chvt 3
  2. Log in there with your user name and password.
  3. Run:  snowflake-session
(Back to your old desktop later:  sudo chvt 7  or  Ctrl+Alt+F7)
MSG
    exit 1
fi

# `qs` wrapper (fits the shell to small screens); `systemctl` stand-in for the Power menu when systemd is absent.
PATH="/usr/local/libexec/snowflake/bin:$PATH"
command -v systemctl >/dev/null 2>&1 || PATH="$PATH:/usr/local/libexec/snowflake/compat"
export PATH

if [ -z "$XDG_RUNTIME_DIR" ]; then
    echo "snowflake-session: XDG_RUNTIME_DIR is not set." >&2
    echo "Log in on a text console so elogind can create your session (the elogind and dbus services must run)." >&2
    exit 1
fi

if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    exec dbus-run-session -- "$0" "$@"
fi

uid="$(id -u)"
# Audio: pipewire + wireplumber + the PulseAudio compatibility server.
pgrep -u "$uid" -x pipewire >/dev/null 2>&1 || { pipewire & sleep 1; }
pgrep -u "$uid" -x wireplumber >/dev/null 2>&1 || wireplumber &
pgrep -u "$uid" -x pipewire-pulse >/dev/null 2>&1 || pipewire-pulse &

# Notification center: needs the Wayland socket, so wait for Hyprland to create it.
(
    n=0
    while [ "$n" -lt 100 ]; do
        for s in "$XDG_RUNTIME_DIR"/wayland-[0-9]*; do
            case "$s" in *.lock) continue ;; esac
            if [ -S "$s" ]; then
                WAYLAND_DISPLAY="$(basename "$s")"
                export WAYLAND_DISPLAY
                exec swaync
            fi
        done
        n=$((n + 1))
        sleep 0.3
    done
) &

if command -v start-hyprland >/dev/null 2>&1; then
    start-hyprland
else
    Hyprland
fi
rc=$?
# shellcheck disable=SC2046
kill $(jobs -p) 2>/dev/null
exit $rc
EOF

    # systemctl stand-in, only visible inside snowflake-session and only when systemd is absent.
    sudo rm -f /usr/local/libexec/snowflake/bin/systemctl
    void_write_root 755 /usr/local/libexec/snowflake/compat/systemctl <<'EOF'
#!/bin/sh
# Minimal systemctl replacement for elogind systems (Void Linux), installed by Snowflake.
for a in "$@"; do
    if [ "$a" = "--user" ]; then
        echo "systemctl: there is no systemd user session on this system" >&2
        exit 1
    fi
done
case "${1:-}" in
    poweroff | halt) exec loginctl poweroff ;;
    reboot) exec loginctl reboot ;;
    suspend) exec loginctl suspend ;;
    hibernate) exec loginctl hibernate ;;
    *) echo "systemctl: '$*' is not supported, this system has no systemd" >&2; exit 1 ;;
esac
EOF

    # qs wrapper: the Hub window is a fixed 1500x800, so on screens smaller than ~1600x900 (e.g. 1366x768
    # laptops) scale the shell down. Dotfiles stay untouched. Override: SNOWFLAKE_SCALE=1 (off) or 0.9 etc.
    void_write_root 755 /usr/local/libexec/snowflake/bin/qs <<'EOF'
#!/bin/sh
# Installed by the Snowflake installer (Void Linux).
real=/usr/local/bin/qs
case " $* " in *" ipc "*) exec "$real" "$@" ;; esac
if [ -z "${QT_SCALE_FACTOR:-}" ]; then
    if [ -n "${SNOWFLAKE_SCALE:-}" ]; then
        f="$SNOWFLAKE_SCALE"
    else
        f="$(hyprctl monitors -j 2>/dev/null | jq -r '[.[] | ([(.width / .scale) / 1600, (.height / .scale) / 900, 1] | min)] | min // 1' 2>/dev/null)"
    fi
    case "$f" in '' | null) f=1 ;; esac
    f="$(awk -v f="$f" 'BEGIN { if (f < 0.7) f = 0.7; if (f > 1) f = 1; printf "%.2f", f }')"
    [ "$f" = "1.00" ] || export QT_SCALE_FACTOR="$f"
fi
exec "$real" "$@"
EOF

    # Entry for graphical login managers, if the user ever installs one.
    void_write_root 644 /usr/share/wayland-sessions/snowflake-hyprland.desktop <<'EOF'
[Desktop Entry]
Name=Hyprland (Snowflake)
Comment=Hyprland started through snowflake-session
Exec=/usr/local/bin/snowflake-session
TryExec=/usr/local/bin/snowflake-session
DesktopNames=Hyprland
Type=Application
EOF
    ok "snowflake-session installed to /usr/local/bin"

    # hyprland.conf starts the polkit agent from the Debian/Fedora path.
    local agent=/usr/libexec/polkit-mate-authentication-agent-1 found
    if [[ ! -x "$agent" ]]; then
        found="$(find /usr/libexec /usr/lib -maxdepth 3 -name polkit-mate-authentication-agent-1 -print -quit 2>/dev/null)"
        if [[ -n "$found" ]]; then
            sudo install -d /usr/libexec
            sudo ln -sf "$found" "$agent"
            ok "Linked $found to $agent"
        else
            warn "mate-polkit agent not found, graphical password prompts (polkit) will not work"
        fi
    fi
}

# ------------------------- SERVICES (runit) -------------------------
void_enable_sv() {
    local sv="$1"
    if [[ ! -d "/etc/sv/$sv" ]]; then
        warn "No runit service /etc/sv/$sv, skipped"
    elif [[ -e "$VOID_SVDIR/$sv" ]]; then
        info "$sv is already enabled"
    elif sudo ln -s "/etc/sv/$sv" "$VOID_SVDIR/$sv"; then
        ok "Enabled $sv"
    else
        warn "Could not enable $sv"
    fi
    return 0
}

enable_services() {
    step "Services (runit)"
    VOID_SVDIR=/var/service
    [[ -d "$VOID_SVDIR" ]] || VOID_SVDIR=/etc/runit/runsvdir/default
    check_libraries
    if [[ ! -d "$VOID_SVDIR" ]]; then
        warn "runit service directory not found. Enable dbus, elogind, polkitd, bluetoothd, NetworkManager yourself."
        return 0
    fi

    local sv other busy=""
    for sv in dbus elogind polkitd bluetoothd power-profiles-daemon; do void_enable_sv "$sv"; done

    # NetworkManager fights with other network services: only enable it when nothing else is in charge.
    if [[ -e "$VOID_SVDIR/NetworkManager" ]]; then
        info "NetworkManager is already enabled"
    else
        for other in dhcpcd wpa_supplicant iwd connmand dhclient; do
            [[ -e "$VOID_SVDIR/$other" ]] && busy+="$other "
        done
        if [[ -n "$busy" ]]; then
            warn "Left your network setup alone ($busy is enabled). Snowflake's network widget needs NetworkManager:"
            warn "   sudo rm ${busy// / $VOID_SVDIR/} ; sudo ln -s /etc/sv/NetworkManager $VOID_SVDIR/   (do it from a local console)"
        else
            void_enable_sv NetworkManager
        fi
    fi

    # brightnessctl needs the video group, bluetoothctl the bluetooth group.
    local g me
    me="$(id -un)"
    for g in video bluetooth; do
        getent group "$g" >/dev/null || continue
        id -nG "$me" | tr ' ' '\n' | grep -qx "$g" && continue
        sudo usermod -aG "$g" "$me" && info "Added $me to the $g group (log out and in again to apply)"
    done
    ok "Services configured"
}

# ------------------------- TOOLS -------------------------
install_matugen() {
    step "matugen $MATUGEN_VERSION"
    if command -v matugen >/dev/null && matugen --version | grep -q "$MATUGEN_VERSION"; then
        ok "matugen $MATUGEN_VERSION already installed"
        return 0
    fi
    if command -v cargo >/dev/null \
        && cargo install matugen --version "$MATUGEN_VERSION" --locked \
        && sudo install -m755 "$HOME/.cargo/bin/matugen" /usr/local/bin/matugen; then
        :
    else
        warn "Building matugen $MATUGEN_VERSION failed, using Void's matugen package instead (the version may differ)"
        void_install matugen
        command -v matugen >/dev/null || die "matugen is not installed"
    fi
    hash -r
    ok "$(matugen --version)"
}

print_finish_hint() {
    printf '     To start Snowflake you need a text console (not a terminal inside XFCE/GNOME):\n'
    printf '       1. %ssudo chvt 3%s   (or Ctrl+Alt+F3, on laptops often Ctrl+Alt+Fn+F3)\n' "$C_BOLD" "$C_RESET"
    printf '       2. log in there with your user name and password\n'
    printf '       3. run %ssnowflake-session%s\n' "$C_BOLD" "$C_RESET"
    printf '     %sBack to the old desktop: sudo chvt 7. If you were added to groups (video/bluetooth), log out and in once first.%s\n' "$C_DIM" "$C_RESET"
}
