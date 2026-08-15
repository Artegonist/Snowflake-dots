#!/bin/bash

CURRENT="$HOME/.cache/hypr/wallpaper"
DEFAULT="/home/artegonist/Картинки/wallpapers/wallpaper.jpg"

if [ -f "$CURRENT" ]; then
    WALL=$(cat "$CURRENT")
    # на случай если картинку удалили/переименовали - откат на дефолт
    [ -f "$WALL" ] || WALL="$DEFAULT"
else
    WALL="$DEFAULT"
fi

swaybg -i "$WALL" -m fill &
