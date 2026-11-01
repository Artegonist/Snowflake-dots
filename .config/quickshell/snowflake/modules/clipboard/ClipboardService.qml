import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    //--------------------- CONFIG ------------------------

    readonly property string dataDir: Quickshell.env("HOME") + "/.local/share/snowflake/clipboard"
    readonly property string pinsDir: root.dataDir + "/pins"
    readonly property string thumbDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/snowflake-clipboard"
    readonly property real maxAgeMs: 72 * 60 * 60 * 1000
    readonly property int scanIntervalMs: 5 * 60 * 1000
    readonly property var terminals: ["kitty", "foot", "footclient", "Alacritty", "org.wezfurlong.wezterm", "com.mitchellh.ghostty", "org.kde.konsole", "org.gnome.Terminal", "xterm"]

    //--------------------- STATE ------------------------

    property var entries: []
    property var pins: []
    property var thumbs: ({})
    property var files: ({})

    property var seen: ({})
    property bool seenLoaded: false
    property bool pinsLoaded: false
    property bool refreshQueued: false

    property var decodeQueue: []
    property var decodeJob: null
    property var storeQueue: []

    //--------------------- HISTORY ------------------------

    function refresh() {
        if (!root.seenLoaded) return
        if (listProc.running) {
            root.refreshQueued = true
            return
        }
        listProc.running = true
    }

    function parse(raw) {
        const result = []
        for (const line of raw.split("\n")) {
            const tab = line.indexOf("\t")
            if (tab < 0) continue
            const text = line.slice(tab + 1)
            result.push({ id: line.slice(0, tab), text: text, type: root.detectType(text) })
        }
        return result
    }

    function detectType(text) {
        if (text.startsWith("[[ binary data")) return "image"
        if (/^(copy |cut )?file:\/\//.test(text)) return "file"
        if (/^https?:\/\//.test(text)) return "link"
        return "text"
    }

    function apply(all) {
        const now = Date.now()
        const nextSeen = {}
        const fresh = []
        const expired = []
        const known = new Set(all.map(e => e.text))
        const pending = root.entries.filter(e => e.pending && now - e.firstSeen < 3000 && !known.has(e.text))

        for (const entry of all) {
            const firstSeen = root.seen[entry.id] ?? now
            nextSeen[entry.id] = firstSeen
            entry.firstSeen = firstSeen
            if (now - firstSeen > root.maxAgeMs) expired.push(entry.id)
            else fresh.push(entry)
        }

        const merged = pending.concat(fresh)

        if (expired.length > 0) root.remove(expired)
        if (expired.length === 0 && !root.changed(merged)) return

        root.seen = nextSeen
        root.entries = merged
        seenFile.setText(JSON.stringify(nextSeen))
        root.queueDecodes()
    }

    function changed(next) {
        if (next.length !== root.entries.length) return true
        return next.some((e, i) => e.id !== root.entries[i].id)
    }

    function remove(ids) {
        Quickshell.execDetached(["sh", "-c", "printf '%s\\t\\n' \"$@\" | cliphist delete", "sh"].concat(ids))
    }

    function deleteEntry(entry) {
        root.remove([entry.id])
        root.entries = root.entries.filter(e => e.id !== entry.id)
    }

    //--------------------- CLIPBOARD ------------------------

    function copy(entry) {
        if (entry.type === "image") {
            Quickshell.execDetached(["sh", "-c", "t=$(mktemp) && cliphist decode \"$1\" > \"$t\" && [ -s \"$t\" ] && wl-copy -t \"$2\" < \"$t\"; rm -f \"$t\"", "sh", entry.id, root.imageMime(entry.text)])
        } else if (entry.type === "file") {
            Quickshell.execDetached(["sh", "-c", "u=$(cliphist decode \"$1\" | grep -o 'file://[^[:space:]]*') && [ -n \"$u\" ] && printf '%s\\n' \"$u\" | wl-copy -t text/uri-list", "sh", entry.id])
        } else {
            Quickshell.execDetached(["sh", "-c", "t=$(mktemp) && cliphist decode \"$1\" > \"$t\" && [ -s \"$t\" ] && wl-copy < \"$t\"; rm -f \"$t\"", "sh", entry.id])
        }
    }

    function copyPin(pinned) {
        if (pinned.type === "image") {
            Quickshell.execDetached(["sh", "-c", "wl-copy -t \"$1\" < \"$2\"", "sh", root.imageMime(pinned.text), pinned.file])
        } else if (pinned.type === "file") {
            root.copyFiles(root.fileUris(pinned.text))
        } else {
            Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", pinned.text])
        }
    }

    function copyFiles(uris) {
        if (uris.length === 0) return
        Quickshell.execDetached(["sh", "-c", "printf '%s\\r\\n' \"$@\" | wl-copy -t text/uri-list", "sh"].concat(uris))
    }

    function paste() {
        const script = "sleep 0.25\n"
            + "cls=$(hyprctl activewindow | awk -F': ' '/^[[:space:]]*class:/ {print $2; exit}')\n"
            + "term=\n"
            + "for t in \"$@\"; do [ \"$cls\" = \"$t\" ] && term=1; done\n"
            + "if command -v wtype >/dev/null 2>&1; then\n"
            + "  if [ -n \"$term\" ]; then wtype -M ctrl -M shift -k v -m shift -m ctrl; else wtype -M ctrl -k v -m ctrl; fi\n"
            + "else\n"
            + "  if [ -n \"$term\" ]; then mods='CTRL SHIFT'; else mods=CTRL; fi\n"
            + "  hyprctl dispatch sendshortcut \"$mods, V, activewindow\"\n"
            + "fi"
        Quickshell.execDetached(["sh", "-c", script, "sh"].concat(root.terminals))
    }

    //--------------------- PINS ------------------------

    function pin(entry) {
        root.enqueueDecode({ kind: "pin", id: entry.id, text: entry.text, entry: entry, pid: root.newPid() }, true)
    }

    function finishPin(job, text) {
        const isImage = job.entry.type === "image"
        if (!isImage && text.length === 0) return
        const pinned = {
            pid: job.pid,
            type: job.entry.type,
            text: isImage ? job.text : text,
            preview: job.text,
            file: isImage ? job.path : "",
            note: false,
            created: Date.now()
        }
        root.pins = [pinned].concat(root.pins)
        root.savePins()
        root.deleteEntry(job.entry)
    }

    function unpin(pinned) {
        const placeholder = {
            id: "",
            text: pinned.preview || root.previewOf(pinned.text),
            type: pinned.type,
            firstSeen: Date.now(),
            pending: true
        }
        root.entries = [placeholder].concat(root.entries)
        if (pinned.type === "image") {
            root.enqueueStore(["sh", "-c", "cliphist store < \"$1\" && rm -f \"$1\"", "sh", pinned.file])
        } else {
            root.enqueueStore(["sh", "-c", "printf '%s' \"$1\" | cliphist store", "sh", pinned.text])
        }
        root.pins = root.pins.filter(p => p.pid !== pinned.pid)
        root.savePins()
    }

    function removePin(pinned) {
        if (pinned.file) Quickshell.execDetached(["rm", "-f", pinned.file])
        root.pins = root.pins.filter(p => p.pid !== pinned.pid)
        root.savePins()
    }

    function addNote(text) {
        const note = {
            pid: root.newPid(),
            type: /^https?:\/\//.test(text) ? "link" : "text",
            text: text,
            preview: "",
            file: "",
            note: true,
            created: Date.now()
        }
        root.pins = [note].concat(root.pins)
        root.savePins()
    }

    function savePins() {
        pinsFile.setText(JSON.stringify(root.pins))
    }

    function enqueueStore(command) {
        root.storeQueue = root.storeQueue.concat([command])
        root.nextStore()
    }

    function nextStore() {
        if (storeProc.running || root.storeQueue.length === 0) return
        storeProc.command = root.storeQueue[0]
        root.storeQueue = root.storeQueue.slice(1)
        storeProc.running = true
    }

    //--------------------- DECODING ------------------------

    function queueDecodes() {
        for (const e of root.entries) {
            if (e.id === "") continue
            if (e.type === "image" && !root.thumbs[e.text]) root.enqueueDecode({ kind: "thumb", id: e.id, text: e.text }, false)
            else if (e.type === "file" && !root.files[e.text]) root.enqueueDecode({ kind: "file", id: e.id, text: e.text }, false)
        }
    }

    function enqueueDecode(job, urgent) {
        const same = j => j !== null && j.kind === job.kind && j.text === job.text
        if (job.kind !== "pin" && (same(root.decodeJob) || root.decodeQueue.some(same))) return
        root.decodeQueue = urgent ? [job].concat(root.decodeQueue) : root.decodeQueue.concat([job])
        root.nextDecode()
    }

    function nextDecode() {
        if (root.decodeJob !== null || root.decodeQueue.length === 0) return
        const job = root.decodeQueue[0]
        root.decodeQueue = root.decodeQueue.slice(1)
        if (job.kind === "thumb") job.path = root.thumbDir + "/" + root.hashOf(job.text) + "." + root.imageFormat(job.text)
        else if (job.kind === "pin" && job.entry.type === "image") job.path = root.pinsDir + "/" + job.pid + "." + root.imageFormat(job.text)
        root.decodeJob = job
        decodeProc.command = job.path
            ? ["sh", "-c", "cliphist decode \"$1\" > \"$2\"", "sh", job.id, job.path]
            : ["cliphist", "decode", job.id]
        decodeProc.running = true
    }

    function finishDecode(text) {
        const job = root.decodeJob
        root.decodeJob = null
        if (job !== null) {
            if (job.kind === "thumb") {
                root.thumbs = Object.assign({}, root.thumbs, { [job.text]: job.path })
            } else if (job.kind === "file") {
                const uris = root.fileUris(text)
                if (uris.length > 0) root.files = Object.assign({}, root.files, { [job.text]: uris })
            } else {
                root.finishPin(job, text)
            }
        }
        Qt.callLater(root.nextDecode)
    }

    //--------------------- HELPERS ------------------------

    function imageFormat(preview) {
        const m = preview.match(/binary data .+? (\w+) \d+x\d+/)
        return m ? m[1].toLowerCase() : "png"
    }

    function imageMime(preview) {
        return "image/" + root.imageFormat(preview)
    }

    function fileUris(text) {
        return text.split(/\s+/).filter(s => s.startsWith("file://"))
    }

    function previewOf(text) {
        const flat = text.trim().split(/\s+/).join(" ")
        const chars = Array.from(flat)
        return chars.length > 100 ? chars.slice(0, 99).join("") + "…" : flat
    }

    function hashOf(text) {
        let h = 5381
        for (let i = 0; i < text.length; i++) h = ((h * 33) ^ text.charCodeAt(i)) >>> 0
        return h.toString(16)
    }

    function newPid() {
        return Date.now().toString(36) + Math.random().toString(36).slice(2, 6)
    }

    //--------------------- STARTUP ------------------------

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.dataDir, root.pinsDir, root.thumbDir])

    //--------------------- STORAGE ------------------------

    FileView {
        id: seenFile
        path: root.dataDir + "/seen.json"

        onLoaded: {
            if (root.seenLoaded) return
            try {
                root.seen = JSON.parse(text())
            } catch (e) {
                root.seen = {}
            }
            root.seenLoaded = true
            root.refresh()
        }

        onLoadFailed: {
            if (root.seenLoaded) return
            root.seen = {}
            root.seenLoaded = true
            root.refresh()
        }
    }

    FileView {
        id: pinsFile
        path: root.dataDir + "/pins.json"

        onLoaded: {
            if (root.pinsLoaded) return
            try {
                const data = JSON.parse(text())
                root.pins = Array.isArray(data) ? data : []
            } catch (e) {
                root.pins = []
            }
            root.pinsLoaded = true
        }

        onLoadFailed: {
            if (root.pinsLoaded) return
            root.pins = []
            root.pinsLoaded = true
        }
    }

    //--------------------- PROCESSES ------------------------

    Process {
        id: listProc
        command: ["cliphist", "list"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.apply(root.parse(this.text))
                if (root.refreshQueued) {
                    root.refreshQueued = false
                    Qt.callLater(root.refresh)
                }
            }
        }
    }

    Process {
        id: decodeProc

        stdout: StdioCollector {
            onStreamFinished: root.finishDecode(this.text)
        }
    }

    Process {
        id: storeProc

        onExited: {
            root.refresh()
            Qt.callLater(root.nextStore)
        }
    }

    Process {
        id: watchProc
        command: ["wl-paste", "--watch", "echo", "change"]
        running: true

        stdout: SplitParser {
            onRead: {
                refreshSoon.restart()
                refreshLate.restart()
            }
        }

        onExited: rewatch.start()
    }

    //--------------------- TIMERS ------------------------

    Timer {
        interval: root.scanIntervalMs
        running: root.seenLoaded
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        id: refreshSoon
        interval: 400
        onTriggered: root.refresh()
    }

    Timer {
        id: refreshLate
        interval: 1500
        onTriggered: root.refresh()
    }

    Timer {
        id: rewatch
        interval: 3000
        onTriggered: watchProc.running = true
    }
}
