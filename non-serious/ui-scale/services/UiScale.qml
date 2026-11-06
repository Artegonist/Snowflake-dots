pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Единая шкала масштаба интерфейса для всех окон Snowflake.
//
// Алгоритм (см. scaleFor):
//   1. База: размер экрана в логических пикселях (после масштаба Hyprland) сравнивается с эталоном 1920x1080:
//        k    = min(width / 1920, height / 1080)
//        auto = clamp(k ^ 0.85, 0.65, 2.0)
//      Степень < 1 сглаживает крайности: на маленьких экранах интерфейс не становится нечитаемо мелким,
//      на больших не раздувается сверх меры.
//   2. Ручная настройка: общий масштаб (0 = авто) и отдельный множитель для каждого окна.
//   3. Предохранитель: итог никогда не больше, чем влезает в экран, поэтому окно не вылезет за край.
//
// Настройки хранятся в ~/.local/share/snowflake/hub/ui.json: { "scale": 0, "panels": { "audio": 1.1 } }
Singleton {
    id: root

    // ------------------------- CONSTANTS -------------------------
    readonly property real refWidth: 1920
    readonly property real refHeight: 1080
    readonly property real gamma: 0.85
    readonly property real autoMin: 0.65
    readonly property real autoMax: 2.0
    readonly property real manualMin: 0.5
    readonly property real manualMax: 2.0
    readonly property real step: 0.05
    readonly property real absoluteMin: 0.4
    readonly property real edgeMargin: 16
    readonly property real topReserve: 40

    // Окна, у которых есть отдельный множитель: { id, название }
    readonly property var panelList: [
        { id: "hub",       title: "Hub" },
        { id: "audio",     title: "Звук" },
        { id: "player",    title: "Плеер" },
        { id: "wifi",      title: "Wi-Fi" },
        { id: "bluetooth", title: "Bluetooth" },
        { id: "battery",   title: "Батарея" },
        { id: "sysinfo",   title: "Система" },
        { id: "clipboard", title: "Буфер обмена" },
        { id: "pet",       title: "Питомец" },
        { id: "macro",     title: "Макросы" },
        { id: "power",     title: "Меню питания" },
        { id: "osd",       title: "OSD" }
    ]

    // ------------------------- STATE -------------------------
    // 0 = автоматически по размеру экрана
    property real userScale: 0
    property var panels: ({})

    // Если qs запущен с QT_SCALE_FACTOR, Qt уже умножил всё на этот коэффициент.
    // Учитываем его, чтобы масштаб не применялся дважды.
    readonly property real qtFactor: {
        const v = parseFloat(Quickshell.env("QT_SCALE_FACTOR") || "")
        return v > 0 ? v : 1
    }

    // ------------------------- MATH -------------------------
    function clamp(v, lo, hi) {
        return Math.max(lo, Math.min(hi, v))
    }

    // Размер экрана в логических пикселях компоситора
    function logicalSize(screen) {
        const s = screen ? screen : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
        if (!s || !(s.width > 0) || !(s.height > 0))
            return { w: root.refWidth, h: root.refHeight }
        return { w: s.width * root.qtFactor, h: s.height * root.qtFactor }
    }

    function autoScale(screen) {
        const sz = root.logicalSize(screen)
        const k = Math.min(sz.w / root.refWidth, sz.h / root.refHeight)
        return root.clamp(Math.pow(k, root.gamma), root.autoMin, root.autoMax)
    }

    function panelMultiplier(key) {
        const v = root.panels ? root.panels[key] : undefined
        return (typeof v === "number" && v > 0) ? root.clamp(v, root.manualMin, root.manualMax) : 1
    }

    // Итоговый масштаб окна размером baseW x baseH (в «эталонных» пикселях)
    function scaleFor(key, screen, baseW, baseH) {
        const sz = root.logicalSize(screen)
        const wanted = (root.userScale > 0 ? root.userScale : root.autoScale(screen)) * root.panelMultiplier(key)
        const fit = Math.min((sz.w - 2 * root.edgeMargin) / baseW, (sz.h - root.topReserve) / baseH)
        const s = Math.max(root.absoluteMin, Math.min(wanted, fit))
        return Math.round(s * 100) / 100 / root.qtFactor
    }

    // Для окон настроек: «базовый» масштаб без множителей окон
    function baseScale(screen) {
        return root.userScale > 0 ? root.userScale : root.autoScale(screen)
    }

    // ------------------------- SETTERS -------------------------
    function setUserScale(value) {
        root.userScale = value > 0 ? root.clamp(Math.round(value * 100) / 100, root.manualMin, root.manualMax) : 0
        root.save()
    }

    function setPanelScale(key, value) {
        const next = Object.assign({}, root.panels)
        if (value > 0 && Math.abs(value - 1) > 0.001)
            next[key] = root.clamp(Math.round(value * 100) / 100, root.manualMin, root.manualMax)
        else
            delete next[key]
        root.panels = next
        root.save()
    }

    function resetAll() {
        root.userScale = 0
        root.panels = ({})
        root.save()
    }

    // ------------------------- STORAGE -------------------------
    readonly property string filePath: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/snowflake/hub/ui.json"

    function apply(raw) {
        let data = null
        try {
            data = JSON.parse(raw)
        } catch (e) {
            data = null
        }
        if (!data || typeof data !== "object")
            return

        const s = (typeof data.scale === "number" && data.scale > 0)
            ? root.clamp(data.scale, root.manualMin, root.manualMax) : 0
        if (Math.abs(s - root.userScale) > 0.0001)
            root.userScale = s

        const next = {}
        const src = (data.panels && typeof data.panels === "object") ? data.panels : {}
        for (const key in src) {
            const v = src[key]
            if (typeof v === "number" && v > 0)
                next[key] = root.clamp(v, root.manualMin, root.manualMax)
        }
        if (JSON.stringify(next) !== JSON.stringify(root.panels))
            root.panels = next
    }

    function save() {
        const payload = JSON.stringify({ scale: root.userScale, panels: root.panels })
        if (writer.running) {
            root.pendingPayload = payload
            root.hasPending = true
            return
        }
        writer.payload = payload
        writer.running = true
    }

    property string pendingPayload: ""
    property bool hasPending: false

    FileView {
        id: file
        path: root.filePath
        watchChanges: true
        printErrors: false
        onLoaded: root.apply(file.text())
        onFileChanged: file.reload()
    }

    Process {
        id: writer

        property string payload: ""

        command: ["sh", "-c",
            "f=\"$1\"; mkdir -p \"$(dirname \"$f\")\" && printf '%s' \"$2\" > \"$f.tmp\" && mv -f \"$f.tmp\" \"$f\"",
            "sh", root.filePath, writer.payload]

        onExited: {
            if (!root.hasPending)
                return
            root.hasPending = false
            writer.payload = root.pendingPayload
            Qt.callLater(function() { writer.running = true })
        }
    }
}
