#!/usr/bin/env bash


STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/snowflake"
STATE="$STATE_DIR/float-mode"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}/snowflake-float-mode"
OWNED="$RUNTIME/owned"
SOCKET="${XDG_RUNTIME_DIR:-/tmp}/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

FLOAT_W=800
FLOAT_H=600
CASCADE=32

for cmd in hyprctl jq socat flock; do
    command -v "$cmd" >/dev/null 2>&1 || {
        printf 'Не найдена команда: %s\n' "$cmd" >&2
        exit 1
    }
done

mkdir -p "$STATE_DIR" "$RUNTIME" || exit 1
[[ -e "$OWNED" ]] || : > "$OWNED"

get_state() {
    local value=""
    [[ -r "$STATE" ]] && IFS= read -r value < "$STATE"
    [[ "$value" == on ]] && echo on || echo off
}

set_state() {
    printf '%s\n' "$1" > "$STATE.tmp" && mv -- "$STATE.tmp" "$STATE"
}

notify() {
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send -a Snowflake -t 1500 "Float mode" "$1" 2>/dev/null || true
}

plan() {
    jq -r --arg only "$1" --argjson w "$FLOAT_W" --argjson h "$FLOAT_H" --argjson step "$CASCADE" \
        --slurpfile mons <(hyprctl monitors -j) '
        def tileable: (.floating | not)
            and ((.mapped // true) == true)
            and (((.fullscreen // 0) | tostring) | IN("0", "false"));
        ($mons[0] | map({key: (.id | tostring), value: .}) | from_entries) as $M
        | . as $all
        | [$all[] | select(tileable) | select($only == "" or .address == $only)] as $targets
        | ($targets | group_by(.workspace.id)[]) as $grp
        | ([$all[] | select(.floating and .workspace.id == $grp[0].workspace.id)] | length) as $base
        | $grp | to_entries[]
        | .value as $c
        | (($base + .key) % 8) as $i
        | $M[($c.monitor | tostring)] as $m
        | "dispatch setfloating address:\($c.address) ; " as $float
        | if $m == null then "\($c.address)\t\($float)" else
            ($m.reserved // [0, 0, 0, 0]) as $r
            | (($m.width / $m.scale) - $r[0] - $r[2]) as $aw
            | (($m.height / $m.scale) - $r[1] - $r[3]) as $ah
            | ([$w, $aw - 40] | min | floor) as $ww
            | ([$h, $ah - 40] | min | floor) as $hh
            | (($m.x + $r[0] + ($aw - $ww) / 2 + $i * $step) | floor) as $x
            | (($m.y + $r[1] + ($ah - $hh) / 2 + $i * $step) | floor) as $y
            | "\($c.address)\t\($float)dispatch resizewindowpixel exact \($ww) \($hh),address:\($c.address) ; dispatch movewindowpixel exact \($x) \($y),address:\($c.address) ; "
          end
    ' < <(hyprctl clients -j)
}

apply_plan() {
    local addr cmds batch=""
    {
        flock 8
        while IFS=$'\t' read -r addr cmds; do
            [[ -n "$addr" ]] || continue
            batch+="$cmds"
            grep -qxF -- "$addr" "$OWNED" || printf '%s\n' "$addr" >> "$OWNED"
        done < <(plan "$1")
    } 8>"$RUNTIME/owned.lock"
    [[ -n "$batch" ]] && hyprctl --batch "$batch" >/dev/null
    return 0
}

float_all() {
    apply_plan ""
}

float_new() {
    apply_plan "$1"
}

tile_owned() {
    local floating batch="" addr
    floating=$(hyprctl clients -j | jq -r '.[] | select(.floating) | .address')
    {
        flock 8
        while IFS= read -r addr; do
            [[ -n "$addr" ]] || continue
            grep -qxF -- "$addr" <<< "$floating" && batch+="dispatch settiled address:$addr ; "
        done < "$OWNED"
        : > "$OWNED"
    } 8>"$RUNTIME/owned.lock"
    [[ -n "$batch" ]] && hyprctl --batch "$batch" >/dev/null
    return 0
}

ensure_daemon() {
    flock -n "$RUNTIME/daemon.lock" true || return 0
    setsid -f "$(readlink -f -- "$0")" daemon >/dev/null 2>&1 < /dev/null
}

toggle() {
    if [[ "$(get_state)" == on ]]; then
        set_state off
        tile_owned
        notify "выключен"
    else
        set_state on
        float_all
        ensure_daemon
        notify "включён"
    fi
}

daemon() {
    exec 9>"$RUNTIME/daemon.lock"
    flock -n 9 || exit 0

    [[ "$(get_state)" == on ]] && float_all

    while [[ -S "$SOCKET" ]]; do
        socat -U - "UNIX-CONNECT:$SOCKET" 2>/dev/null | while IFS= read -r line; do
            [[ "$line" == openwindow\>\>* ]] || continue
            [[ "$(get_state)" == on ]] || continue
            addr="${line#openwindow>>}"
            float_new "0x${addr%%,*}"
        done
        sleep 1
    done
}

case "${1:-toggle}" in
    toggle) toggle ;;
    daemon) daemon ;;
    status) get_state ;;
    *)
        printf 'Использование: %s [toggle|daemon|status]\n' "${0##*/}" >&2
        exit 2
        ;;
esac
