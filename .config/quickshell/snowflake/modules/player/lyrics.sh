#!/usr/bin/env bash
# lyrics.sh TOKEN ARTIST TITLE ALBUM DURATION_SEC URL
# Ответ: TOKEN <token> / SRC <local|lrclib|none|error> / тело.
# Python используется и в playbutton.sh; дополнительных Python-пакетов не нужно.
if ! command -v python3 >/dev/null 2>&1; then
    printf 'TOKEN %s\nSRC error\n' "${1:-0}"
    exit 0
fi
exec python3 - "$@" <<'PY'
import hashlib
import json
import math
import os
from pathlib import Path
import re
import signal
import sys
import tempfile
import time
import unicodedata
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, unquote, urlsplit
from urllib.request import Request, urlopen

args = (sys.argv[1:] + [""] * 6)[:6]
token, artist, title, album, duration, url = args
CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME") or (Path.home() / ".cache")) / "quickshell-player" / "lyrics"
API = "https://lrclib.net/api"
USER_AGENT = "quickshell-player-module/2.0"
MAX_BODY = 4 * 1024 * 1024
NEGATIVE_TTL = 86400


def emit(source, body=""):
    print("TOKEN " + token)
    print("SRC " + source)
    if body:
        print(body)


def read_local():
    try:
        parsed = urlsplit(url)
        if parsed.scheme != "file" or parsed.netloc not in ("", "localhost"):
            return None
        audio = Path(unquote(parsed.path))
        for suffix in (".lrc", ".LRC", ".txt"):
            candidate = audio.with_suffix(suffix)
            if candidate.is_file() and 0 < candidate.stat().st_size <= MAX_BODY:
                return candidate.read_text(encoding="utf-8-sig", errors="replace")
    except (OSError, ValueError):
        pass
    return None


def normalize_title(value):
    # «Song (Official Video)», «Song - Remastered 2011», «Song [Live]», «Song feat. X»
    text = unicodedata.normalize("NFKC", value or "").casefold()
    text = re.sub(r"[(\[{].*?[)\]}]", " ", text)
    text = re.sub(r"\b(?:feat|ft)\b\.?.*$", " ", text)
    return " ".join(re.sub(r"[^\w]+", " ", text).split())


WANTED_TITLE = normalize_title(title)


def same_song(item):
    # Нечёткий поиск LRCLIB возвращает и чужие песни. Название должно совпасть
    # целыми словами: «song» подходит к «artist song», но «up» не подходит к «upside down».
    found = normalize_title(item.get("trackName") if isinstance(item, dict) else "")
    if not found or not WANTED_TITLE:
        return False
    return (" " + found + " ") in (" " + WANTED_TITLE + " ") \
        or (" " + WANTED_TITLE + " ") in (" " + found + " ")


def only_same_song(data):
    # /api/get отвечает по точной сигнатуре трека — ему доверяем; списки поиска фильтруем.
    if isinstance(data, list):
        return [item for item in data if same_song(item)]
    return data


def has_lyrics(data):
    if isinstance(data, dict):
        return any(isinstance(data.get(key), str) and data[key].strip()
                   for key in ("syncedLyrics", "plainLyrics")) and not data.get("instrumental")
    return isinstance(data, list) and any(has_lyrics(item) for item in data)


def cached_result(path):
    try:
        if path.stat().st_size > MAX_BODY:
            return None
        text = path.read_text(encoding="utf-8")
        header, _, body = text.partition("\n")
        if header == "SRC none" and time.time() - path.stat().st_mtime < NEGATIVE_TTL:
            return "none", ""
        if header == "SRC lrclib":
            # Старый кэш мог сохранить текст чужой песни — отбрасываем и ищем заново.
            data = only_same_song(json.loads(body))
            if has_lyrics(data):
                return "lrclib", json.dumps(data, ensure_ascii=False)
    except (OSError, ValueError, UnicodeError):
        pass
    return None


def store_result(path, source, body):
    temporary = None
    try:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=CACHE_DIR,
                                         prefix=".lyrics-", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write("SRC " + source + "\n" + body + "\n")
        os.replace(temporary, path)
    except OSError:
        pass  # Текст всё равно возвращается, даже если кэш недоступен.
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def fetch(endpoint, params, deadline):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        return None, False
    request = Request(API + "/" + endpoint + "?" + urlencode(params), headers={"User-Agent": USER_AGENT})
    try:
        with urlopen(request, timeout=min(4.0, remaining)) as response:
            body = response.read(MAX_BODY + 1)
        if len(body) > MAX_BODY:
            return None, False
        data = json.loads(body.decode("utf-8"))
        valid = isinstance(data, dict) if endpoint == "get" else (
            isinstance(data, list) and all(isinstance(item, dict) for item in data))
        return (data, True) if valid else (None, False)
    except HTTPError as error:
        return None, error.code == 404
    except (OSError, URLError, ValueError, UnicodeError):
        return None, False


def main():
    local = read_local()
    if local is not None:
        emit("local", local)
        return
    if not title:
        emit("none")
        return
    # Тот же ключ и формат, что в прежнем скрипте: существующий кэш сохраняется.
    key = hashlib.sha1("|".join((artist, title, album, duration)).encode("utf-8")).hexdigest()
    cache = CACHE_DIR / key
    hit = cached_result(cache)
    if hit is not None:
        emit(*hit)
        return
    requests = []
    try:
        seconds = float(duration)
    except ValueError:
        seconds = 0
    if artist:
        if math.isfinite(seconds) and seconds > 0:
            requests.append(("get", {"artist_name": artist, "track_name": title,
                                     "album_name": album, "duration": duration}))
        requests.append(("search", {"artist_name": artist, "track_name": title}))
    requests.append(("search", {"q": (artist + " " + title).strip()}))
    deadline = time.monotonic() + 10
    all_replies_valid = True
    for endpoint, params in requests:
        data, valid = fetch(endpoint, params, deadline)
        all_replies_valid = all_replies_valid and valid
        data = only_same_song(data)
        if has_lyrics(data):
            body = json.dumps(data, ensure_ascii=False)
            store_result(cache, "lrclib", body)
            emit("lrclib", body)
            return
    if all_replies_valid:
        store_result(cache, "none", "")
        emit("none")
    else:
        # Сбой сети не считается отсутствием текста и не кэшируется на сутки.
        emit("error")


signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
try:
    main()
except (OSError, ValueError):
    emit("error")
PY