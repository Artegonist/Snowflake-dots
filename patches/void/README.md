Patches used only by the Void Linux installer (installer/void.sh).
Void ships GCC 14, Hyprland 0.55.x expects GCC 15 (C++26 #embed, append_range, ...).
The patches come from https://github.com/CODJointOps/hyprland-voidlinux (commit 1834398,
the Hyprland 0.55.3 templates) and are applied with `patch -p1 -F3`.
