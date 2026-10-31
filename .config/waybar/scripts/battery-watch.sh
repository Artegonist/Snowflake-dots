#!/usr/bin/env bash

if ! command -v python3 >/dev/null 2>&1; then
    printf '%s\n' '{"text":" 󰐊 ","class":"stopped","tooltip":"Для playbutton.sh нужен python3"}'
    exit 0
fi

exec python3 -I -S - "$@" <<'PY'
import contextlib
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import time


CONFIG = os.environ.get("QS_PLAYER_CONFIG", "player-module")
TARGET = "playerSync"

ACTIONS = {
    "status", "diagnose", "toggle", "play", "pause", "next", "previous",
    "panel", "auto", "cycle", "seek-forward", "seek-backward",
}
ALIASES = {"play-pause": "toggle", "prev": "previous", "open": "panel"}
ACTION = sys.argv[1] if len(sys.argv) > 1 else "status"
ACTION = ALIASES.get(ACTION, ACTION)

runtime_root = os.environ.get("XDG_RUNTIME_DIR")
if runtime_root:
    RUNTIME = Path(runtime_root) / "quickshell-player"
else:
    cache_root = os.environ.get("XDG_CACHE_HOME")
    RUNTIME = Path(cache_root or (Path.home() / ".cache")) / "quickshell-player"

STATE = RUNTIME / "waybar-selection.json"

ICON_PLAYING = " 󰏤 "
ICON_PAUSED = " 󰐊 "
STATUSES = {"Playing", "Paused", "Stopped"}

PROXY_PLAYERS = {"playerctld"}


def log(message):
    print("playbutton: " + message, file=sys.stderr)


def run(args, timeout=1.0):
    try:
        result = subprocess.run(
            args,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=timeout,
            encoding="utf-8",
            errors="replace",
        )
    except subprocess.TimeoutExpired:
        return "timeout", None
    except OSError:
        return "failed", None

    if result.returncode == 0:
        return "ok", result.stdout
    return "failed", None


def output_of(args, timeout=1.0):
    status, out = run(args, timeout)
    return out.strip() if status == "ok" else None


def ipc(method, *args, timeout=1.5):
    return run(["qs", "-c", CONFIG, "ipc", "call", TARGET, method, *args], timeout)


def quickshell_running():
    return run(["qs", "-c", CONFIG, "ipc", "show"], timeout=1.5)[0] == "ok"


def primary_snapshot():
    status, output = ipc("snapshot")
    if status != "ok":
        return None

    try:
        data = json.loads(output)
    except (ValueError, TypeError):
        return None

    if (
        isinstance(data, dict)
        and data.get("protocol") == 1
        and data.get("class") in {"playing", "paused", "stopped"}
        and isinstance(data.get("text"), str)
        and isinstance(data.get("tooltip"), str)
    ):
        return data
    return None


def read_state():
    try:
        data = json.loads(STATE.read_text())
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save_state(selected, manual=False):
    import tempfile

    temporary = None
    try:
        RUNTIME.mkdir(parents=True, exist_ok=True, mode=0o700)
        with tempfile.NamedTemporaryFile("w", dir=RUNTIME, prefix=".selection-", delete=False) as stream:
            temporary = Path(stream.name)
            json.dump({"selected": selected, "manual": manual}, stream)
        os.replace(temporary, STATE)
    except OSError:
        pass
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def is_proxy(name):
    return name.split(".")[0] in PROXY_PLAYERS


def drop_proxies(players):
    real = [player for player in players if not is_proxy(player[0])]
    return real or players


def available_players():
    out = output_of(["playerctl", "--all-players", "status", "--format", "{{playerInstance}}\t{{status}}"])
    players = []
    for line in (out or "").splitlines():
        name, sep, status = line.partition("\t")
        if sep and name.strip() and status.strip() in STATUSES:
            players.append((name.strip(), status.strip()))
    if players:
        return drop_proxies(list(dict.fromkeys(players)))

    names = [name.strip() for name in (output_of(["playerctl", "--list-all"]) or "").splitlines()]
    for name in dict.fromkeys(name for name in names if name):
        status = output_of(["playerctl", "--player=" + name, "status"])
        if status in STATUSES:
            players.append((name, status))
    return drop_proxies(players)


def select_fallback(players, saved):
    if not players:
        return None

    saved_player = saved.get("selected")
    selected = next((player for player in players if player[0] == saved_player), None)

    if selected and (saved.get("manual") or selected[1] == "Playing"):
        return selected

    return next((player for player in players if player[1] == "Playing"), selected or players[0])


def fallback_snapshot(players=None):
    import html

    if players is None:
        players = available_players()

    selected = select_fallback(players, read_state())
    if selected is None:
        return {"text": ICON_PAUSED, "class": "stopped", "tooltip": "Нет активных плееров"}

    name, status = selected

    status_meta, meta = run(["playerctl", "--player=" + name, "metadata", "--format", "{{artist}}\t{{title}}"])
    artist, _, title = (meta or "").rstrip("\n").partition("\t") if status_meta == "ok" else ("", "", "")

    track = " — ".join(part.strip() for part in (artist, title) if part.strip()) or "Без названия"

    return {
        "text": ICON_PLAYING if status == "Playing" else ICON_PAUSED,
        "class": status.lower(),
        "tooltip": html.escape(track + "\n" + name, quote=False),
    }


def wait_for_status_change(name, before, timeout=0.5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if output_of(["playerctl", "--player=" + name, "status"], timeout=0.3) != before:
            return
        time.sleep(0.04)


def fallback_action(action):
    players = available_players()
    saved = read_state()
    selected = select_fallback(players, saved)

    if action == "auto":
        save_state(selected[0] if selected else "", False)
        return True

    if action == "cycle":
        if len(players) < 2:
            return False
        names = [player[0] for player in players]
        current = names.index(selected[0]) if selected else -1
        save_state(names[(current + 1) % len(names)], True)
        return True

    if selected is None:
        return False

    commands = {
        "toggle": ["play-pause"],
        "next": ["next"],
        "previous": ["previous"],
        "play": ["play"],
        "pause": ["pause"],
        "seek-forward": ["position", "5+"],
        "seek-backward": ["position", "5-"],
    }
    command = commands.get(action)
    if command is None:
        return False

    name, before = selected
    save_state(name, bool(saved.get("manual") and saved.get("selected") == name))
    if run(["playerctl", "--player=" + name, *command], timeout=2)[0] != "ok":
        return False

    if action in {"toggle", "play", "pause"}:
        wait_for_status_change(name, before)
    return True


def output_waybar(data):
    print(
        json.dumps(
            {"text": data["text"], "class": data["class"], "tooltip": data["tooltip"]},
            ensure_ascii=False,
        ),
        flush=True,
    )


@contextlib.contextmanager
def command_lock():
    RUNTIME.mkdir(parents=True, exist_ok=True, mode=0o700)

    with (RUNTIME / "command.lock").open("a") as stream:
        deadline = time.monotonic() + 3
        while True:
            try:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise RuntimeError("предыдущая команда плеера ещё выполняется")
                time.sleep(0.025)

        try:
            yield
        finally:
            fcntl.flock(stream, fcntl.LOCK_UN)


def open_panel():
    import shutil

    if shutil.which("qs") is None:
        log("qs не найден в PATH")
        return 1

    if not quickshell_running():
        subprocess.Popen(
            ["qs", "-c", CONFIG],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        status, out = ipc("action", "panel", timeout=2.0)
        if status == "ok":
            return 0 if out.strip() == "ok" else 1
        if status == "timeout":
            return 1
        time.sleep(0.15)

    log(CONFIG + " не запустился за 5 с")
    return 1


def handle_action():
    with command_lock():
        status, out = ipc("action", ACTION, timeout=2.0)

        if status == "ok":
            return 0 if out.strip() == "ok" else 1

        if status == "timeout":
            log("quickshell не ответил вовремя, команда не повторяется")
            return 1

        if ACTION == "panel":
            return open_panel()
        return 0 if fallback_action(ACTION) else 1


def main():
    if ACTION not in ACTIONS:
        print("Команды: " + " ".join(sorted(ACTIONS)), file=sys.stderr)
        return 2

    if ACTION == "status":
        output_waybar(primary_snapshot() or fallback_snapshot())
        return 0

    if ACTION == "diagnose":
        data = primary_snapshot()
        print(
            json.dumps(
                {
                    "controller": "quickshell" if data is not None else "playerctl",
                    "config": CONFIG,
                    "quickshellRunning": quickshell_running(),
                    "players": available_players(),
                    "snapshot": data or fallback_snapshot(),
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return 0

    return handle_action()


try:
    code = main()
except Exception as error:
    log(type(error).__name__ + ": " + str(error))
    if ACTION == "status":
        output_waybar({"text": ICON_PAUSED, "class": "stopped", "tooltip": "Плеер временно недоступен"})
        code = 0
    else:
        code = 1

sys.exit(code)
PY
