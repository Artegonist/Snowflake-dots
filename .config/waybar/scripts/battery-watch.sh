#!/usr/bin/env bash

set -uo pipefail

for command in upower jq stdbuf; do
    if ! command -v "$command" >/dev/null 2>&1; then
        printf '{"text":"","tooltip":"Не найдена зависимость: %s","class":"error"}\n' "$command"
        exit 0
    fi
done

ICONS_DEFAULT=("󰂎" "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹")
ICON_CHARGING="󰂄"
ICON_FULL="󱟢"
ICON_WARNING="󰂃"
ICON_CRITICAL="󱉝"

WARNING_THRESHOLD=30
CRITICAL_THRESHOLD=5

find_battery_device() {
    upower -e 2>/dev/null | grep -m1 'BAT' || true
}

BATTERY_DEV="$(find_battery_device)"

if [[ -z "${BATTERY_DEV}" ]]; then
    echo '{"text":"","tooltip":"Нет батареи","class":"no-battery"}'
    exit 0
fi

pick_icon() {
    local percent="$1"
    local state="$2"

    if [[ "$state" == "fully-charged" ]]; then
        echo "$ICON_FULL"
        return
    fi
    if [[ "$state" == "charging" ]]; then
        echo "$ICON_CHARGING"
        return
    fi
    if (( percent <= CRITICAL_THRESHOLD )); then
        echo "$ICON_CRITICAL"
        return
    fi
    if (( percent <= WARNING_THRESHOLD )); then
        echo "$ICON_WARNING"
        return
    fi

    local idx=$(( percent * (${#ICONS_DEFAULT[@]} - 1) / 100 ))
    echo "${ICONS_DEFAULT[$idx]}"
}

pick_class() {
    local percent="$1"
    local state="$2"

    if [[ "$state" == "fully-charged" ]]; then
        echo "full"
    elif [[ "$state" == "charging" ]]; then
        echo "charging"
    elif (( percent <= CRITICAL_THRESHOLD )); then
        echo "critical"
    elif (( percent <= WARNING_THRESHOLD )); then
        echo "warning"
    else
        echo "normal"
    fi
}

emit_state() {
    local info percent state icon class text

    info="$(upower -i "$BATTERY_DEV" 2>/dev/null || true)"
    [[ -z "$info" ]] && return 0

    percent="$(grep -m1 'percentage:' <<<"$info" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)"
    state="$(grep -m1 'state:' <<<"$info" 2>/dev/null | awk '{print $2}' || true)"

    [[ -z "$percent" ]] && percent=0
    [[ -z "$state" ]] && state="unknown"

    icon="$(pick_icon "$percent" "$state")"
    class="$(pick_class "$percent" "$state")"
    text=" ${icon} ${percent}% "

    local time_line tooltip
    if [[ "$state" == "charging" ]]; then
        time_line="$(grep -m1 'time to full:' <<<"$info" 2>/dev/null | sed 's/^ *time to full: *//' || true)"
        tooltip="До полной зарядки: ${time_line:-—}"
    elif [[ "$state" == "discharging" ]]; then
        time_line="$(grep -m1 'time to empty:' <<<"$info" 2>/dev/null | sed 's/^ *time to empty: *//' || true)"
        tooltip="Осталось: ${time_line:-—}"
    elif [[ "$state" == "fully-charged" ]]; then
        tooltip="Батарея заряжена"
    else
        tooltip="Состояние: ${state}"
    fi

    jq -nc \
        --arg text "$text" \
        --arg tooltip "$tooltip" \
        --arg class "$class" \
        --argjson percentage "$percent" \
        '{text: $text, tooltip: $tooltip, class: $class, percentage: $percentage}' 2>/dev/null || true
}

emit_state

while true; do
    stdbuf -oL upower --monitor-detail 2>/dev/null | while read -r line; do
        if [[ "$line" == *"$BATTERY_DEV"* ]] || [[ "$line" == *"device changed"* ]] || [[ "$line" == *"device added"* ]]; then
            emit_state
        fi
    done
    emit_state
    sleep 1
done
