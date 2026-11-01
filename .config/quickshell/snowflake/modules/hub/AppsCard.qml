import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import Quickshell.Io

ColumnLayout {
    id: root

    // ------------------------- STATE -------------------------
    required property var hub

    spacing: 8

    property var windows: []
    readonly property int count: root.windows.length
    property string lastJson: ""

    // ------------------------- HYPRLAND CLIENTS -------------------------
    Process {
        id: clientsProc
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: root.apply(text)
        }
    }

    function apply(text) {
        let list = []
        try {
            const parsed = JSON.parse(text)
            if (Array.isArray(parsed)) list = parsed
        } catch (e) {
            list = []
        }

        const wins = list.filter(w => w.mapped !== false).map(w => {
            const ws = w.workspace || {}
            const wsId = ws.id !== undefined ? ws.id : 0
            return {
                address: w.address,
                title: w.title && w.title.length > 0 ? w.title : (w.class || "?"),
                cls: w.class || "",
                wsId: wsId,
                wsName: ws.name || String(wsId),
                wsLabel: wsId > 0 ? String(wsId) : "S",
                focused: w.focusHistoryID === 0,
                floating: !!w.floating
            }
        }).sort((a, b) => {
            const wa = a.wsId > 0 ? a.wsId : 1000
            const wb = b.wsId > 0 ? b.wsId : 1000
            return (wa - wb) || (a.wsId - b.wsId) || a.cls.localeCompare(b.cls)
        })

        const json = JSON.stringify(wins)
        if (json === root.lastJson) return
        root.lastJson = json
        root.windows = wins
        root.syncModel()
    }

    function refresh() {
        if (!clientsProc.running)
            clientsProc.running = true
    }

    function focusWindow(address) {
        Hyprland.dispatch("focuswindow address:" + address)
        refreshSoon.restart()
    }

    function closeWindow(address) {
        Hyprland.dispatch("closewindow address:" + address)
        refreshSoon.restart()
    }

    function goToWorkspace(wsId, wsName) {
        if (wsId > 0) {
            Hyprland.dispatch("workspace " + wsId)
        } else {
            const name = wsName.startsWith("special:") ? wsName.slice(8) : ""
            Hyprland.dispatch("togglespecialworkspace" + (name ? " " + name : ""))
        }
        refreshSoon.restart()
    }

    function wsTitle(wsId, wsName) {
        if (wsId > 0)
            return "Рабочий стол " + wsId + (wsName && wsName !== String(wsId) ? " · " + wsName : "")
        const name = wsName.startsWith("special:") ? wsName.slice(8) : ""
        return "Скрытый стол" + (name && name !== "special" ? " · " + name : "")
    }

    function plural(n, one, few, many) {
        const m10 = n % 10, m100 = n % 100
        if (m10 === 1 && m100 !== 11) return one
        if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few
        return many
    }

    // ------------------------- FLAT MODEL -------------------------
    ListModel { id: rowsModel }

    function row(kind, w, n, active) {
        return {
            kind: kind,
            address: w.address,
            title: w.title,
            cls: w.cls,
            wsId: w.wsId,
            wsName: w.wsName,
            focused: active,
            winCount: n,
            floating: w.floating
        }
    }

    function syncModel() {
        const wins = root.windows
        const rows = []
        let i = 0
        while (i < wins.length) {
            let j = i
            let active = false
            while (j < wins.length && wins[j].wsId === wins[i].wsId) {
                if (wins[j].focused) active = true
                j++
            }
            rows.push(root.row("ws", wins[i], j - i, active))
            for (let k = i; k < j; k++)
                rows.push(root.row("win", wins[k], 0, wins[k].focused))
            i = j
        }

        for (let r = 0; r < rows.length; r++) {
            if (r < rowsModel.count) rowsModel.set(r, rows[r])
            else rowsModel.append(rows[r])
        }
        if (rowsModel.count > rows.length)
            rowsModel.remove(rows.length, rowsModel.count - rows.length)
    }

    Timer {
        id: refreshSoon
        interval: 150
        onTriggered: root.refresh()
    }

    Timer {
        interval: 3000
        running: root.hub.expanded
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Connections {
        target: Hyprland
        enabled: root.hub.expanded
        function onRawEvent(event) {
            const n = event.name
            if (n === "openwindow" || n === "closewindow" || n === "windowtitle" || n === "windowtitlev2"
                || n === "activewindowv2" || n === "movewindow" || n === "movewindowv2" || n === "changefloatingmode")
                refreshSoon.restart()
        }
    }

    // ------------------------- REVEAL ANIMATION -------------------------
    readonly property bool shown: root.hub.expanded && root.hub.currentPage === 1
    property real reveal: 1
    onShownChanged: if (root.shown) revealAnim.restart()

    NumberAnimation {
        id: revealAnim
        target: root
        property: "reveal"
        from: 0
        to: 1
        duration: 800
        easing.type: Easing.OutCubic
    }

    function appearAt(frac) {
        return Math.max(0, Math.min(1, (root.reveal - frac * 0.45) / 0.55))
    }

    // ------------------------- LIST -------------------------
    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 150
        visible: root.count > 0
        clip: true
        spacing: 6
        boundsBehavior: Flickable.StopAtBounds
        model: rowsModel

        SmoothScroll { flick: list }

        delegate: Item {
            id: item
            required property int index
            required property string kind
            required property string address
            required property string title
            required property string cls
            required property int wsId
            required property string wsName
            required property bool focused
            required property int winCount
            required property bool floating

            readonly property bool isHeader: item.kind === "ws"
            readonly property real appear: root.appearAt(Math.min(item.index, 10) / 10)

            width: list.width
            height: item.isHeader ? (item.index === 0 ? 24 : 34) : 50
            opacity: item.appear
            transform: Translate { x: (1 - item.appear) * 18 }

            // ------------------------- WORKSPACE HEADER -------------------------
            Item {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 24
                visible: item.isHeader

                HoverHandler { id: wsHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.goToWorkspace(item.wsId, item.wsName) }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 4
                    anchors.rightMargin: 4
                    spacing: 8

                    Rectangle {
                        implicitWidth: 8
                        implicitHeight: 8
                        radius: 4
                        color: item.focused ? root.hub.accentPrimary : root.hub.textDim
                        opacity: item.focused ? 1 : 0.4
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.wsTitle(item.wsId, item.wsName)
                        color: wsHover.hovered || item.focused ? root.hub.textMain : root.hub.textDim
                        font.pixelSize: 13
                        font.bold: true
                        elide: Text.ElideRight

                        Behavior on color { ColorAnimation { duration: 140 } }
                    }

                    Text {
                        text: item.winCount + " " + root.plural(item.winCount, "окно", "окна", "окон")
                        color: root.hub.textDim
                        font.pixelSize: 12
                    }
                }
            }

            // ------------------------- WINDOW -------------------------
            Rectangle {
                id: card
                anchors.fill: parent
                visible: !item.isHeader
                radius: 10
                color: item.focused ? root.hub.workspaceActive
                     : rowHover.hovered ? root.hub.accentSecondary : root.hub.bgTrack
                scale: rowArea.pressed ? 0.98 : 1.0

                Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }

                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    onClicked: function(mouse) {
                        if (mouse.button === Qt.MiddleButton) root.closeWindow(item.address)
                        else root.focusWindow(item.address)
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 12

                    AppIcon {
                        id: winIcon
                        hub: root.hub
                        appClass: item.cls
                        size: 30
                        highlighted: item.focused
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            Layout.fillWidth: true
                            text: item.title
                            color: item.focused ? root.hub.onWorkspaceActive : root.hub.textMain
                            font.pixelSize: 14
                            font.bold: item.focused
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            readonly property string name: winIcon.appName !== item.title ? winIcon.appName : ""
                            visible: text !== ""
                            text: [name, item.floating ? "плавающее" : ""].filter(s => s !== "").join(" · ")
                            color: item.focused ? Qt.rgba(root.hub.onWorkspaceActive.r, root.hub.onWorkspaceActive.g, root.hub.onWorkspaceActive.b, 0.7)
                                                : root.hub.textDim
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        implicitWidth: 26
                        implicitHeight: 26
                        radius: 7
                        opacity: rowHover.hovered ? 1 : 0
                        color: closeArea.containsMouse ? root.hub.danger : Qt.rgba(0, 0, 0, 0.18)
                        scale: closeArea.pressed ? 0.9 : 1.0

                        Behavior on opacity { NumberAnimation { duration: 140 } }
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on scale { NumberAnimation { duration: 100 } }

                        Text {
                            anchors.centerIn: parent
                            text: "󰅖"
                            font.family: root.hub.iconFont
                            font.pixelSize: 14
                            color: closeArea.containsMouse ? root.hub.bgPanel
                                 : item.focused ? root.hub.onWorkspaceActive : root.hub.textMain
                        }

                        MouseArea {
                            id: closeArea
                            anchors.fill: parent
                            enabled: parent.opacity > 0.5
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.closeWindow(item.address)
                        }
                    }
                }
            }
        }
    }

    // ------------------------- EMPTY STATE -------------------------
    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: 24
        visible: root.count === 0
        spacing: 8

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "󰖲"
            font.family: root.hub.iconFont
            font.pixelSize: 36
            color: root.hub.textDim
            opacity: 0.5
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Нет открытых окон"
            color: root.hub.textDim
            font.pixelSize: 14
        }
    }

    Item {
        Layout.fillHeight: true
        visible: root.count === 0
    }
}
