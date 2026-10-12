#!/usr/bin/env bash

set -euo pipefail

action="${1:-next}"

case "$action" in
    next|show)
        ;;
    *)
        printf 'Использование: %s [next|show]\n' "$0" >&2
        exit 2
        ;;
esac

for cmd in hyprctl jq pkill; do
    command -v "$cmd" >/dev/null 2>&1 || {
        printf 'Не найдена команда: %s\n' "$cmd" >&2
        exit 1
    }
done

if ! current_layout=$(
    hyprctl -j getoption general:layout | jq -er '.str'
); then
    printf 'Не удалось получить текущую компоновку окон\n' >&2
    exit 1
fi

if [[ "$action" == "show" ]]; then
    case "$current_layout" in
        dwindle)
            preserve=$(
                hyprctl -j getoption dwindle:preserve_split | jq -er '.int'
            ) || preserve=0
            if [[ "$preserve" == "1" ]]; then
                icon=$'\xef\x80\xa3'   
            else
                icon=$'\xef\x82\x9c'   
            fi
            printf '%s %s\n' "$icon" "${current_layout^}"
            ;;
        *)
            printf '%s\n' "${current_layout^}"
            ;;
    esac
    exit 0
fi

case "$current_layout" in
    dwindle)
        next_layout=master
        ;;
    master)
        next_layout=scrolling
        ;;
    scrolling)
        next_layout=monocle
        ;;
    monocle)
        next_layout=dwindle
        ;;
    *)
        printf 'Переключение из компоновки "%s" не настроено\n' \
            "$current_layout" >&2
        exit 1
        ;;
esac

hyprctl keyword general:layout "$next_layout"

pkill -RTMIN+9 -u "$(id -u)" -x waybar 2>/dev/null || true
