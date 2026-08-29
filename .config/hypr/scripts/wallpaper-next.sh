#!/bin/bash

DIR="/home/artegonist/Картинки/wallpapers"
CACHE_DIR="$HOME/.cache/hypr"
CURRENT="$CACHE_DIR/wallpaper"  
INDEX="$CACHE_DIR/wallpaper_index"

mkdir -p "$CACHE_DIR"

mapfile -t WALLS < <(find "$DIR" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) | sort)

if [ ${#WALLS[@]} -eq 0 ]; then
    notify-send "Wallpaper" "В $DIR нет картинок" 2>/dev/null
    exit 1
fi

if [ -f "$INDEX" ]; then
    IDX=$(cat "$INDEX")
else
    IDX=-1
fi

IDX=$(( (IDX + 1) % ${#WALLS[@]} ))
echo "$IDX" > "$INDEX"
echo "${WALLS[$IDX]}" > "$CURRENT"

pkill swaybg
swaybg -i "${WALLS[$IDX]}" -m fill &
