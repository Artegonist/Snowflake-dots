#!/bin/bash

LOCKFILE="/tmp/waybar-playerctl-listener.lock"

print_status() {
    ICON_PLAYING=" 󰏤 "
    ICON_PAUSED=" 󰐊 "
    ICON_STOPPED=" 󰐊 "

    status=$(playerctl status 2>/dev/null)
    title=$(playerctl metadata title 2>/dev/null)
    artist=$(playerctl metadata artist 2>/dev/null)

    case "$status" in
        "Playing") icon="$ICON_PLAYING"; class="playing" ;;
        "Paused")  icon="$ICON_PAUSED";  class="paused"  ;;
        *)         icon="$ICON_STOPPED"; class="stopped" ;;
    esac

    tooltip="${artist:-No player}${title:+ - $title}"
    tooltip=$(echo "$tooltip" | sed 's/"/\\"/g')

    printf '{"text": "%s", "class": "%s", "tooltip": "%s"}\n' "$icon" "$class" "$tooltip"
}

# Атомарно гарантируем, что слушатель запустится только один раз
(
    flock -n 200 || exit 0
    setsid bash -c '
        playerctl --follow status 2>/dev/null | while read -r _; do
            pkill -RTMIN+8 waybar
        done
    ' >/dev/null 2>&1 &
    disown
) 200>"$LOCKFILE"

print_status