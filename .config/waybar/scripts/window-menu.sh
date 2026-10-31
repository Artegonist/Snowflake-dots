#!/usr/bin/env bash

MAX_TITLE=30
MENU_WIDTH=400
SHIFT=20

CLIENTS=$(hyprctl clients -j)

CURSOR=$(hyprctl cursorpos -j)
CX=$(jq -r '.x | floor' <<<"$CURSOR")
MON=$(hyprctl monitors -j | jq -c '.[] | select(.focused)')
MX=$(jq -r '.x' <<<"$MON")
MW=$(jq -r '(.width / .scale) | floor' <<<"$MON")

XOFF=$(( CX - MX - SHIFT ))

MAXOFF=$(( MW - MENU_WIDTH - 3 ))
[ "$XOFF" -gt "$MAXOFF" ] && XOFF=$MAXOFF
[ "$XOFF" -lt 3 ] && XOFF=3

CHOICE=$(
    printf '%s' "$CLIENTS" |
    jq -r --argjson max "$MAX_TITLE" '
        to_entries[]
        | select(.value.mapped == true)
        | "\(.key)\t\(.value.class) — \(if (.value.title | length) > $max then (.value.title[0:$max] + "…") else .value.title end)"
    ' |
    wofi \
        --dmenu \
        --width "$MENU_WIDTH" \
        --height 250 \
        --location top_left \
        --xoffset "$XOFF" \
        --yoffset 3 \
        --style ~/.config/wofi/window-menu.css
)

[ -z "$CHOICE" ] && exit 0

INDEX=$(printf '%s' "$CHOICE" | cut -f1)

ADDRESS=$(
    printf '%s' "$CLIENTS" |
    jq -r ".[$INDEX].address"
)

[ -n "$ADDRESS" ] &&
    hyprctl dispatch focuswindow "address:$ADDRESS"
