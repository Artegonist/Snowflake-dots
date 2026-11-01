#!/usr/bin/env bash

current=$(hyprctl getoption dwindle:preserve_split | awk '/int:/ {print $2}')

if [ "$current" = "1" ]; then
    hyprctl keyword dwindle:preserve_split false
else
    hyprctl keyword dwindle:preserve_split true
fi

pkill -RTMIN+9 -u "$(id -u)" -x waybar 2>/dev/null || true
