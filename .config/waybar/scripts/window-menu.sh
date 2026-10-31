#!/usr/bin/env bash

MAX_TITLE=30
MENU_WIDTH=400
MENU_HEIGHT=250
SHIFT=20
MARGIN=3

cd ~/.config/wofi || exit 1

pkill -u "$(id -u)" -x wofi && exit 0

CLIENTS=$(hyprctl clients -j) || exit 1

declare -A ADDRESSES COUNT
LABELS=()
while IFS=$'\t' read -r label address; do
    COUNT[$label]=$(( ${COUNT[$label]:-0} + 1 ))
    [ "${COUNT[$label]}" -gt 1 ] && label="$label (${COUNT[$label]})"
    LABELS+=("$label")
    ADDRESSES[$label]=$address
done < <(
    jq -r --argjson max "$MAX_TITLE" '
        .[]
        | select(.mapped and (.hidden | not))
        | (.class // "" | gsub("[[:cntrl:]]+"; " ")) as $class
        | (.title // "" | gsub("[[:cntrl:]]+"; " ") | gsub("^ +| +$"; "")) as $title
        | select($class != "" or $title != "")
        | (if ($title | length) > $max then $title[0:$max] + "…" else $title end) as $short
        | (if $class != "" then $class else "?" end) as $name
        | (if $short != "" then "\($name) — \($short)" else $name end) + "\t" + .address
    ' <<<"$CLIENTS"
)

[ "${#LABELS[@]}" -eq 0 ] && exit 0

CX=$(hyprctl cursorpos -j | jq -r '.x | floor')
read -r MX MW < <(
    hyprctl monitors -j |
    jq -r '.[] | select(.focused) | "\(.x) \((if .transform % 2 == 1 then .height else .width end) / .scale | floor)"'
)

XOFF=$(( CX - MX - SHIFT ))
MAXOFF=$(( MW - MENU_WIDTH - MARGIN ))
[ "$XOFF" -gt "$MAXOFF" ] && XOFF=$MAXOFF
[ "$XOFF" -lt "$MARGIN" ] && XOFF=$MARGIN

CHOICE=$(
    printf '%s\n' "${LABELS[@]}" |
    wofi \
        --dmenu \
        --cache-file /dev/null \
        --width "$MENU_WIDTH" \
        --height "$MENU_HEIGHT" \
        --location top_left \
        --xoffset "$XOFF" \
        --yoffset "$MARGIN" \
        --style ~/.config/wofi/window-menu.css
)

[ -z "$CHOICE" ] && exit 0

ADDRESS=${ADDRESSES[$CHOICE]}
[ -n "$ADDRESS" ] || exit 0
hyprctl dispatch focuswindow "address:$ADDRESS"
