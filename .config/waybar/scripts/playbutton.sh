#!/bin/bash

LOCKFILE="/tmp/waybar-playerctl-listener.lock"
LASTFILE="/tmp/waybar-playerctl-last"

list_players() {
    playerctl --all-players metadata --format $'{{playerName}}\t{{status}}\t{{artist}}\t{{title}}' 2>/dev/null
}

find_playing_player() {
    found_status=""; found_artist=""; found_title=""
    local p_player p_status p_artist p_title
    while IFS=$'\t' read -r p_player p_status p_artist p_title; do
        [[ -z "$p_player" ]] && continue
        if [[ "$p_status" == "Playing" ]]; then
            found_status="$p_status"; found_artist="$p_artist"; found_title="$p_title"
            echo "$p_player"
            return
        fi
    done < <(list_players)
}

print_status() {
    local ICON_PLAYING=" 󰏤 "
    local ICON_PAUSED=" 󰐊 "
    local ICON_STOPPED=" 󰐊 "

    local status="" artist="" title=""
    local fallback_status="" fallback_artist="" fallback_title=""
    local p_player p_status p_artist p_title

    while IFS=$'\t' read -r p_player p_status p_artist p_title; do
        [[ -z "$p_player" ]] && continue
        if [[ "$p_status" == "Playing" ]]; then
            status="$p_status"; artist="$p_artist"; title="$p_title"
            break
        elif [[ -z "$fallback_status" ]]; then
            fallback_status="$p_status"; fallback_artist="$p_artist"; fallback_title="$p_title"
        fi
    done < <(list_players)

    if [[ -z "$status" ]]; then
        status="$fallback_status"; artist="$fallback_artist"; title="$fallback_title"
    fi

    case "$status" in
        "Playing") icon="$ICON_PLAYING"; class="playing" ;;
        "Paused")  icon="$ICON_PAUSED";  class="paused"  ;;
        *)         icon="$ICON_STOPPED"; class="stopped" ;;
    esac

    tooltip="${artist:-No player}${title:+ - $title}"
    tooltip=$(echo "$tooltip" | sed 's/"/\\"/g')

    printf '{"text": "%s", "class": "%s", "tooltip": "%s"}\n' "$icon" "$class" "$tooltip"
}

toggle_play_pause() {
    local target
    target=$(find_playing_player)

    if [[ -z "$target" && -f "$LASTFILE" ]]; then
        local saved
        saved=$(<"$LASTFILE")
        if [[ -n "$saved" ]] && playerctl -p "$saved" status &>/dev/null; then
            target="$saved"
        fi
    fi

    if [[ -z "$target" ]]; then
        target=$(playerctl -l 2>/dev/null | head -n1)
    fi

    if [[ -n "$target" ]]; then
        echo "$target" > "$LASTFILE"
        playerctl -p "$target" play-pause
    else
        playerctl play-pause
    fi
}

start_listener() {
    (
        flock -n 200 || exit 0
        setsid bash -c '
            follow_and_update() {
                local prop="$1"
                playerctl --all-players --follow "$prop" 2>/dev/null | while IFS= read -r _; do
                    pkill -RTMIN+8 waybar
                done
            }

            # оба следим только для того, чтобы дёрнуть waybar на перерисовку;
            # актуальные данные всегда берутся заново в print_status
            follow_and_update status &
            follow_and_update metadata &

            wait
        ' >/dev/null 2>&1 &
        disown
    ) 200>"$LOCKFILE"
}

case "$1" in
    toggle)
        toggle_play_pause
        ;;
    *)
        start_listener
        print_status
        ;;
esac
