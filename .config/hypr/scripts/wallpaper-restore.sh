#!/usr/bin/env bash

for cmd in swaybg flock pkill; do
    command -v "$cmd" >/dev/null 2>&1 || {
        printf 'Не найдена команда: %s\n' "$cmd" >&2
        exit 1
    }
done

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hypr"
CURRENT="$CACHE_DIR/wallpaper"
DEFAULT="${XDG_DATA_HOME:-$HOME/.local/share}/snowflake/wallpapers/wallpaper1.jpg"

mkdir -p "$CACHE_DIR" || exit 1

exec 9>"$CACHE_DIR/wallpaper.lock" || exit 1
flock -n 9 || exit 0

WALL="$DEFAULT"

if [[ -f "$CURRENT" && -r "$CURRENT" ]]; then
    saved_wall=""
    IFS= read -r saved_wall < "$CURRENT" || true

    if [[ -f "$saved_wall" && -r "$saved_wall" ]]; then
        WALL="$saved_wall"
    fi
fi

if [[ ! -f "$WALL" || ! -r "$WALL" ]]; then
    printf 'Не удалось прочитать обои: %s\n' "$WALL" >&2
    exit 1
fi

pkill -u "$(id -u)" -x swaybg 2>/dev/null || true

swaybg -i "$WALL" -m fill 9>&- &
