import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../services"

PanelWindow {
    id: root

    property bool active: false
    property bool closing: false
    property bool cursorOver: false
    property int pressedIndex: -1
    property string focusedClass: ""
    property bool fullscreen: false
    property var fsCache: ({})        // адрес окна -> fullscreen (чтобы не дёргать hyprctl при каждой смене фокуса)
    property bool resyncQueued: false
    property var macros: ({})
    readonly property int trackPad: 12

    readonly property string macroScript: Quickshell.env("HOME") + "/.config/hypr/scripts/macro.sh"

    visible: false
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    mask: Region { width: 0; height: 0 }

    anchors { bottom: true; right: true }
    margins { bottom: 3; right: 3 }
    implicitWidth: 288
    implicitHeight: 70

    //--------------------- LIFECYCLE ----------------------
    // F9-F12 теперь ВСЕГДА забиндены на global shortcut, пока работает quickshell.
    // Если макроса нет - клавиша пробрасывается в окно через macro.sh (см. press()).
    // Так нет гонок "включить/выключить бинд" при смене окна.

    Component.onCompleted: {
        const w = Hyprland.activeToplevel
        focusedClass = (w?.wayland?.appId || w?.lastIpcObject?.class || "").toLowerCase()
        resync()
        // небольшая задержка: при reload старый экземпляр мог ещё выполнять "off"
        bindsInitTimer.start()
    }

    Component.onDestruction: {
        // не оставляем F9-F12 мёртвыми, если панель закрылась
        Quickshell.execDetached([root.macroScript, "binds", "off"])
    }

    function applyBinds() {
        Quickshell.execDetached([root.macroScript, "binds", "on"])
    }

    Timer {
        id: bindsInitTimer
        interval: 400
        repeat: false
        onTriggered: root.applyBinds()
    }

    //--------------------- FOCUS TRACKING ----------------------
    function rememberFullscreen(addr, value) {
        if (fsCache[addr] === value) return
        const next = Object.assign({}, fsCache)
        next[addr] = value
        fsCache = next
    }

    function forgetFullscreen(addr) {
        if (fsCache[addr] === undefined) return
        const next = {}
        for (const k in fsCache)
            if (k !== addr) next[k] = fsCache[k]
        fsCache = next
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activewindow") {
                root.focusedClass = event.data.split(",")[0].toLowerCase()
            } else if (event.name === "activewindowv2") {
                // fullscreen нового окна берём из кеша; hyprctl только для окна, которое видим впервые
                const addr = event.data ? "0x" + event.data : ""
                if (addr === "")
                    root.fullscreen = false
                else if (root.fsCache[addr] !== undefined)
                    root.fullscreen = root.fsCache[addr]
                else
                    root.resync()
            } else if (event.name === "fullscreen" || event.name === "closelayer") {
                // fullscreen меняют редко (действие пользователя) - тут можно спросить точное состояние
                root.resync()
            } else if (event.name === "openwindow") {
                // data: адрес,воркспейс,класс,заголовок
                root.applyLayout((event.data.split(",")[2] || "").toLowerCase())
            } else if (event.name === "closewindow") {
                root.forgetFullscreen("0x" + event.data)
            } else if (event.name === "configreloaded") {
                // hyprctl reload сбрасывает динамические бинды
                root.applyBinds()
            }
        }
    }

    Process {
        id: awProc
        command: ["hyprctl", "activewindow", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const w = JSON.parse(text)
                    root.focusedClass = (w.class || "").toLowerCase()
                    // новые версии Hyprland: fullscreen = 0/1/2 (2 = настоящий fullscreen, 1 = maximize)
                    // старые: fullscreen = bool + fullscreenMode (1 = maximize)
                    root.fullscreen = (w.fullscreen === 2)
                                   || (w.fullscreen === true && w.fullscreenMode !== 1)
                    if (w.address)
                        root.rememberFullscreen(w.address, root.fullscreen)
                } catch (e) {
                    root.focusedClass = ""
                    root.fullscreen = false
                }
            }
        }
        // если во время работы пришёл новый запрос - выполняем его после завершения, а не теряем
        onRunningChanged: {
            if (!running && root.resyncQueued) {
                root.resyncQueued = false
                running = true
            }
        }
    }

    // Раскладка при запуске программы: секция "_layouts" в macros.json, например {"obsidian": 0, "telegramdesktop": 1}
    // Число = индекс раскладки из kb_layout (us=0, ru=1, dk=2). Раскладка одна на всю систему, не на окно.
    function applyLayout(cls) {
        const map = macros["_layouts"]
        if (cls === "" || !map || typeof map !== "object")
            return

        let key = ""
        if (map[cls] !== undefined) {
            key = cls
        } else {
            for (const k in map) {
                if (cls.startsWith(k.toLowerCase()) && k.length > key.length)
                    key = k
            }
        }
        if (key === "" || typeof map[key] !== "number")
            return

        Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", String(map[key])])
    }

    function resync() {
        if (awProc.running)
            resyncQueued = true
        else
            awProc.running = true
    }

    //--------------------- ACTIVE APP + MACROS ----------------------
    readonly property string appClass: focusedClass

    function findKey(cls) {
        if (cls === "")
            return ""
        if (macros[cls] !== undefined)
            return cls

        let best = ""
        for (const k in macros) {
            if (cls.startsWith(k.toLowerCase()) && k.length > best.length)
                best = k
        }
        return best
    }

    readonly property string macroKey: findKey(appClass)

    // Набор приложения и набор по умолчанию ("_default" в macros.json)
    readonly property var appSet:
        (macroKey !== "" && Array.isArray(macros[macroKey])) ? macros[macroKey] : null
    readonly property var defaultSet:
        Array.isArray(macros["_default"]) ? macros["_default"] : null

    readonly property bool hasMacros:
        (appSet !== null && appSet.length > 0) || (defaultSet !== null && defaultSet.length > 0)

    readonly property var emptySet: [
        { icon: "", exec: [] },
        { icon: "", exec: [] },
        { icon: "", exec: [] },
        { icon: "", exec: [] }
    ]

    // Каждый слот: свой макрос приложения -> иначе макрос из "_default" -> иначе пусто
    readonly property var current: {
        const out = []
        for (let i = 0; i < 4; i++)
            out.push((appSet && appSet[i]) || (defaultSet && defaultSet[i]) || emptySet[i])
        return out
    }

    //--------------------- MACROS FILE ----------------------
    readonly property string macrosFile: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/snowflake/macrobar/macros.json"
    property bool macrosMigrated: false

    Process {
        running: true
        command: ["sh", "-c",
            'mkdir -p "$(dirname "$1")" && { [ -e "$1" ] || [ ! -f "$2" ] || cp -p "$2" "$1"; }',
            "snowflake-migrate", root.macrosFile, Quickshell.env("HOME") + "/.config/macrobar/macros.json"]
        onExited: root.macrosMigrated = true
    }

    FileView {
        id: macroFile
        path: root.macrosMigrated ? root.macrosFile : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.macros = JSON.parse(macroFile.text())
            } catch (e) {
                console.log("macros.json parse error:", e)
                root.macros = ({})
            }
        }
        onLoadFailed: root.macros = ({})
    }

    //--------------------- API for shell.qml ----------------------
    function show()   { active = true }
    function hide()   { active = false }
    function toggle() { active = !active }

    function press(i) {
        const m = (active && hasMacros && !fullscreen) ? current[i] : null
        const hasAction = !!m && ((m.exec && m.exec.length > 0) || !!m.keys
                                  || (m.launch && m.launch.length > 1))

        // Панель скрыта, полноэкранный режим или для этого слота нет макроса -> отдаём F-клавишу окну как есть
        if (!hasAction) {
            Quickshell.execDetached([root.macroScript, "send", ",F" + (i + 9)])
            return
        }

        pressedIndex = i
        releaseTimer.restart()

        // execDetached: каждое нажатие - независимый процесс, ничего не теряется
        if (m.exec && m.exec.length > 0) {
            Quickshell.execDetached(m.exec)
        } else if (m.launch && m.launch.length > 1) {
            // ["класс", "команда", "аргументы"...]: фокус на открытое окно или запуск
            Quickshell.execDetached([root.macroScript, "launch"].concat(m.launch))
        } else if (m.keys) {
            Quickshell.execDetached([root.macroScript, "send", m.keys])
        }
    }

    onActiveChanged: {
        openAnim.stop()
        closeAnim.stop()
        if (active) {
            closing = false
            if (!root.visible)
                root.visible = true
            cursorOver = false
            openAnim.start()
            resync()
        } else {
            closing = true
            closeAnim.start()
        }
    }

    //--------------------- SHORTCUTS ----------------------
    GlobalShortcut { name: "macro1"; description: "Macro F9";  onPressed: root.press(0) }
    GlobalShortcut { name: "macro2"; description: "Macro F10"; onPressed: root.press(1) }
    GlobalShortcut { name: "macro3"; description: "Macro F11"; onPressed: root.press(2) }
    GlobalShortcut { name: "macro4"; description: "Macro F12"; onPressed: root.press(3) }

    //--------------------- CURSOR HIDE ----------------------
    Process {
        id: cursorProc
        command: ["hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const p = JSON.parse(text)
                    const s = root.screen
                    if (!s) return

                    const left   = s.x + s.width  - root.margins.right  - root.width  - root.trackPad
                    const top    = s.y + s.height - root.margins.bottom - root.height - root.trackPad
                    const right  = s.x + s.width
                    const bottom = s.y + s.height

                    root.cursorOver = p.x >= left && p.x <= right
                                   && p.y >= top  && p.y <= bottom
                } catch (e) {
                    // ignore
                }
            }
        }
    }

    //--------------------- TIMERS ----------------------
    Timer {
        // было 80 мс (~12 процессов hyprctl/сек), теперь реже
        interval: 150
        repeat: true
        running: root.active
        onTriggered: if (!cursorProc.running) cursorProc.running = true
    }

    Timer {
        id: releaseTimer
        interval: 150
        onTriggered: root.pressedIndex = -1
    }

    //--------------------- COLORS (matugen) ----------------------
    readonly property color accentPrimary:   Theme.accentPrimary
    readonly property color accentSecondary: Theme.accentSecondary
    readonly property color bgPanel:         Theme.bgPanelBattery
    readonly property color bgTrack:         Theme.bgTrack
    readonly property color textMain:        Theme.textMain
    readonly property color textDim:         Theme.textDim

    //--------------------- WRAPPER (прячется при наведении) ----------------------
    Item {
        id: wrapper
        anchors.fill: parent

        opacity: root.cursorOver ? 0 : 1
        Behavior on opacity {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }

        //--------------------- CARD ----------------------
        Rectangle {
            id: card
            anchors.fill: parent
            radius: 8
            color: root.bgPanel
            border.width: 3
            border.color: root.accentPrimary

            transformOrigin: Item.BottomRight
            opacity: 0
            scale: 0.85

            ParallelAnimation {
                id: openAnim
                running: false
                NumberAnimation { target: card; property: "opacity"; to: 1; duration: 150; easing.type: Easing.OutCubic }
                NumberAnimation { target: card; property: "scale"; to: 1; duration: 190; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
            }

            SequentialAnimation {
                id: closeAnim
                ParallelAnimation {
                    NumberAnimation { target: card; property: "opacity"; to: 0; duration: 120; easing.type: Easing.InCubic }
                    NumberAnimation { target: card; property: "scale"; to: 0.85; duration: 120; easing.type: Easing.InCubic }
                }
                ScriptAction { script: root.closing = false }
            }

            //--------------------- BUTTONS ----------------------
            RowLayout {
                id: buttonRow
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                Repeater {
                    model: root.current

                    delegate: Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Rectangle {
                            id: btn
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 36
                            radius: 10

                            readonly property bool pressed: root.pressedIndex === index

                            color: pressed ? root.accentPrimary : root.bgTrack
                            scale: pressed ? 0.93 : 1.0
                            readonly property bool hasAction:
                                (modelData.exec && modelData.exec.length > 0) || !!modelData.keys
                                || (modelData.launch && modelData.launch.length > 1)

                            opacity: (hasAction && !root.fullscreen) ? 1.0 : 0.4

                            Behavior on color {
                                ColorAnimation { duration: 180; easing.type: Easing.OutCubic }
                            }

                            Behavior on scale {
                                NumberAnimation { duration: 140; easing.type: Easing.OutBack }
                            }

                            Behavior on opacity {
                                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: modelData.icon
                                font.pixelSize: 18
                                color: btn.pressed ? root.bgPanel : root.textMain

                                Behavior on color {
                                    ColorAnimation { duration: 180; easing.type: Easing.OutCubic }
                                }
                            }
                        }

                        Text {
                            anchors.top: btn.bottom
                            anchors.topMargin: 4
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "F" + (index + 9)
                            font.pixelSize: 10
                            color: root.textDim
                        }
                    }
                }
            }
        }
    }
}
