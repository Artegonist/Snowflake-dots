#!/usr/bin/env bash

for cmd in swaybg flock pkill; do
    command -v "$cmd" >/dev/null 2>&1 || {
        printf 'Не найдена команда: %s\n' "$cmd" >&2
        exit 1
    }
done

DIR="${XDG_DATA_HOME:-$HOME/.local/share}/snowflake/wallpapers"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hypr"
CURRENT="$CACHE_DIR/wallpaper"
INDEX="$CACHE_DIR/wallpaper_index"

if [[ ! -d "$DIR" ]]; then
    printf 'Папка с обоями не найдена: %s\n' "$DIR" >&2
    exit 1
fi

mkdir -p "$CACHE_DIR" || exit 1

exec 9>"$CACHE_DIR/wallpaper.lock" || exit 1
flock -n 9 || exit 0

mapfile -t WALLS < <(
    find "$DIR" -maxdepth 1 -type f \
        \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) |
        sort
)

if (( ${#WALLS[@]} == 0 )); then
    printf 'В папке нет подходящих обоев: %s\n' "$DIR" >&2

    if command -v notify-send >/dev/null 2>&1; then
        notify-send "Wallpaper" "В $DIR нет картинок" 2>/dev/null || true
    fi

    exit 1
fi

IDX=-1

if [[ -f "$INDEX" && -r "$INDEX" ]]; then
    IDX=$(cat -- "$INDEX")
fi

[[ "$IDX" =~ ^(0|[1-9][0-9]{0,8})$ ]] || IDX=-1

IDX=$(( (IDX + 1) % ${#WALLS[@]} ))
WALL="${WALLS[$IDX]}"

if [[ ! -r "$WALL" ]]; then
    printf 'Не удалось прочитать обои: %s\n' "$WALL" >&2
    exit 1
fi

printf '%s\n' "$IDX" > "$INDEX" || exit 1
printf '%s\n' "$WALL" > "$CURRENT" || exit 1

pkill -u "$(id -u)" -x swaybg 2>/dev/null || true

swaybg -i "$WALL" -m fill 9>&- &
