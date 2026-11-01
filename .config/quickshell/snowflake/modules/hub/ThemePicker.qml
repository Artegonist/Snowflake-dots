import QtQuick
import QtQuick.Layouts
import Quickshell.Io

Dropdown {
    id: root

    label: "Тема"
    popupHeight: Math.min(list.contentHeight, 280)

    // ------------------------- STATE -------------------------
    readonly property int swatch: 14

    property var themes: []
    property string savedName: ""
    property string pendingName: ""

    // ------------------------- WALLPAPER ENTRY -------------------------
    readonly property var wallTheme: root.hub.wallpaperTheme
    readonly property var wallpaperEntry: {
        const c = root.wallTheme ? root.wallTheme.lastColors : null
        const has = c && c.accent_primary
        return {
            name: "@wallpaper",
            dynamic: true,
            label: root.wallTheme && root.wallTheme.busy ? "Из обоев · сканирую…"
                 : root.wallTheme && root.wallTheme.failed ? "Из обоев · ошибка (см. ⚙)"
                 : "Из обоев",
            colors: has ? [c.accent_primary, c.accent_secondary, c.workspace_active] : ["#777777", "#999999", "#bbbbbb"]
        }
    }
    readonly property var entries: [root.wallpaperEntry].concat(root.themes)

    readonly property int currentIndex: {
        if (root.wallTheme && root.wallTheme.active)
            return 0
        const cur = root.hub.themeColors
        const keys = Object.keys(cur)
        if (keys.length > 0) {
            const same = t => keys.every(k => String(t.palette[k] || "").toLowerCase() === String(cur[k]).toLowerCase())
            const saved = root.themes.findIndex(t => t.name === root.savedName && same(t))
            if (saved >= 0) return saved + 1
            const i = root.themes.findIndex(same)
            if (i >= 0) return i + 1
        }
        const n = root.themes.findIndex(t => t.name === root.savedName)
        return n >= 0 ? n + 1 : -1
    }
    readonly property var current: root.currentIndex >= 0 ? root.entries[root.currentIndex] : null

    function prettify(name) {
        const s = name.replace(/[-_]+/g, " ")
        return s.charAt(0).toUpperCase() + s.slice(1)
    }

    function refresh() {
        if (!listProc.running)
            listProc.running = true
    }

    onExpandedChanged: {
        if (root.expanded) {
            root.refresh()
            savedFile.load()
        }
    }

    Component.onCompleted: {
        root.refresh()
        savedFile.load()
    }

    // ------------------------- THEME LOADER -------------------------
    Process {
        id: listProc
        command: ["sh", "-c",
            "for f in \"$HOME\"/.config/matugen/themes/*.json; do "
            + "[ -f \"$f\" ] || continue; printf '\\036%s\\n' \"$f\"; cat -- \"$f\"; echo; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = []
                for (const chunk of text.split("\x1e")) {
                    const nl = chunk.indexOf("\n")
                    if (nl < 0)
                        continue
                    const path = chunk.slice(0, nl).trim()
                    if (path.length === 0)
                        continue
                    const name = path.split("/").pop().replace(/\.json$/, "")
                    let colors = ["#666666", "#888888", "#aaaaaa"]
                    const palette = {}
                    try {
                        const t = JSON.parse(chunk.slice(nl + 1)).theme || {}
                        for (const k in t) {
                            if (t[k] && t[k].color)
                                palette[k] = t[k].color
                        }
                        colors = [
                            (t.accent_primary   && t.accent_primary.color)   || "#888888",
                            (t.accent_secondary && t.accent_secondary.color) || "#aaaaaa",
                            (t.workspace_active && t.workspace_active.color) || "#cccccc"
                        ]
                    } catch (e) {
                        console.log("ThemePicker: не удалось разобрать", path, e)
                    }
                    list.push({ name: name, label: root.prettify(name), colors: colors, palette: palette })
                }
                if (JSON.stringify(list) !== JSON.stringify(root.themes))
                    root.themes = list
            }
        }
    }

    // ------------------------- SAVED THEME -------------------------
    JsonFile {
        id: savedFile
        path: ".cache/hub-module/theme_name"
        json: false
        onLoaded: function(value) {
            root.savedName = String(value || "").trim()
        }
    }

    // ------------------------- APPLY -------------------------
    Process {
        id: applyProc
        command: ["sh", "-c",
            "mkdir -p \"$HOME/.cache/hub-module\" && printf '%s\\n' \"$1\" > \"$HOME/.cache/hub-module/theme_name\"; "
            + "matugen json \"$HOME/.config/matugen/themes/$1.json\" 2>&1",
            "sh", root.pendingName]
        stdout: SplitParser {
            onRead: (line) => console.log("matugen:", line)
        }
        onExited: root.hub.reloadColors()
    }

    function applyTheme(index) {
        if (index === 0) {
            root.expanded = false
            root.wallTheme.enable()
            return
        }
        const t = root.entries[index]
        if (!t)
            return
        root.wallTheme.disable()
        console.log("ThemePicker: applying theme ->", t.name)
        root.savedName = t.name
        root.pendingName = t.name
        root.expanded = false
        applyProc.running = false
        applyProc.running = true
    }

    // ------------------------- HEADER -------------------------
    header: RowLayout {
        anchors.fill: parent
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: root.current ? root.current.label
                : (root.themes.length === 0 ? "Темы не найдены" : "Выбрать тему")
            color: root.hub.textMain
            font.pixelSize: 14
            font.bold: true
            elide: Text.ElideRight
        }

        Repeater {
            model: root.current ? root.current.colors : []
            delegate: Rectangle {
                required property var modelData
                implicitWidth: root.swatch
                implicitHeight: root.swatch
                radius: 4
                color: modelData
                border.width: 1
                border.color: Qt.rgba(0, 0, 0, 0.25)
            }
        }
    }

    // ------------------------- THEME LIST -------------------------
    ListView {
        id: list
        anchors.fill: parent
        model: root.entries
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        SmoothScroll { flick: list }

        delegate: Rectangle {
            id: themeRow
            required property var modelData
            required property int index
            readonly property bool isCurrent: themeRow.index === root.currentIndex

            width: list.width
            height: root.headerHeight
            color: rowArea.containsMouse ? root.hub.hoverColor
                 : themeRow.isCurrent ? Qt.rgba(1, 1, 1, 0.04) : "transparent"

            Behavior on color { ColorAnimation { duration: 120 } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: root.slotLeft
                anchors.rightMargin: root.slotRight
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: themeRow.modelData.label
                    color: themeRow.isCurrent ? root.hub.accentPrimary : root.hub.textMain
                    font.pixelSize: 14
                    font.bold: themeRow.isCurrent
                    elide: Text.ElideRight
                }

                Repeater {
                    model: themeRow.modelData.colors
                    delegate: Rectangle {
                        required property var modelData
                        implicitWidth: root.swatch
                        implicitHeight: root.swatch
                        radius: 4
                        color: modelData
                        border.width: 1
                        border.color: Qt.rgba(0, 0, 0, 0.25)
                    }
                }
            }

            Rectangle {
                visible: themeRow.index === 0
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                height: 1
                color: Qt.rgba(root.hub.textDim.r, root.hub.textDim.g, root.hub.textDim.b, 0.3)
            }

            MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.applyTheme(themeRow.index)
            }
        }
    }
}
