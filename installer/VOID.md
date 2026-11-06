# Snowflake on Void Linux

`install.sh` detects Void (`ID=void` in /etc/os-release) and loads `installer/void.sh`.
Dotfiles in `.config/` and `.local/` are installed exactly as on Debian, nothing in them is changed.
Debian behaviour is unchanged.

```bash
git clone https://github.com/Artegonist/Snowflake-dots.git
cd Snowflake-dots
bash install.sh          # as your normal user, needs sudo
```

Requirements: glibc Void (musl is not supported), `sudo`, about 10 GB free, 4 GB RAM or more (or swap).
The installer limits compiler jobs by free RAM, override with `SNOWFLAKE_JOBS=2 bash install.sh`.

## Starting it
Hyprland needs the screen for itself, so start it from a **text console**, not from a terminal inside XFCE:
```bash
sudo chvt 3        # or Ctrl+Alt+F3 (on laptops often Ctrl+Alt+Fn+F3)
# log in on that console, then:
snowflake-session
```
Back to the old desktop: `sudo chvt 7`. If you run `snowflake-session` inside another desktop it explains this and exits.

Small screens: the Hub window is a fixed 1500x800, so on screens below ~1600x900 (e.g. 1366x768) a wrapper
for `qs` scales the shell down automatically (dotfiles are not changed). Change it with
`SNOWFLAKE_SCALE=0.9 snowflake-session`, turn it off with `SNOWFLAKE_SCALE=1 snowflake-session`.

Update only the launcher after pulling a new version: `bash install.sh --session-only`.

## What it does differently from Debian
* Updates Void (`xbps-install -Syu`), installs runtime and `-devel` packages with xbps.
* Void has no Hyprland package and its `hyprutils` is too old, so Hyprland 0.55.3 and its libraries
  (hyprutils, hyprlang, hyprcursor, hyprgraphics, hyprwire, aquamarine, glaze, hyprlock, hypridle,
  xdg-desktop-portal-hyprland) are built from pinned commits into `/usr/local`.
  Void ships GCC 14, so a few small patches from `patches/void/` are applied.
* Quickshell, Waybar (patched), wofi, hyprshot, matugen are built exactly as on Debian.
* No systemd: services are enabled with runit (`dbus elogind polkitd bluetoothd power-profiles-daemon`,
  and `NetworkManager` only if no other network service such as dhcpcd/iwd is enabled).
* No uwsm: start the desktop from a text console with `snowflake-session`
  (it starts D-Bus, pipewire, wireplumber, the notification center and Hyprland).
  The Power menu's `systemctl poweroff/reboot` is mapped to elogind inside that session only.

## Troubleshooting
* Log of every run: `~/.cache/snowflake-build/install-*.log` (path is printed at the end).
* Finished components are remembered in `~/.cache/snowflake-build/hypr/.stamps`, so a re-run continues
  where it stopped instead of rebuilding everything.
* Hyprland already installed? `bash install.sh --skip-hyprland`.
