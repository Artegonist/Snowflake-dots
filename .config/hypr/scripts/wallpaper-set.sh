#!/bin/bash

CACHE_DIR="$HOME/.cache/hypr"
CURRENT="$CACHE_DIR/wallpaper"

WALL="$1"

if [ -z "$WALL" ] || [ ! -f "$WALL" ]; then
    notify-send "Wallpaper" "Файл не найден: $WALL" 2>/dev/null
    exit 1
fi

mkdir -p "$CACHE_DIR"
echo "$WALL" > "$CURRENT"

pkill swaybg
setsid swaybg -i "$WALL" -m fill >/dev/null 2>&1 &
disown
