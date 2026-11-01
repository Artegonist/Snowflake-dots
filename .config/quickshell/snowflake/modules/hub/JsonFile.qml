import QtQuick
import Quickshell.Io

Process {
    id: file

    // ------------------------- STATE -------------------------
    required property string path
    property string legacyPath: ""
    property bool json: true
    property bool secret: false

    signal loaded(var value)

    property string pendingPayload: ""
    property bool hasPending: false

    // ------------------------- API -------------------------
    function load() {
        if (!file.running)
            file.running = true
    }

    function save(value) {
        const payload = file.json ? JSON.stringify(value) : String(value)
        if (writerProc.running) {
            file.pendingPayload = payload
            file.hasPending = true
            return
        }
        writerProc.payload = payload
        writerProc.running = true
    }

    // ------------------------- READER -------------------------
    command: ["sh", "-c",
        "abs() { case \"$1\" in /*) printf '%s' \"$1\" ;; *) printf '%s/%s' \"$HOME\" \"$1\" ;; esac; }; "
        + "f=$(abs \"$1\"); "
        + "if [ ! -e \"$f\" ] && [ -n \"$2\" ]; then o=$(abs \"$2\"); "
        + "[ -f \"$o\" ] && mkdir -p \"$(dirname \"$f\")\" && cp -p \"$o\" \"$f\"; fi; "
        + "cat -- \"$f\" 2>/dev/null",
        "sh", file.path, file.legacyPath]

    stdout: StdioCollector {
        onStreamFinished: {
            if (!file.json) {
                file.loaded(text)
                return
            }
            let value = null
            try {
                value = JSON.parse(text)
            } catch (e) {
                value = null
            }
            file.loaded(value)
        }
    }

    // ------------------------- WRITER -------------------------
    property Process writer: Process {
        id: writerProc

        property string payload: ""

        command: ["sh", "-c",
            (file.secret ? "umask 077; " : "")
            + "case \"$1\" in /*) f=\"$1\" ;; *) f=\"$HOME/$1\" ;; esac; mkdir -p \"$(dirname \"$f\")\" && printf '%s' \"$2\" > \"$f.tmp\" && mv -f \"$f.tmp\" \"$f\"",
            "sh", file.path, writerProc.payload]

        onExited: {
            if (!file.hasPending)
                return
            file.hasPending = false
            writerProc.payload = file.pendingPayload
            Qt.callLater(function() { writerProc.running = true })
        }
    }
}
