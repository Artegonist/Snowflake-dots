import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: wt

    // ------------------------- STATE -------------------------
    required property var hub

    property bool active: false
    property string mode: "dark"
    property string scheme: "scheme-tonal-spot"
    property bool glow: false
    property int sourceIndex: 0
    property var sources: []
    property string lastWallpaper: ""
    property var lastColors: ({})
    property double lastRun: 0
    property bool busy: false
    property string status: ""
    property bool failed: false

    readonly property var schemes: [
        { id: "scheme-tonal-spot",   title: "Спокойная" },
        { id: "scheme-content",      title: "Как на обоях" },
        { id: "scheme-expressive",   title: "Выразительная" },
        { id: "scheme-fruit-salad",  title: "Фруктовая" },
        { id: "scheme-neutral",      title: "Приглушённая" },
        { id: "scheme-monochrome",   title: "Монохром" }
    ]

    readonly property var keys: ["accent_primary", "accent_secondary", "bg_panel_waybar", "bg_panel_battery",
        "bg_track", "bg_input_wofi", "text_main", "text_dim", "text_waybar", "workspace_active",
        "hover_light", "hover_wofi_select", "wofi_input_text", "wofi_accent_text", "clock_glow"]

    // ------------------------- SETTINGS -------------------------
    JsonFile {
        id: settingsFile
        path: wt.hub.dataDir + "/wallpaper-theme.json"
        legacyPath: ".config/hub-module/wallpaper-theme.json"
        onLoaded: function(s) {
            if (s) {
                wt.active = s.active === true
                if (s.mode === "dark" || s.mode === "light") wt.mode = s.mode
                if (typeof s.scheme === "string" && s.scheme.indexOf("scheme-") === 0) wt.scheme = s.scheme
                wt.glow = s.glow === true
                if (typeof s.sourceIndex === "number") wt.sourceIndex = Math.max(0, Math.min(3, s.sourceIndex))
                if (Array.isArray(s.sources)) wt.sources = s.sources
                if (typeof s.lastWallpaper === "string") wt.lastWallpaper = s.lastWallpaper
                if (s.lastColors && typeof s.lastColors === "object") wt.lastColors = s.lastColors
                if (typeof s.lastRun === "number") wt.lastRun = s.lastRun
            }
        }
    }

    Component.onCompleted: settingsFile.load()

    function save() {
        settingsFile.save({
            active: wt.active, mode: wt.mode, scheme: wt.scheme, glow: wt.glow,
            sourceIndex: wt.sourceIndex, sources: wt.sources,
            lastWallpaper: wt.lastWallpaper, lastColors: wt.lastColors, lastRun: wt.lastRun
        })
    }

    // ------------------------- CONTROL -------------------------
    function enable() {
        wt.active = true
        wt.save()
        wt.run("")
    }

    function disable() {
        if (!wt.active) return
        wt.active = false
        wt.save()
    }

    function setMode(m) { if (m !== wt.mode) { wt.mode = m; wt.save(); if (wt.active) wt.run(wt.lastWallpaper) } }
    function setScheme(s) { if (s !== wt.scheme) { wt.scheme = s; wt.save(); if (wt.active) wt.run(wt.lastWallpaper) } }
    function setGlow(g) { if (g !== wt.glow) { wt.glow = g; wt.save(); if (wt.active) wt.run(wt.lastWallpaper) } }
    function setSourceIndex(i) { if (i !== wt.sourceIndex) { wt.sourceIndex = i; wt.save(); if (wt.active) wt.run(wt.lastWallpaper) } }

    function refresh() {
        if (wt.active) wt.run("")
    }

    function wallpaperApplied(path) {
        if (wt.active) wt.run(path)
    }

    function checkOnOpen() {
        if (!wt.active || wt.busy) return
        if (!wt.stillApplied()) {
            wt.disable()
            return
        }
        currentProc.running = false
        currentProc.running = true
    }

    function stillApplied() {
        const mine = wt.lastColors
        if (!mine || Object.keys(mine).length === 0) return true
        const cur = wt.hub.themeColors
        for (const k in cur) {
            if (mine[k] !== undefined && String(mine[k]).toLowerCase() !== String(cur[k]).toLowerCase())
                return false
        }
        return true
    }

    function run(path) {
        if (wt.busy) {
            wt.pendingPath = path
            wt.pending = true
            return
        }
        wt.busy = true
        wt.failed = false
        wt.status = "Сканирую обои…"
        scanProc.imagePath = path
        scanProc.running = true
    }

    // ------------------------- RUN -------------------------
    property bool pending: false
    property string pendingPath: ""

    readonly property string logPath: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/hub-module/wallpaper-theme.log"

    function finish(ok, msg) {
        wt.busy = false
        wt.failed = !ok
        wt.status = msg
        if (wt.pending) {
            wt.pending = false
            wt.run(wt.pendingPath)
        }
    }

    Connections {
        target: wt.hub
        function onExpandedChanged() {
            if (wt.hub.expanded)
                wt.checkOnOpen()
        }
    }

    // ------------------------- CURRENT WALLPAPER -------------------------
    Process {
        id: currentProc
        command: ["sh", "-c", "cat \"${XDG_CACHE_HOME:-$HOME/.cache}/hypr/wallpaper\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim()
                if (p !== "" && (p !== wt.lastWallpaper || wt.sources.length === 0))
                    wt.run(p)
            }
        }
    }

    // ------------------------- SCAN -------------------------
    Process {
        id: scanProc
        property string imagePath: ""
        command: ["sh", "-c",
            "c=\"${XDG_CACHE_HOME:-$HOME/.cache}/hub-module\"; mkdir -p \"$c\" || exit 1; "
            + "img=\"$1\"; mode=\"$2\"; type=\"$3\"; idx=\"$4\"; log=\"$5\"; cfg=\"$c/matugen-scan.toml\"; "
            + "[ -n \"$img\" ] || img=$(cat \"${XDG_CACHE_HOME:-$HOME/.cache}/hypr/wallpaper\" 2>/dev/null); "
            + "[ -f \"$img\" ] || { echo \"ERR:не нашёл файл текущих обоев\"; exit 2; }; "
            + "command -v matugen >/dev/null 2>&1 || { echo \"ERR:matugen не установлен\"; exit 3; }; "
            + "printf '[config]\\n' > \"$cfg\"; "
            + "{ echo \"=== $(date '+%F %T')  $img  mode=$mode type=$type index=$idx\"; matugen --version 2>&1; } > \"$log\" 2>/dev/null; "
            + "printf 'IMG:%s\\n' \"$img\"; "
            + "src=$(matugen image \"$img\" --dry-run --debug --source-color-index 0 </dev/null 2>&1 >/dev/null "
            + "| grep -oE '[0-9]+: #[0-9a-fA-F]{6}' | grep -oE '#[0-9a-fA-F]{6}'); "
            + "[ -n \"$src\" ] || src=$(matugen image \"$img\" --dry-run --show-source-colors </dev/null 2>/dev/null "
            + "| grep -oiE '#[0-9a-f]{6}' | awk '!seen[tolower($0)]++'); "
            + "printf '%s\\n' \"$src\" | awk 'NF' | head -n 4 | sed 's/^/SRC:/' | tee -a \"$log\"; "
            + "try() { echo \"--- matugen image <обои> -m $mode -t $type --json hex $*\" >> \"$log\"; "
            + "o=$(matugen image \"$img\" -m \"$mode\" -t \"$type\" --json hex \"$@\" </dev/null 2>&1); "
            + "printf '%s\\n' \"$o\" | head -c 3000 >> \"$log\"; printf '%s' \"$o\"; }; "
            + "ok() { case \"$1\" in *'\"colors\"'*) return 0;; esac; return 1; }; "
            + "out=$(try --dry-run --source-color-index \"$idx\"); "
            + "ok \"$out\" || { [ \"$idx\" != 0 ] && out=$(try --dry-run --source-color-index 0); }; "
            + "ok \"$out\" || out=$(try -c \"$cfg\" --source-color-index 0); "
            + "ok \"$out\" || out=$(try --dry-run); "
            + "ok \"$out\" || out=$(try -c \"$cfg\"); "
            + "printf '%s\\n' \"$out\"",
            "sh", scanProc.imagePath, wt.mode, wt.scheme, String(wt.sourceIndex), wt.logPath]
        stdout: StdioCollector {
            onStreamFinished: wt.handleScan(text)
        }
    }

    function handleScan(text) {
        let img = ""
        const srcs = []
        const other = []
        for (const line of text.split("\n")) {
            if (line.indexOf("ERR:") === 0) { wt.finish(false, line.slice(4)); return }
            if (line.indexOf("IMG:") === 0) img = line.slice(4).trim()
            else if (line.indexOf("SRC:") === 0) srcs.push(line.slice(4).trim().toLowerCase())
            else if (line.trim() !== "") other.push(line.trim())
        }
        if (srcs.length > 0) {
            wt.sources = srcs
            if (wt.sourceIndex >= srcs.length)
                wt.sourceIndex = 0
        }
        let a = text.charAt(0) === "{" ? 0 : text.indexOf("\n{")
        if (a > 0) a += 1
        const b = text.lastIndexOf("}")
        let data = null
        if (a >= 0 && b > a) {
            try { data = JSON.parse(text.slice(a, b + 1)) } catch (e) { data = null }
        }
        if (!data) {
            let clean = other.map(l => l.replace(/\x1b\[[0-9;]*m/g, "").trim()).filter(l => l !== "")
            const cut = clean.findIndex(l => /^(Location:|Backtrace|Run with|Note:|Suggestion:)/.test(l))
            if (cut >= 0) clean = clean.slice(0, cut)
            clean = clean.map(l => l.replace(/^\d+:\s*/, ""))
            let i = clean.findIndex(l => /error|ошибк|failed|not found|invalid|unexpected/i.test(l))
            if (i < 0) i = Math.max(0, clean.length - 3)
            const err = clean.slice(i, i + 4).join(" · ").replace(/^Error:\s*·?\s*/i, "")
            wt.finish(false, "matugen не вернул цвета" + (err ? ": " + err.slice(0, 300) : "")
                      + "\nПодробности: ~/.cache/hub-module/wallpaper-theme.log")
            return
        }
        const theme = wt.buildTheme(data.colors || data, wt.mode, wt.glow)
        if (!theme) {
            wt.finish(false, "Непонятный формат ответа matugen")
            return
        }
        wt.lastWallpaper = img
        wt.lastColors = theme
        wt.status = "Применяю…"
        const file = { theme: {} }
        for (const k of wt.keys) file.theme[k] = { color: theme[k] }
        applyProc.payload = JSON.stringify(file, null, 2)
        applyProc.running = true
    }

    // ------------------------- APPLY THEME -------------------------
    Process {
        id: applyProc
        property string payload: ""
        command: ["sh", "-c",
            "c=\"${XDG_CACHE_HOME:-$HOME/.cache}/hub-module\"; f=\"$c/wallpaper-theme.json\"; "
            + "printf '%s\\n' \"$1\" > \"$f.tmp\" && mv \"$f.tmp\" \"$f\" && matugen json \"$f\" 2>&1",
            "sh", applyProc.payload]
        stdout: SplitParser {
            onRead: (line) => console.log("matugen (обои):", line)
        }
        onExited: function(code) {
            if (code === 0) {
                wt.lastRun = Date.now()
                wt.save()
                wt.hub.reloadColors()
                wt.finish(true, "Готово — тема собрана из обоев")
            } else {
                wt.finish(false, "matugen json завершился с ошибкой (" + code + ")")
            }
        }
    }

    // ------------------------- MATERIAL YOU MAPPING -------------------------
    function pickColor(colors, mode, role) {
        if (!colors) return ""
        let v
        if (colors[mode] && colors[mode][role] !== undefined) {
            v = colors[mode][role]
        } else if (colors[role] !== undefined) {
            const r = colors[role]
            v = (r && typeof r === "object") ? (r[mode] !== undefined ? r[mode] : r["default"]) : r
        }
        if (v && typeof v === "object") v = v.color || v.hex || ""
        v = String(v || "")
        return /^#[0-9a-fA-F]{6}/.test(v) ? v.slice(0, 7).toLowerCase() : ""
    }

    function role(colors, mode, names) {
        for (const n of names) {
            const c = wt.pickColor(colors, mode, n)
            if (c) return c
        }
        return ""
    }

    function rgb(h) { return [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16)) }
    function hex(c) { return "#" + c.map(v => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, "0")).join("") }
    function mix(a, b, t) { const x = wt.rgb(a), y = wt.rgb(b); return wt.hex(x.map((v, i) => v + (y[i] - v) * t)) }
    function lum(h) {
        const f = x => { x /= 255; return x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4) }
        const c = wt.rgb(h)
        return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2])
    }
    function contrast(a, b) {
        const x = wt.lum(a), y = wt.lum(b)
        return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05)
    }
    function ensure(fg, bg, min, toward) {
        let c = fg
        for (let i = 1; i <= 10 && wt.contrast(c, bg) < min; i++)
            c = wt.mix(fg, toward, i / 10)
        return c
    }

    function buildTheme(colors, mode, glow) {
        const g = (...names) => wt.role(colors, mode, names)
        const dark = mode !== "light"

        const primary = g("primary")
        const container = g("primary_container")
        const surface = g("surface", "background")
        const onSurface = g("on_surface", "on_background")
        if (!primary || !surface || !onSurface) return null

        const t = {}
        t.bg_panel_waybar = dark ? surface : g("surface_container", "surface")
        t.bg_panel_battery = g("surface_container_low", "surface")
        t.bg_track = g("surface_container_high", "surface_variant", "surface")
        t.bg_input_wofi = g("surface_container", "surface")
        t.text_main = onSurface
        t.text_dim = wt.ensure(g("on_surface_variant") || onSurface, t.bg_panel_battery, 4.5, onSurface)
        t.text_waybar = wt.ensure(g("on_primary_container") || onSurface, t.bg_panel_waybar, 4.5, onSurface)
        t.accent_primary = wt.ensure(primary, t.bg_panel_battery, 3, onSurface)
        t.accent_secondary = container ? wt.mix(container, primary, 0.5) : wt.mix(primary, surface, 0.4)
        t.workspace_active = wt.ensure(primary, t.bg_panel_waybar, 3, onSurface)
        t.hover_light = wt.ensure(g("secondary_container", "surface_variant") || t.bg_track, t.workspace_active, 3, surface)
        t.workspace_active = wt.ensure(t.workspace_active, t.hover_light, 3, onSurface)
        t.hover_wofi_select = g("secondary_container", "surface_variant") || t.bg_track
        t.wofi_input_text = onSurface
        t.wofi_accent_text = wt.ensure(primary, t.bg_input_wofi, 4.5, onSurface)
        t.clock_glow = glow ? primary : t.bg_panel_waybar

        for (const k of wt.keys)
            if (!/^#[0-9a-f]{6}$/.test(t[k] || "")) return null
        return t
    }
}
