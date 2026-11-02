# SNOWFLAKE-DOTFILES

![Snowflake desktop](Rice%20demo/snowflake-103646.png)

<table>
  <tr>
    <td><img src="Rice%20demo/snowflake-104245.png" alt="Snowflake demo 1"></td>
    <td><img src="Rice%20demo/snowflake-104417.png" alt="Snowflake demo 2"></td>
  </tr>
  <tr>
    <td><img src="Rice%20demo/snowflake-104728.png" alt="Snowflake demo 3"></td>
    <td><img src="Rice%20demo/snowflake-104934.png" alt="Snowflake demo 4"></td>
  </tr>
  <tr>
    <td colspan="2"><img src="Rice%20demo/snowflake-105018.png" alt="Snowflake demo 5"></td>
  </tr>
</table>

> [!CAUTION]
> **DISCLAIMER:**
> **- THIS RICE IS MADE AND TESTED ONLY ON DEBIAN 13 (TRIXIE). I CANNOT GUARANTEE FLAWLESS WORK ON OTHER DISTROS.**
> **- THE WM CONFIG USES THE OLD HYPRLAND SYNTAX AND DOES NOT SUPPORT THE NEW LUA SYNTAX YET. SEE [WHAT'S NEXT](#whats-next) FOR UPCOMING CHANGES.**
> **- NOT ALL WALLPAPERS ARE MINE. ALL WALLPAPERS WERE EITHER FOUND ON FREE STOCK SITES OR GIVEN TO ME BY PEOPLE I KNOW. I DO NOT CLAIM ANY RIGHTS TO THEM AND THEY ARE NOT COVERED BY THIS REPOSITORY'S LICENSE. IF YOU ARE THE AUTHOR AND WANT YOUR WALLPAPER DELETED, PLEASE [OPEN AN ISSUE](https://github.com/Artegonist/Snowflake-dots/issues).**

> [!NOTE]
> This project was configured and tuned by me. AI was used for routine tasks and bug hunting. The configuration and testing were mostly done by me, including real-life daily use on Debian 13 (Trixie).

## About
Snowflake is my daily-driver Hyprland rice: simple enough to be practical, polished enough to look good. Everything here is something I actually use, not a showcase setup that falls apart in real life.
Multiple themes and wallpapers are included, so you can choose the vibe that fits you.

## Components
- **WM:** Hyprland 0.55.3
- **TOPBAR:** Waybar 0.15.0 (a custom-built version with an essential fix made by me, see the wiki of this project)
- **LAUNCHER:** Wofi
- **WIDGETS:** Quickshell 0.3.0

## Requirements
- **Debian 13 (Trixie)**
- **A user in the sudo group**
- **About 10 GB of free disk space and an internet connection**

# Installation

### 1. Prepare the system
Make sure your user can use `sudo`:
```bash
sudo -v
```
If it says `is not in the sudoers file`, add yourself (asks for the root password), then log out and back in:
```bash
su -c "usermod -aG sudo $USER"
```

Update the system, install git and reboot:
```bash
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y git
```

### 2. Download Snowflake
```bash
git clone https://github.com/Artegonist/Snowflake-dots.git
cd Snowflake-dots
```
> [!IMPORTANT]
> Use `git clone`, not the ZIP download, otherwise `update.sh` will not work later.

### 3. Run the installer
```bash
bash install.sh
```
> [!WARNING]
> Run it as your normal user, **not** with `sudo`. The script asks for your password when it needs it.

To start with a different theme than the default `bloodsnow`, pass its name from `.config/matugen/themes`:
```bash
bash install.sh --theme arctic
```

### 4. Answer the Debian-Hyprland prompts
Hyprland is built through [Debian-Hyprland](https://github.com/LinuxBeginnings/Debian-Hyprland), which opens its own dialogs:
- **Add deb-src?** → `y`
- **Continue with the installation?** → `y`
- Notices about the login manager, NVIDIA or the input group → `OK`
- **Options list** → only `bluetooth` is checked, keep it and press `Tab`, then `Enter`
- **KooL Hyprland Dot Files** → `Continue` (Snowflake brings its own configs)
- **Reboot now?** at the end → `n`, the Snowflake part is not finished yet

The whole installation takes 1–2 hours, mostly compiling. It ends with **Snowflake is installed**.

### 5. Log in
Reboot. On the login screen click your user, then the gear icon in the bottom right corner, and choose **Hyprland (uwsm-managed)**.

| Keys | Action |
| --- | --- |
| `Super + Q` | Terminal |
| `Super + W` | App launcher |
| `Super + C` | Close window |
| Click the clock | Hub: themes, wallpapers, settings |

> [!NOTE]
> **NVIDIA laptops:** if Hyprland is missing on the login screen, enable modesetting and reboot:
> ```bash
> echo 'options nvidia-drm modeset=1 fbdev=1' | sudo tee /etc/modprobe.d/nvidia-drm.conf
> sudo update-initramfs -u
> ```
> **Virtual machines:** enable 3D acceleration, otherwise Hyprland will not start.

# Updating
```bash
cd ~/Snowflake-dots
bash update.sh
```
- `bash update.sh` keeps your own changes (binds, settings) and merges the new version in. If both touched the same lines, your file stays and the new one is saved next to it as `*.snowflake-new`.
- `bash update.sh --reset` brings all configs back to the Snowflake defaults. Old files go to `~/.snowflake-backup`.
- `bash update.sh --check` only shows what would change.

# Troubleshooting
If the installer stops with an error, [open an issue](https://github.com/Artegonist/Snowflake-dots/issues) and attach the log from `~/.cache/snowflake-build/install-*.log` (the path is printed on the last line). If Hyprland already built and something failed later, continue with:
```bash
bash install.sh --skip-hyprland
```

# What's next
- Moving the Hyprland config to the new Lua syntax.
