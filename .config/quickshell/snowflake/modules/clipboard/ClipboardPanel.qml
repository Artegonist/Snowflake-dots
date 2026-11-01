import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: panel

    //--------------------- CONFIG ------------------------

    readonly property bool autoPaste: true
    readonly property bool closeOnPaste: false
    readonly property bool typeOnOpen: true
    readonly property bool refocusAfterPaste: true

    //--------------------- STATE ------------------------

    required property var service

    property bool shown: false
    property bool typing: false
    property bool noteOpen: false
    property bool draggingOut: false
    property string category: "all"
    property string selectedKey: ""
    property real now: Date.now()
    readonly property string home: Quickshell.env("HOME")

    readonly property var categories: [
        { key: "all", label: "Все" },
        { key: "pinned", label: "Закреп" },
        { key: "text", label: "Текст" },
        { key: "image", label: "Картинки" },
        { key: "file", label: "Файлы" }
    ]

    signal flashed(string key)

    property var items: []
    property var lookup: ({})
    property var orderRank: ({})
    property int minRank: 0

    readonly property var icons: ({
        search: "M4.5 11 A6.5 6.5 0 1 0 17.5 11 A6.5 6.5 0 1 0 4.5 11 M20 20 L15.8 15.8",
        text: "M5 7 L19 7 M5 12 L19 12 M5 17 L14 17",
        link: "M10 14 A4 4 0 0 0 15.66 14 L18.66 11 A4 4 0 0 0 13 5.34 L12 6.34 M14 10 A4 4 0 0 0 8.34 10 L5.34 13 A4 4 0 0 0 11 18.66 L12 17.66",
        file: "M14 3 L7 3 Q6 3 6 4 L6 20 Q6 21 7 21 L17 21 Q18 21 18 20 L18 7 Z M14 3 L14 7 L18 7",
        image: "M5 5 L19 5 Q20 5 20 6 L20 18 Q20 19 19 19 L5 19 Q4 19 4 18 L4 6 Q4 5 5 5 Z M4 16 L9 11 L13 15 L15.5 12.5 L20 17",
        plus: "M12 5 L12 19 M5 12 L19 12",
        x: "M6 6 L18 18 M18 6 L6 18",
        drop: "M12 3 L12 15 M7 10 L12 15 L17 10 M5 20 L19 20",
        flake: "M12 2 L12 22 M3.34 7 L20.66 17 M3.34 17 L20.66 7 M9 4 L12 7 L15 4 M9 20 L12 17 L15 20 M3.57 10.6 L7.67 9.5 L6.57 5.4 M20.43 13.4 L16.33 14.5 L17.43 18.6 M3.57 13.4 L7.67 14.5 L6.57 18.6 M20.43 10.6 L16.33 9.5 L17.43 5.4"
    })

    visible: false
    implicitWidth: 420
    implicitHeight: 560
    color: "transparent"

    anchors {
        left: true
        bottom: true
    }

    margins {
        left: 3
        bottom: 3
    }

    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0

    WlrLayershell.keyboardFocus: panel.typing ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    //--------------------- FOCUS ------------------------

    HyprlandFocusGrab {
        id: focusGrab
        windows: [panel]
        onCleared: panel.stopTyping()
    }

    //--------------------- MASK ------------------------

    Region {
        id: emptyRegion
        x: 0
        y: 0
        width: 0
        height: 0
    }

    //--------------------- COLORS ------------------------

    FileView {
        path: panel.home + "/.config/quickshell/clipboard-module/colors.json"
        watchChanges: true
        onFileChanged: reload()

        JsonAdapter {
            id: theme
            property string bg_panel: "#071113"
            property string border_panel: "#80deea"
            property string surface: "#0a1618"
            property string item_hover: "#0f1e21"
            property string accent_primary: "#80deea"
            property string chip_active_bg: "#006064"
            property string chip_active_text: "#80deea"
            property string selection: "#006064"
            property string text_main: "#e0fbff"
            property string text_dim: "#5c9aa3"
            property string danger: "#e57373"
        }
    }

    //--------------------- MODEL ------------------------

    ListModel {
        id: rows
    }

    Connections {
        target: panel.service

        function onEntriesChanged() {
            Qt.callLater(panel.rebuild)
        }

        function onPinsChanged() {
            Qt.callLater(panel.rebuild)
        }
    }

    onCategoryChanged: Qt.callLater(panel.rebuild)

    //--------------------- COMPONENTS ------------------------

    component Glyph: Item {
        id: glyph

        property string path
        property color tint
        property real size: 16

        width: size
        height: size

        Behavior on tint {
            ColorAnimation { duration: 140 }
        }

        Shape {
            width: 24
            height: 24
            scale: glyph.size / 24
            transformOrigin: Item.TopLeft
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: glyph.tint
                strokeWidth: 1.8
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: glyph.path }
            }
        }
    }

    component IconButton: Rectangle {
        id: button

        property string icon
        property color tint
        property color hoverTint

        signal clicked()

        width: 26
        height: 26
        radius: 7
        color: buttonMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
        scale: buttonMouse.pressed ? 0.86 : 1

        Behavior on color {
            ColorAnimation { duration: 120 }
        }

        Behavior on scale {
            NumberAnimation { duration: 120; easing.type: Easing.OutBack }
        }

        Glyph {
            anchors.centerIn: parent
            size: 15
            path: button.icon
            tint: buttonMouse.containsMouse ? button.hoverTint : button.tint
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }

    //--------------------- PANEL ------------------------

    function show() {
        panel.now = Date.now()
        panel.category = "all"
        panel.selectedKey = ""
        panel.closeNote()
        input.text = ""
        panel.orderRank = {}
        panel.minRank = 0
        Qt.callLater(panel.rebuild)
        panel.service.refresh()
        panel.shown = true
        closeAnim.stop()
        if (!panel.visible) panel.visible = true
        panel.mask = null
        openAnim.restart()
        if (panel.typeOnOpen) panel.startTyping()
    }

    function hide() {
        if (!panel.shown) return
        panel.shown = false
        panel.stopTyping()
        panel.mask = emptyRegion
        openAnim.stop()
        closeAnim.restart()
    }

    function startTyping() {
        panel.typing = true
        focusGrab.active = true
        input.forceActiveFocus()
    }

    function focusPanel() {
        if (!panel.shown) return
        panel.typing = true
        focusGrab.active = true
        if (!noteInput.activeFocus) input.forceActiveFocus()
    }

    function stopTyping() {
        panel.typing = false
        focusGrab.active = false
    }

    function toggle() {
        panel.shown ? panel.hide() : panel.show()
    }

    function openNote() {
        panel.noteOpen = true
        panel.typing = true
        focusGrab.active = true
        noteInput.forceActiveFocus()
    }

    function closeNote() {
        panel.noteOpen = false
        noteInput.text = ""
        panel.stopTyping()
    }

    function saveNote() {
        const text = noteInput.text.trim()
        if (text.length === 0) return
        panel.service.addNote(text)
        panel.category = "all"
        panel.closeNote()
    }

    //--------------------- LIST ------------------------

    function rebuild() {
        const q = input.text.trim().toLowerCase()
        const cat = panel.category
        const fits = item => {
            if (cat === "text" && item.type !== "text" && item.type !== "link") return false
            if (cat === "image" && item.type !== "image") return false
            if (cat === "file" && item.type !== "file") return false
            return q.length === 0 || item.text.toLowerCase().includes(q)
        }

        const pinned = panel.service.pins
            .filter(fits)
            .map(p => ({ kind: "pin", key: "p:" + p.pid, entry: p }))

        const previews = new Set(panel.service.pins.map(p => p.preview).filter(p => !!p))
        const ranks = panel.orderRank
        const firstPass = Object.keys(ranks).length === 0
        const counts = {}
        const history = []
        panel.service.entries.forEach((e, index) => {
            if (previews.has(e.text)) return
            counts[e.text] = (counts[e.text] ?? 0) + 1
            const key = "h:" + e.text + (counts[e.text] > 1 ? "#" + counts[e.text] : "")
            if (ranks[key] === undefined) {
                if (firstPass) ranks[key] = index
                else ranks[key] = --panel.minRank
            }
            history.push({ kind: "entry", key: key, entry: e })
        })

        const recent = cat === "pinned" ? [] : history
            .filter(h => fits(h.entry))
            .sort((a, b) => ranks[a.key] - ranks[b.key])

        const both = pinned.length > 0 && recent.length > 0
        const next = (both ? [{ kind: "header", key: "hp", label: "Pinned" }] : [])
            .concat(pinned)
            .concat(both ? [{ kind: "header", key: "hr", label: "Recent" }] : [])
            .concat(recent)

        const map = {}
        for (const item of next) map[item.key] = item
        panel.lookup = map
        panel.items = next
        panel.sync(next)
        panel.keepSelection()
    }

    function sync(next) {
        const wanted = new Set(next.map(i => i.key))
        const current = []
        for (let i = 0; i < rows.count; i++) current.push(rows.get(i).key)

        for (let i = current.length - 1; i >= 0; i--) {
            if (wanted.has(current[i])) continue
            rows.remove(i)
            current.splice(i, 1)
        }

        for (let i = 0; i < next.length; i++) {
            const key = next[i].key
            if (current[i] === key) continue
            const from = current.indexOf(key, i + 1)
            if (from >= 0) {
                rows.move(from, i, 1)
                current.splice(from, 1)
                current.splice(i, 0, key)
            } else {
                rows.insert(i, { key: key, kind: next[i].kind, label: next[i].label ?? "" })
                current.splice(i, 0, key)
            }
        }
    }

    function selectables() {
        return panel.items.filter(i => i.kind !== "header")
    }

    function selectedItem() {
        return panel.items.find(i => i.key === panel.selectedKey) ?? null
    }

    function keepSelection() {
        const list = panel.selectables()
        if (list.some(i => i.key === panel.selectedKey)) return
        panel.selectedKey = list.length > 0 ? list[0].key : ""
    }

    function moveSelection(step) {
        const list = panel.selectables()
        if (list.length === 0) return
        const index = list.findIndex(i => i.key === panel.selectedKey)
        const next = Math.max(0, Math.min(list.length - 1, index + step))
        panel.selectedKey = list[next].key
        const row = panel.items.findIndex(i => i.key === panel.selectedKey)
        if (row >= 0) listView.positionViewAtIndex(row, ListView.Contain)
    }

    //--------------------- ACTIONS ------------------------

    function activate(item) {
        if (!item || item.kind === "header") return
        panel.flashed(item.key)
        if (item.kind === "pin") panel.service.copyPin(item.entry)
        else panel.service.copy(item.entry)
        if (panel.closeOnPaste) panel.hide()
        else panel.stopTyping()
        if (panel.autoPaste) panel.service.paste()
        if (!panel.closeOnPaste && panel.refocusAfterPaste) refocus.restart()
    }

    function togglePin(item) {
        if (!item || item.kind === "header") return
        if (item.kind === "pin") panel.service.unpin(item.entry)
        else panel.service.pin(item.entry)
        panel.focusPanel()
    }

    function deleteItem(item) {
        if (!item || item.kind === "header") return
        const list = panel.selectables()
        const index = list.findIndex(i => i.key === item.key)
        const neighbour = list[index + 1] ?? list[index - 1] ?? null
        if (item.kind === "pin") panel.service.removePin(item.entry)
        else panel.service.deleteEntry(item.entry)
        panel.selectedKey = neighbour ? neighbour.key : ""
        panel.focusPanel()
    }

    function dragUris(entry, isPin) {
        if (entry.type === "file") {
            if (isPin) return panel.service.fileUris(entry.text)
            return panel.service.files[entry.text] ?? panel.service.fileUris(entry.text)
        }
        if (entry.type === "image") {
            const path = isPin ? entry.file : panel.service.thumbs[entry.text]
            return path ? ["file://" + encodeURI(path)] : []
        }
        return []
    }

    //--------------------- FORMAT ------------------------

    function filePaths(text) {
        return text.replace(/^(copy|cut) /, "")
            .split(/\s+/)
            .filter(s => s.startsWith("file://"))
            .map(s => decodeURIComponent(s.slice(7)).replace(/\/$/, ""))
    }

    function shortPath(path) {
        return path.startsWith(panel.home) ? "~" + path.slice(panel.home.length) : path
    }

    function describe(entry) {
        if (entry.type === "file") {
            const paths = panel.filePaths(entry.text)
            if (paths.length === 0) return { title: entry.text, meta: "" }
            return {
                title: paths.length > 1 ? paths.length + " files" : paths[0].split("/").pop(),
                meta: panel.shortPath(paths[0].slice(0, paths[0].lastIndexOf("/")))
            }
        }
        if (entry.type === "image") {
            const m = entry.text.match(/binary data (.+?) (\w+) (\d+)x(\d+)/)
            return { title: "Image", meta: m ? m[2].toUpperCase() + ", " + m[3] + "×" + m[4] + ", " + m[1] : "" }
        }
        const title = entry.text.replace(/\s+/g, " ").trim()
        if (entry.note) return { title: title, meta: "Note" }
        if (entry.type === "link") {
            const m = entry.text.match(/^https?:\/\/([^\/\s]+)/)
            return { title: title, meta: m ? m[1] : "" }
        }
        return { title: title, meta: "" }
    }

    function ageText(ms) {
        const m = Math.floor(ms / 60000)
        if (m < 1) return "now"
        if (m < 60) return m + "m"
        if (m < 1440) return Math.floor(m / 60) + "h"
        const d = Math.floor(m / 1440)
        const h = Math.floor((m % 1440) / 60)
        return h > 0 ? d + "d " + h + "h" : d + "d"
    }

    function emptyText() {
        const q = input.text.trim()
        if (q.length > 0) return "Nothing matches “" + q + "”."
        if (panel.category === "pinned") return "Ничего не закреплено"
        if (panel.category === "image") return "Картинок нету"
        if (panel.category === "file") return "Файлов нету"
        if (panel.category === "text") return "Текста нету"
        return "Пусто"
    }

    //--------------------- TIMERS ------------------------

    Timer {
        id: refocus
        interval: 650
        onTriggered: panel.focusPanel()
    }

    Timer {
        interval: 60000
        running: panel.shown
        repeat: true
        onTriggered: panel.now = Date.now()
    }

    //--------------------- ANIMATIONS ------------------------

    SequentialAnimation {
        id: openAnim

        ParallelAnimation {
            NumberAnimation { target: frame; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutCubic }
            NumberAnimation { target: frame; property: "scale"; to: 1; duration: 260; easing.type: Easing.OutCubic }
            NumberAnimation { target: shift; property: "y"; to: 0; duration: 260; easing.type: Easing.OutCubic }
        }
    }

    SequentialAnimation {
        id: closeAnim

        ParallelAnimation {
            NumberAnimation { target: frame; property: "opacity"; to: 0; duration: 150; easing.type: Easing.InCubic }
            NumberAnimation { target: frame; property: "scale"; to: 0.95; duration: 150; easing.type: Easing.InCubic }
            NumberAnimation { target: shift; property: "y"; to: 14; duration: 150; easing.type: Easing.InCubic }
        }

        ScriptAction {
            script: rows.clear()
        }
    }

    //--------------------- UI ------------------------

    Rectangle {
        id: frame
        anchors.fill: parent
        color: theme.bg_panel
        radius: 8
        border.color: theme.border_panel
        border.width: 3
        opacity: 0
        scale: 0.95
        transformOrigin: Item.BottomLeft

        transform: Translate {
            id: shift
            y: 14
        }

        Behavior on color {
            ColorAnimation { duration: 300 }
        }

        //--------------------- HEADER ------------------------

        Column {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 12
            spacing: 10

            Item {
                width: parent.width
                height: 36

                Rectangle {
                    id: search
                    anchors.left: parent.left
                    anchors.right: addButton.left
                    anchors.rightMargin: 8
                    height: parent.height
                    radius: 10
                    color: theme.surface
                    border.width: 1
                    border.color: panel.typing && !panel.noteOpen ? theme.accent_primary : "transparent"

                    Behavior on border.color {
                        ColorAnimation { duration: 150 }
                    }

                    Glyph {
                        id: searchIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        size: 16
                        path: panel.icons.search
                        tint: panel.typing && !panel.noteOpen ? theme.accent_primary : theme.text_dim
                    }

                    TextInput {
                        id: input
                        anchors.left: searchIcon.right
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        color: theme.text_main
                        selectionColor: theme.selection
                        selectedTextColor: theme.text_main
                        font.pixelSize: 14
                        clip: true
                        focus: true

                        onTextChanged: Qt.callLater(panel.rebuild)

                        Keys.onUpPressed: panel.moveSelection(-1)
                        Keys.onDownPressed: panel.moveSelection(1)
                        Keys.onReturnPressed: panel.activate(panel.selectedItem())
                        Keys.onEnterPressed: panel.activate(panel.selectedItem())

                        Keys.onEscapePressed: {
                            if (text.length > 0) text = ""
                            else panel.hide()
                        }

                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier)) {
                                panel.togglePin(panel.selectedItem())
                                event.accepted = true
                            } else if (event.key === Qt.Key_Delete && input.text.length === 0) {
                                panel.deleteItem(panel.selectedItem())
                                event.accepted = true
                            }
                        }

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: "Поиск"
                            color: theme.text_dim
                            font: input.font
                            visible: input.text.length === 0
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !panel.typing || panel.noteOpen
                        cursorShape: Qt.IBeamCursor
                        onClicked: {
                            if (panel.noteOpen) panel.closeNote()
                            panel.startTyping()
                        }
                    }
                }

                Rectangle {
                    id: addButton
                    anchors.right: parent.right
                    width: 36
                    height: 36
                    radius: 10
                    color: "transparent"
                    border.width: 1
                    border.color: panel.noteOpen || addMouse.containsMouse ? theme.accent_primary : Qt.rgba(1, 1, 1, 0.12)

                    Behavior on border.color {
                        ColorAnimation { duration: 150 }
                    }

                    Glyph {
                        anchors.centerIn: parent
                        size: 18
                        path: panel.icons.plus
                        tint: panel.noteOpen || addMouse.containsMouse ? theme.accent_primary : theme.text_main
                        rotation: panel.noteOpen ? 45 : 0

                        Behavior on rotation {
                            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                        }
                    }

                    MouseArea {
                        id: addMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.noteOpen ? panel.closeNote() : panel.openNote()
                    }
                }
            }

            //--------------------- NOTE ------------------------

            Item {
                id: noteArea
                width: parent.width
                height: panel.noteOpen ? noteColumn.implicitHeight : 0
                opacity: panel.noteOpen ? 1 : 0
                visible: panel.noteOpen || height > 0
                clip: true

                Behavior on height {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }

                Behavior on opacity {
                    NumberAnimation { duration: 180 }
                }

                Column {
                    id: noteColumn
                    width: parent.width
                    spacing: 10

                    Rectangle {
                        id: noteBox
                        width: parent.width
                        height: 76
                        radius: 10
                        color: theme.surface
                        border.width: 1
                        border.color: theme.accent_primary

                        TextEdit {
                            id: noteInput
                            anchors.fill: parent
                            anchors.margins: 10
                            wrapMode: TextEdit.Wrap
                            color: theme.text_main
                            selectionColor: theme.selection
                            selectedTextColor: theme.text_main
                            font.pixelSize: 13
                            clip: true

                            Keys.onEscapePressed: {
                                panel.closeNote()
                                panel.startTyping()
                            }

                            Keys.onPressed: (event) => {
                                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
                                    panel.saveNote()
                                    event.accepted = true
                                }
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                text: "Запишите чтото чтобы сохранить"
                                color: theme.text_dim
                                font: noteInput.font
                                visible: noteInput.text.length === 0
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: 28

                        Row {
                            id: noteButtons
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Rectangle {
                                width: cancelLabel.implicitWidth + 24
                                height: 28
                                radius: 8
                                color: "transparent"
                                border.width: 1
                                border.color: cancelMouse.containsMouse ? theme.text_dim : Qt.rgba(1, 1, 1, 0.12)

                                Text {
                                    id: cancelLabel
                                    anchors.centerIn: parent
                                    text: "Отменить"
                                    color: theme.text_main
                                    font.pixelSize: 12
                                }

                                MouseArea {
                                    id: cancelMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: panel.closeNote()
                                }
                            }

                            Rectangle {
                                width: saveLabel.implicitWidth + 24
                                height: 28
                                radius: 8
                                color: theme.accent_primary
                                opacity: saveMouse.containsMouse ? 0.85 : 1

                                Text {
                                    id: saveLabel
                                    anchors.centerIn: parent
                                    text: "Закрепить"
                                    color: theme.bg_panel
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                }

                                MouseArea {
                                    id: saveMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: panel.saveNote()
                                }
                            }
                        }
                    }
                }
            }

            //--------------------- CHIPS ------------------------

            Item {
                id: chips

                readonly property real chipWidth: (width - 4 * (panel.categories.length - 1)) / panel.categories.length
                readonly property int activeIndex: panel.categories.findIndex(c => c.key === panel.category)

                width: parent.width
                height: 26

                Rectangle {
                    x: chips.activeIndex * (chips.chipWidth + 4)
                    width: chips.chipWidth
                    height: parent.height
                    radius: height / 2
                    color: theme.chip_active_bg

                    Behavior on x {
                        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                    }
                }

                Row {
                    anchors.fill: parent
                    spacing: 4

                    Repeater {
                        model: panel.categories

                        delegate: Item {
                            id: chip

                            required property var modelData
                            readonly property bool active: panel.category === modelData.key

                            width: chips.chipWidth
                            height: chips.height

                            Text {
                                anchors.centerIn: parent
                                text: chip.modelData.label
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                color: chip.active ? theme.chip_active_text : (chipMouse.containsMouse ? theme.text_main : theme.text_dim)
                                scale: chipMouse.pressed ? 0.94 : 1

                                Behavior on color {
                                    ColorAnimation { duration: 160 }
                                }

                                Behavior on scale {
                                    NumberAnimation { duration: 100 }
                                }
                            }

                            MouseArea {
                                id: chipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panel.category = chip.modelData.key
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: divider
            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 10
            anchors.leftMargin: 3
            anchors.rightMargin: 3
            height: 1
            color: Qt.rgba(1, 1, 1, 0.08)
        }

        //--------------------- LIST ------------------------

        ListView {
            id: listView
            anchors.top: divider.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.topMargin: 4
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.bottomMargin: 8
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: rows

            add: Transition {
                id: addTransition

                SequentialAnimation {
                    PropertyAction { property: "opacity"; value: 0 }
                    PauseAnimation { duration: Math.min(addTransition.ViewTransition.index, 12) * 18 }

                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "x"; from: -14; to: 0; duration: 240; easing.type: Easing.OutCubic }
                    }
                }
            }

            remove: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; to: 0; duration: 140; easing.type: Easing.InCubic }
                    NumberAnimation { property: "x"; to: 14; duration: 140; easing.type: Easing.InCubic }
                }
            }

            move: Transition {
                NumberAnimation { property: "y"; duration: 200; easing.type: Easing.OutCubic }
            }

            displaced: Transition {
                NumberAnimation { property: "y"; duration: 200; easing.type: Easing.OutCubic }
                NumberAnimation { property: "opacity"; to: 1; duration: 120 }
                NumberAnimation { property: "x"; to: 0; duration: 120 }
            }

            delegate: Item {
                id: cell

                required property string key
                required property string kind
                required property string label

                readonly property bool isHeader: kind === "header"
                readonly property bool isPin: kind === "pin"
                readonly property var item: panel.lookup[key] ?? null
                readonly property var entry: item ? item.entry : null
                readonly property bool selected: !isHeader && panel.selectedKey === key
                readonly property real age: entry && entry.firstSeen ? panel.now - entry.firstSeen : 0
                readonly property real life: Math.max(0.04, 1 - age / panel.service.maxAgeMs)
                readonly property var info: entry ? panel.describe(entry) : ({ title: "", meta: "" })
                readonly property string thumb: {
                    if (!entry || entry.type !== "image") return ""
                    if (isPin) return entry.file ?? ""
                    return panel.service.thumbs[entry.text] ?? ""
                }

                width: listView.width
                height: isHeader ? 28 : 46

                Text {
                    visible: cell.isHeader
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 5
                    text: cell.label
                    color: theme.text_dim
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                Rectangle {
                    id: row

                    readonly property var uris: cell.entry ? panel.dragUris(cell.entry, cell.isPin) : []
                    readonly property bool draggable: row.uris.length > 0
                    readonly property bool lifted: rowDrag.active
                    property url dragImage: ""

                    visible: !cell.isHeader
                    anchors.fill: parent
                    anchors.topMargin: 1
                    anchors.bottomMargin: 1
                    radius: 8
                    color: cell.selected ? theme.item_hover : "transparent"
                    border.width: row.lifted ? 1 : 0
                    border.color: theme.accent_primary
                    opacity: row.lifted ? 0.45 : 1
                    scale: rowTap.pressed ? 0.98 : 1

                    Behavior on color {
                        ColorAnimation { duration: 140 }
                    }

                    Behavior on opacity {
                        NumberAnimation { duration: 120 }
                    }

                    Behavior on scale {
                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: theme.accent_primary
                        opacity: 0

                        NumberAnimation on opacity {
                            id: flashAnim
                            running: false
                            from: 0.3
                            to: 0
                            duration: 480
                            easing.type: Easing.OutCubic
                        }
                    }

                    Connections {
                        target: panel

                        function onFlashed(key) {
                            if (key === cell.key) flashAnim.restart()
                        }
                    }

                    Drag.dragType: Drag.Automatic
                    Drag.supportedActions: Qt.CopyAction
                    Drag.mimeData: ({ "text/uri-list": row.uris.join("\r\n") })
                    Drag.imageSource: row.dragImage
                    Drag.hotSpot.x: rowDrag.centroid.pressPosition.x
                    Drag.hotSpot.y: rowDrag.centroid.pressPosition.y
                    Drag.active: rowDrag.active && row.draggable

                    DragHandler {
                        id: rowDrag
                        target: null
                        enabled: row.draggable
                        onActiveChanged: panel.draggingOut = rowDrag.active
                    }

                    HoverHandler {
                        id: rowHover
                        cursorShape: row.draggable ? Qt.OpenHandCursor : Qt.PointingHandCursor

                        onHoveredChanged: {
                            if (!rowHover.hovered) return
                            panel.selectedKey = cell.key
                            if (row.draggable) row.grabToImage(result => row.dragImage = result.url)
                        }
                    }

                    TapHandler {
                        id: rowTap
                        onTapped: panel.activate(cell.item)
                    }

                    Grid {
                        opacity: row.draggable && cell.selected ? 1 : 0
                        visible: opacity > 0
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        columns: 2
                        spacing: 2

                        Repeater {
                            model: 6

                            Rectangle {
                                width: 3
                                height: 3
                                radius: 1.5
                                color: theme.text_dim
                            }
                        }

                        Behavior on opacity {
                            NumberAnimation { duration: 140 }
                        }
                    }

                    Rectangle {
                        visible: !cell.isPin
                        opacity: row.draggable && cell.selected ? 0 : 1
                        anchors.left: parent.left
                        anchors.leftMargin: 5
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.topMargin: 10
                        anchors.bottomMargin: 10
                        width: 3
                        radius: 1.5
                        color: Qt.rgba(1, 1, 1, 0.06)

                        Behavior on opacity {
                            NumberAnimation { duration: 140 }
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: parent.height * cell.life
                            radius: 1.5
                            color: theme.accent_primary
                            opacity: 0.25 + cell.life * 0.75

                            Behavior on height {
                                NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
                            }
                        }
                    }

                    Glyph {
                        visible: cell.isPin
                        opacity: row.draggable && cell.selected ? 0 : 1
                        anchors.left: parent.left
                        anchors.leftMargin: 2
                        anchors.verticalCenter: parent.verticalCenter
                        size: 10
                        path: panel.icons.flake
                        tint: theme.accent_primary
                    }

                    Item {
                        id: lead
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44
                        height: 32

                        Rectangle {
                            anchors.centerIn: parent
                            width: 30
                            height: 30
                            radius: 8
                            color: Qt.rgba(1, 1, 1, 0.045)
                            visible: thumbImage.status !== Image.Ready

                            Glyph {
                                anchors.centerIn: parent
                                size: 16
                                path: panel.icons[cell.entry ? cell.entry.type : "text"] ?? panel.icons.text
                                tint: theme.text_dim
                            }
                        }

                        Image {
                            id: thumbImage
                            anchors.fill: parent
                            source: cell.thumb.length > 0 ? "file://" + cell.thumb : ""
                            sourceSize.width: 88
                            sourceSize.height: 64
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                            opacity: status === Image.Ready ? 1 : 0

                            Behavior on opacity {
                                NumberAnimation { duration: 200 }
                            }
                        }
                    }

                    Column {
                        anchors.left: lead.right
                        anchors.leftMargin: 10
                        anchors.right: side.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: cell.info.title
                            color: theme.text_main
                            font.pixelSize: 13
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        Text {
                            width: parent.width
                            text: cell.info.meta
                            visible: cell.info.meta.length > 0
                            color: theme.text_dim
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }

                    Item {
                        id: side
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 56
                        height: 26

                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 2
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !cell.isPin && opacity > 0
                            opacity: cell.selected ? 0 : 1
                            text: panel.ageText(cell.age)
                            color: theme.text_dim
                            font.pixelSize: 11

                            Behavior on opacity {
                                NumberAnimation { duration: 120 }
                            }
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            opacity: cell.selected ? 1 : 0
                            visible: opacity > 0

                            Behavior on opacity {
                                NumberAnimation { duration: 120 }
                            }

                            IconButton {
                                icon: panel.icons.flake
                                tint: cell.isPin ? theme.accent_primary : theme.text_dim
                                hoverTint: theme.accent_primary
                                onClicked: panel.togglePin(cell.item)
                            }

                            IconButton {
                                icon: panel.icons.x
                                tint: theme.text_dim
                                hoverTint: theme.danger
                                onClicked: panel.deleteItem(cell.item)
                            }
                        }
                    }
                }
            }
        }

        //--------------------- EMPTY ------------------------

        Text {
            anchors.centerIn: listView
            width: listView.width - 48
            opacity: panel.items.length === 0 ? 1 : 0
            visible: opacity > 0
            text: panel.emptyText()
            color: theme.text_dim
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap

            Behavior on opacity {
                NumberAnimation { duration: 200 }
            }
        }

        //--------------------- DRAG HINT ------------------------

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 12
            anchors.bottomMargin: panel.draggingOut ? 12 : 0
            height: 36
            radius: 10
            color: theme.accent_primary
            opacity: panel.draggingOut ? 1 : 0
            visible: opacity > 0

            Behavior on anchors.bottomMargin {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }

            Behavior on opacity {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }

            Row {
                anchors.centerIn: parent
                spacing: 8

                Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 16
                    path: panel.icons.drop
                    tint: theme.bg_panel
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Drop into any app"
                    color: theme.bg_panel
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
            }
        }

        //--------------------- CLICK FOCUS ------------------------

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton

            onPressed: (mouse) => {
                mouse.accepted = false
                const point = mapToItem(listView.contentItem, mouse.x, mouse.y)
                const cell = listView.itemAt(point.x, point.y)
                const onRow = cell !== null && cell.isHeader === false && listView.contains(mapToItem(listView, mouse.x, mouse.y))
                if (!onRow) panel.focusPanel()
            }
        }

        //--------------------- DROP ------------------------

        DropArea {
            id: dropZone
            anchors.fill: parent
            enabled: !panel.draggingOut

            onDropped: (drop) => {
                if (!drop.hasUrls) return
                const uris = []
                for (let i = 0; i < drop.urls.length; i++) uris.push(drop.urls[i].toString())
                panel.service.copyFiles(uris)
                drop.accept(Qt.CopyAction)
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 8
            radius: 6
            opacity: dropZone.containsDrag ? 1 : 0
            visible: opacity > 0
            color: theme.bg_panel
            border.width: 2
            border.color: theme.accent_primary

            Behavior on opacity {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            Column {
                anchors.centerIn: parent
                width: parent.width - 48
                spacing: 8

                Glyph {
                    anchors.horizontalCenter: parent.horizontalCenter
                    size: 40
                    path: panel.icons.flake
                    tint: theme.accent_primary

                    SequentialAnimation on scale {
                        running: dropZone.containsDrag
                        loops: Animation.Infinite

                        NumberAnimation { to: 1.12; duration: 600; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
                    }

                    RotationAnimation on rotation {
                        running: dropZone.containsDrag
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 6000
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Перетащите чтобы скопировать"
                    color: theme.text_main
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }

                Text {
                    width: parent.width
                    text: "Файл будет скопирован в буфер обмена и отобразится в истории."
                    color: theme.text_dim
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
