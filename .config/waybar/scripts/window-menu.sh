#!/usr/bin/env bash

# Максимальная длина названия окна
MAX_TITLE=30

CLIENTS=$(hyprctl clients -j)

CHOICE=$(
    printf '%s' "$CLIENTS" |
    jq -r --argjson max "$MAX_TITLE" '
        to_entries[]
        | select(.value.mapped == true)
        | "\(.key)\t\(.value.class) — \(if (.value.title | length) > $max then (.value.title[0:$max] + "…") else .value.title end)"
    ' |
    wofi \
        --dmenu \
        --width 400 \
        --height 250 \
        --location top_left \
        --xoffset 3 \
        --yoffset 3 \
        --style ~/.config/wofi/window-menu.css
)

# Ничего не выбрали
[ -z "$CHOICE" ] && exit 0

# Получаем индекс выбранного окна
INDEX=$(printf '%s' "$CHOICE" | cut -f1)

# По индексу получаем настоящий address окна
ADDRESS=$(
    printf '%s' "$CLIENTS" |
    jq -r ".[$INDEX].address"
)

# Переключаемся на выбранное окно
[ -n "$ADDRESS" ] &&
    hyprctl dispatch focuswindow "address:$ADDRESS"