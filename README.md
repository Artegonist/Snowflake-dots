# SNOWFLAKE-DOTFILES

> [!CAUTION]
> **DISCLAIMER:**
> **- THIS RICE IS MADE AND TESTED ONLY ON DEBIAN 13 (TRIXIE). I CANNOT GUARANTEE FLAWLESS WORK ON OTHER DISTROS.**
> **- THE WM CONFIG USES THE OLD HYPRLAND SYNTAX AND DOES NOT SUPPORT THE NEW LUA SYNTAX YET. SEE [WHAT'S NEXT](#whats-next) FOR UPCOMING CHANGES.**
> **- NOT ALL WALLPAPERS ARE MINE. ALL WALLPAPERS WERE EITHER FOUND ON FREE STOCK SITES OR GIVEN TO ME BY PEOPLE I KNOW. I DO NOT CLAIM ANY RIGHTS TO THEM AND THEY ARE NOT COVERED BY THIS REPOSITORY'S LICENSE. IF YOU ARE THE AUTHOR AND WANT YOUR WALLPAPER DELETED, PLEASE OPEN AN ISSUE OR CONTACT ME AT [YOUR CONTACT].**

> [!NOTE]
> This project was configured and tuned by me. AI was used for routine tasks and bug hunting. The configuration and testing were mostly done by me, including real-life daily use on Debian 13 (Trixie).

## About
Snowflake is my daily-driver Hyprland rice: simple enough to be practical, polished enough to look good. Everything here is something I actually use, not a showcase setup that falls apart in real life.
Multiple themes and wallpapers are included, so you can choose the vibe that fits you. 

## Components
- **WM:** Hyprland 0.55.3
- **TOPBAR:** Waybar 0.15.0 (In my case i use custom builded version, with essential fix made by me. To learn more refer to wiki of this project)
- **LAUNCHER:** Wofi
- **WIDGETS:** Quickshell 0.3.0

## Requirements for instalation 
- **Debian 13**
- **User should be in sudo group**

# Instalation 
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
> echo 'options
