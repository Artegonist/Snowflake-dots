#!/bin/bash

CURRENT="$HOME/.cache/hypr/wallpaper"
DEFAULT="/home/artegonist/Картинки/wallpapers/wallpaper.jpg"

if [ -f "$CURRENT" ]; then
    WALL=$(cat "$CURRENT")
    [ -f "$WALL" ] || WALL="$DEFAULT"
else
    WALL="$DEFAULT"
fi

swaybg -i "$WALL" -m fill &
