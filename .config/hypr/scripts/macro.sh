#!/bin/sh

keycode() {
    case "$1" in
        q|Q) echo 16 ;; w|W) echo 17 ;; e|E) echo 18 ;; r|R) echo 19 ;; t|T) echo 20 ;;
        y|Y) echo 21 ;; u|U) echo 22 ;; i|I) echo 23 ;; o|O) echo 24 ;; p|P) echo 25 ;;
        a|A) echo 30 ;; s|S) echo 31 ;; d|D) echo 32 ;; f|F) echo 33 ;; g|G) echo 34 ;;
        h|H) echo 35 ;; j|J) echo 36 ;; k|K) echo 37 ;; l|L) echo 38 ;;
        z|Z) echo 44 ;; x|X) echo 45 ;; c|C) echo 46 ;; v|V) echo 47 ;; b|B) echo 48 ;;
        n|N) echo 49 ;; m|M) echo 50 ;;
        1) echo 2 ;; 2) echo 3 ;; 3) echo 4 ;; 4) echo 5 ;; 5) echo 6 ;;
        6) echo 7 ;; 7) echo 8 ;; 8) echo 9 ;; 9) echo 10 ;; 0) echo 11 ;;
        Tab) echo 15 ;; grave) echo 41 ;; space) echo 57 ;;
        Return|Enter) echo 28 ;; Escape) echo 1 ;;
        Up) echo 103 ;; Left) echo 105 ;; Right) echo 106 ;; Down) echo 108 ;;
        F1) echo 59 ;; F2) echo 60 ;; F3) echo 61 ;; F4) echo 62 ;; F5) echo 63 ;;
        F6) echo 64 ;; F7) echo 65 ;; F8) echo 66 ;; F9) echo 67 ;; F10) echo 68 ;;
        F11) echo 87 ;; F12) echo 88 ;;
        *) return 1 ;;
    esac
}

modcode() {
    case "$1" in
        CTRL|CONTROL)    echo 29 ;;
        SHIFT)           echo 42 ;;
        ALT)             echo 56 ;;
        SUPER|META|MOD4) echo 125 ;;
        *) return 1 ;;
    esac
}

do_send() {
    spec="$1"
    [ -z "$spec" ] && { echo "usage: $0 send \"MODS,key\"" >&2; exit 1; }

    mods="${spec%%,*}"
    key="${spec#*,}"

    if command -v ydotool >/dev/null 2>&1 && kc=$(keycode "$key"); then
        down=""
        up=""
        for m in $mods; do
            mc=$(modcode "$m") || continue
            down="$down $mc:1"
            up="$mc:0 $up"          
        done
        exec ydotool key -d 20 $down $kc:1 $kc:0 $up
    fi

    msg="macro: ydotool недоступен или клавиша '$key' неизвестна, использую sendshortcut"
    echo "$msg" >&2
    command -v notify-send >/dev/null 2>&1 && notify-send -u low "Macros" "$msg"
    exec hyprctl dispatch sendshortcut "$mods,$key,activewindow"
}

do_binds() {
    cmd=""
    n=1
    for k in F9 F10 F11 F12; do
        case "$1" in
            on)  cmd="$cmd keyword unbind , $k ; keyword bindi , $k, global, quickshell:macro$n ;" ;;
            off) cmd="$cmd keyword unbind , $k ;" ;;
            *)   echo "usage: $0 binds on|off" >&2; exit 1 ;;
        esac
        n=$((n + 1))
    done
    exec hyprctl --batch "$cmd"
}

do_launch() {
    [ $# -lt 2 ] && { echo "usage: $0 launch CLASS COMMAND..." >&2; exit 1; }
    cls="$1"
    shift

    found=$(hyprctl clients -j | grep -io "\"class\": *\"$cls\"" | head -1 | sed 's/.*: *"\(.*\)"/\1/')
    if [ -n "$found" ]; then
        exec hyprctl dispatch focuswindow "class:^($found)\$"
    fi
    exec "$@"
}

case "$1" in
    send)  do_send "$2" ;;
    launch) shift; do_launch "$@" ;;
    binds) do_binds "$2" ;;
    *)
        echo "usage: $0 binds on|off | send \"MODS,key\" | launch CLASS COMMAND..." >&2
        exit 1
        ;;
esac
