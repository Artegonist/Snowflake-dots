#!/usr/bin/env bash

if ! command -v python3 >/dev/null 2>&1; then
    printf '%s\n' '{"text":" 󰐊 ","class":"stopped","tooltip":"Для playbutton.sh нужен python3"}'
    exit 0
fi

exec python3 - "$@" <<'PY'
import contextlib
import fcntl
import html
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time


CONFIG = os.environ.get("QS_PLAYER_CONFIG", "player-module")
TARGET = "playerSync"

ACTION = sys.argv[1] if len(sys.argv) > 1 else "status"
ACTION = {
    "play-pause": "toggle",
    "prev": "previous",
    "open": "panel",
}.get(ACTION, ACTION)

runtime_root = os.environ.get("XDG_RUNTIME_DIR")
if runtime_root:
    RUNTIME = Path(runtime_root) / "quickshell-player"
else:
    cache_root = os.environ.get("XDG_CACHE_HOME")
    RUNTIME = Path(cache_root or (Path.home() / ".cache")) / "quickshell-player"

STATE = RUNTIME / "waybar-selection.json"

ICON_PLAYING = " 󰏤 "
ICON_PAUSED = " 󰐊 "


def run(args, timeout=1.0):
    try:
        result = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=timeout,
            encoding="utf-8",
            errors="replace",
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        pass

    return None


def ipc(method, *args):
    return run([
        "qs",
        "-c",
        CONFIG,
        "ipc",
        "call",
        TARGET,
        method,
        *args,
    ])


def primary_snapshot():
    output = ipc("snapshot")

    if output is None:
        return None

    try:
        data = json.loads(output)

        if (
            isinstance(data, dict)
            and data.get("protocol") == 1
            and data.get("class") in {"playing", "paused", "stopped"}
            and isinstance(data.get("text"), str)
            and isinstance(data.get("tooltip"), str)
        ):
            return data

    except (ValueError, TypeError):
        pass

    return None


def read_state():
    try:
        data = json.loads(STATE.read_text())
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save_state(selected, manual=False):
    temporary = None

    try:
        RUNTIME.mkdir(parents=True, exist_ok=True, mode=0o700)

        with tempfile.NamedTemporaryFile(
            "w",
            dir=RUNTIME,
            prefix=".selection-",
            delete=False,
        ) as stream:
            temporary = Path(stream.name)

            json.dump(
                {
                    "selected": selected,
                    "manual": manual,
                },
                stream,
            )

        os.replace(temporary, STATE)

    except OSError:
        pass

    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def available_players():
    names = (
        run(["playerctl", "--list-all"]) or ""
    ).splitlines()

    players = []

    for name in dict.fromkeys(names):
        status = run([
            "playerctl",
            "--player=" + name,
            "status",
        ])

        if status in {"Playing", "Paused", "Stopped"}:
            players.append((name, status))

    return players


def select_fallback(players, saved):
    if not players:
        return None

    saved_player = saved.get("selected")

    selected = next(
        (player for player in players if player[0] == saved_player),
        None,
    )

    if selected and (
        saved.get("manual")
        or selected[1] == "Playing"
    ):
        return selected

    return next(
        (player for player in players if player[1] == "Playing"),
        selected or players[0],
    )


def fallback_snapshot(players=None):
    if players is None:
        players = available_players()

    saved = read_state()
    selected = select_fallback(players, saved)

    if selected is None:
        return {
            "text": ICON_PAUSED,
            "class": "stopped",
            "tooltip": "Нет активных плееров",
        }

    name, status = selected

    artist = run([
        "playerctl",
        "--player=" + name,
        "metadata",
        "--format",
        "{{artist}}",
    ])

    title = run([
        "playerctl",
        "--player=" + name,
        "metadata",
        "--format",
        "{{title}}",
    ])

    track = " — ".join(
        part for part in (artist, title) if part
    ) or "Без названия"

    return {
        "text": ICON_PLAYING if status == "Playing" else ICON_PAUSED,
        "class": status.lower(),
        "tooltip": html.escape(
            track + "\n" + name,
            quote=False,
        ),
    }


def output_waybar(data):
    print(
        json.dumps(
            {
                "text": data["text"],
                "class": data["class"],
                "tooltip": data["tooltip"],
            },
            ensure_ascii=False,
        ),
        flush=True,
    )


@contextlib.contextmanager
def command_lock():
    RUNTIME.mkdir(
        parents=True,
        exist_ok=True,
        mode=0o700,
    )

    with (RUNTIME / "command.lock").open("a") as stream:
        deadline = time.monotonic() + 3

        while True:
            try:
                fcntl.flock(
                    stream,
                    fcntl.LOCK_EX | fcntl.LOCK_NB,
                )
                break

            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise RuntimeError(
                        "Предыдущая команда плеера ещё выполняется"
                    )

                time.sleep(0.025)

        try:
            yield

        finally:
            fcntl.flock(stream, fcntl.LOCK_UN)


def fallback_action(action):
    players = available_players()
    saved = read_state()
    selected = select_fallback(players, saved)

    if action == "auto":
        save_state(
            selected[0] if selected else "",
            False,
        )
        return True

    if selected is None:
        return False

    name, _ = selected

    commands = {
        "toggle": ["play-pause"],
        "next": ["next"],
        "previous": ["previous"],
        "play": ["play"],
        "pause": ["pause"],
    }

    command = commands.get(action)

    if command is None:
        return False

    save_state(
        name,
        bool(
            saved.get("manual")
            and saved.get("selected") == name
        ),
    )

    return run(
        [
            "playerctl",
            "--player=" + name,
            *command,
        ],
        timeout=2,
    ) is not None


def main():
    allowed_actions = {
        "status",
        "diagnose",
        "toggle",
        "play",
        "pause",
        "next",
        "previous",
        "panel",
        "auto",
    }

    if ACTION not in allowed_actions:
        print(
            "Команды: status toggle play pause next previous panel auto diagnose",
            file=sys.stderr,
        )
        return 2

    if ACTION in {"status", "diagnose"}:
        data = primary_snapshot()

        if ACTION == "diagnose":
            print(
                json.dumps(
                    {
                        "controller": (
                            "quickshell"
                            if data is not None
                            else "playerctl"
                        ),
                        "config": CONFIG,
                        "snapshot": data or fallback_snapshot(),
                    },
                    ensure_ascii=False,
                    indent=2,
                )
            )
        else:
            output_waybar(
                data if data is not None else fallback_snapshot()
            )

        return 0

    with command_lock():
        data = primary_snapshot()

        if data is not None:
            # Не повторяем команду через playerctl,
            # чтобы случайно не выполнить toggle дважды.
            return 0 if ipc("action", ACTION) == "ok" else 1

        if ACTION == "panel":
            if not shutil.which("qs"):
                return 1

            subprocess.Popen(
                ["qs", "-c", CONFIG],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )

            deadline = time.monotonic() + 3

            while time.monotonic() < deadline:
                if primary_snapshot() is not None:
                    return (
                        0
                        if ipc("action", "panel") == "ok"
                        else 1
                    )

                time.sleep(0.1)

            return 1

        return 0 if fallback_action(ACTION) else 1


try:
    sys.exit(main())

except (OSError, RuntimeError) as error:
    print(
        "playbutton: " + str(error),
        file=sys.stderr,
    )

    if ACTION == "status":
        output_waybar(
            {
                "text": ICON_PAUSED,
                "class": "stopped",
                "tooltip": "Плеер временно недоступен",
            }
        )
        sys.exit(0)

    sys.exit(1)
PY
