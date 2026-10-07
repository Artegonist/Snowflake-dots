#!/usr/bin/env bash
set -euo pipefail

for cmd in hyprctl jq; do
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

exec hyprctl keyword general:layout "$next_layout"
