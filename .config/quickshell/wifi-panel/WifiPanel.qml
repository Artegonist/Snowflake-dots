import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

PanelWindow {
    id: root

    visible: false
    focusable: true
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    property bool expanded: false
    property bool closing: false

    function show() {
        root.closing = false
        if (!root.visible)
            root.visible = true
        focusGrab.active = true
        root.mask = null
        root.expanded = true
        root.refreshAll()
        Qt.callLater(function() { card.forceActiveFocus() })
    }

    function hide() {
        if (!root.expanded || root.closing)
            return
        root.closing = true
        focusGrab.active = false
        root.mask = emptyRegion
        root.expanded = false
        root.cancelPassword()
    }

    function toggle() {
        if (root.expanded && !root.closing)
            hide()
        else
            show()
    }

    Region {
        id: emptyRegion
        x: 0
        y: 0
        width: 0
        height: 0
    }

    anchors {
        top: true
        right: true
    }

    margins {
        top: 30
        right: 53
    }

    exclusionMode: ExclusionMode.Ignore

    color: "transparent"
    implicitWidth: 380
    implicitHeight: 540

    readonly property color accentPrimary:   "#d71921"
    readonly property color accentSecondary: "#a3141a"
    readonly property color bgPanelWaybar:   "#0a0a0a"
    readonly property color bgPanel:         "#0c0c0c"
    readonly property color bgTrack:         "#1a1a1a"
    readonly property color bgInput:         "#141414"
    readonly property color textMain:        "#f5f5f5"
    readonly property color textDim:         "#8a8a8a"
    readonly property color textWaybar:      "#eaeaea"
    readonly property color workspaceActive: "#d71921"
    readonly property color hoverLight:      "#2a2a2a"
    readonly property color hoverSelect:     "#3a1114"
    readonly property color inputTextColor:  "#f5f5f5"
    readonly property color accentText:      "#d71921"

    readonly property color borderColor: accentPrimary
    readonly property color separatorColor: Qt.rgba(1, 1, 1, 0.08)

    property bool wifiEnabled: true
    property bool scanning: false
    property bool busy: false
    property string ipAddress: "—"
    property string activeSsid: ""
    property string activeIface: ""
    property var networks: []
    readonly property var availableNetworks: root.networks.filter(function(n) { return n.ssid !== root.activeSsid })
    property var knownConnections: []
    property string connectingSsid: ""
    property string errorText: ""
    property bool lastAttemptWasKnownSecure: false

    property bool passwordPromptVisible: false
    property string pendingSsid: ""

    function refreshAll() {
        root.refreshRadioState()
        root.refreshActiveConnection()
        root.refreshIp()
        root.refreshKnownConnections()
    }

    function refreshRadioState() { radioStateProc.running = true }
    function refreshActiveConnection() { activeConnProc.running = true }
    function refreshIp() { ipProc.running = true }
    function refreshKnownConnections() { knownConnProc.running = true }

    function scanNetworks() {
        if (!root.wifiEnabled)
            return
        root.scanning = true
        root.errorText = ""
        scanProc.running = true
    }

    function toggleRadio() {
        radioToggleProc.command = ["nmcli", "radio", "wifi", root.wifiEnabled ? "off" : "on"]
        radioToggleProc.running = true
    }

    function connectTo(ssid, secure, known) {
        if (root.busy)
            return
        if (secure && !known) {
            root.pendingSsid = ssid
            root.passwordPromptVisible = true
            passwordField.forceActiveFocus()
            return
        }
        root.busy = true
        root.errorText = ""
        root.connectingSsid = ssid
        root.lastAttemptWasKnownSecure = secure && known
        connectProc.command = ["nmcli", "device", "wifi", "connect", ssid]
        connectProc.running = true
    }

    function connectWithPassword() {
        if (passwordField.text.length === 0)
            return
        root.busy = true
        root.errorText = ""
        root.connectingSsid = root.pendingSsid
        root.lastAttemptWasKnownSecure = false
        connectProc.command = ["nmcli", "device", "wifi", "connect", root.pendingSsid, "password", passwordField.text]
        connectProc.running = true
        root.passwordPromptVisible = false
        passwordField.text = ""
        card.forceActiveFocus()
    }

    function cancelPassword() {
        root.passwordPromptVisible = false
        root.pendingSsid = ""
        passwordField.text = ""
        card.forceActiveFocus()
    }

    function disconnectActive() {
        if (root.activeIface === "" || root.busy)
            return
        root.busy = true
        disconnectProc.command = ["nmcli", "device", "disconnect", root.activeIface]
        disconnectProc.running = true
    }

    function forgetActive() {
        if (root.activeSsid === "" || root.busy)
            return
        root.busy = true
        forgetProc.command = ["nmcli", "connection", "delete", root.activeSsid]
        forgetProc.running = true
    }

    function splitEscaped(line) {
        const result = []
        let current = ""
        for (let i = 0; i < line.length; i++) {
            if (line.charCodeAt(i) === 92 && i + 1 < line.length) {
                current += line[i + 1]
                i++
            } else if (line[i] === ":") {
                result.push(current)
                current = ""
            } else {
                current += line[i]
            }
        }
        result.push(current)
        return result
    }

    function parseNetworks(text) {
        const lines = text.split("\n").filter(l => l.length > 0)
        const indexBySsid = {}
        const list = []
        for (const line of lines) {
            const parts = root.splitEscaped(line)
            if (parts.length < 4)
                continue
            const active = parts[0] === "yes"
            const ssid = parts[1]
            const signal = parseInt(parts[2]) || 0
            const security = parts[3]
            if (!ssid)
                continue
            if (indexBySsid[ssid] !== undefined) {
                if (active)
                    list[indexBySsid[ssid]].active = true
                continue
            }
            indexBySsid[ssid] = list.length
            list.push({ ssid: ssid, signal: signal, secure: security.length > 0, active: active })
        }
        list.sort((a, b) => {
            if (a.active !== b.active)
                return a.active ? -1 : 1
            return b.signal - a.signal
        })
        return list
    }

    function parseKnownConnections(text) {
        const lines = text.split("\n").filter(l => l.length > 0)
        const names = []
        for (const line of lines) {
            const parts = root.splitEscaped(line)
            if (parts.length < 2)
                continue
            if (parts[1] === "802-11-wireless")
                names.push(parts[0])
        }
        return names
    }

    function wifiIcon(signal) {
        if (signal >= 75) return "󰤨"
        if (signal >= 50) return "󰤥"
        if (signal >= 25) return "󰤢"
        return "󰤟"
    }

    Process {
        id: radioStateProc
        command: ["nmcli", "-t", "-f", "WIFI", "radio"]
        stdout: StdioCollector {
            onStreamFinished: root.wifiEnabled = text.trim() === "enabled"
        }
    }

    Process {
        id: radioToggleProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.refreshRadioState()
                if (root.wifiEnabled)
                    root.scanNetworks()
                else
                    root.networks = []
            }
        }
    }

    Process {
        id: activeConnProc
        command: ["sh", "-c", "nmcli -t -f TYPE,DEVICE,STATE,CONNECTION device status | grep '^wifi'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const line = text.trim()
                if (line.length === 0) {
                    root.activeSsid = ""
                    root.activeIface = ""
                    return
                }
                const parts = root.splitEscaped(line.split("\n")[0])
                if (parts[2] === "connected") {
                    root.activeIface = parts[1]
                    root.activeSsid = parts[3]
                } else {
                    root.activeSsid = ""
                    root.activeIface = ""
                }
            }
        }
    }

    Process {
        id: ipProc
        command: ["sh", "-c", "hostname -I 2>/dev/null | awk '{print $1}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const ip = text.trim()
                root.ipAddress = ip.length > 0 ? ip : "—"
            }
        }
    }

    Process {
        id: knownConnProc
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.knownConnections = root.parseKnownConnections(text)
                root.scanNetworks()
            }
        }
    }

    Process {
        id: scanProc
        command: ["nmcli", "-t", "-f", "active,ssid,signal,security", "device", "wifi", "list", "--rescan", "yes"]
        stdout: StdioCollector {
            onStreamFinished: {
                const known = root.knownConnections
                const list = root.parseNetworks(text)
                for (const n of list) {
                    n.known = known.indexOf(n.ssid) !== -1
                    n.active = n.ssid === root.activeSsid
                }
                root.networks = list
                root.scanning = false
            }
        }
    }

    Process {
        id: connectProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false
                const failed = text.toLowerCase().indexOf("error") !== -1
                const retrySsid = root.connectingSsid
                root.errorText = failed ? "Не удалось подключиться к сети" : ""
                root.connectingSsid = ""
                if (failed && root.lastAttemptWasKnownSecure) {
                    root.pendingSsid = retrySsid
                    root.passwordPromptVisible = true
                    passwordField.forceActiveFocus()
                }
                root.lastAttemptWasKnownSecure = false
                root.refreshActiveConnection()
                root.refreshIp()
                root.refreshKnownConnections()
            }
        }
    }

    Process {
        id: disconnectProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false
                root.refreshActiveConnection()
                root.refreshIp()
                root.refreshKnownConnections()
            }
        }
    }

    Process {
        id: forgetProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false
                root.refreshActiveConnection()
                root.refreshIp()
                root.refreshKnownConnections()
            }
        }
    }

    Component.onCompleted: {
        root.refreshRadioState()
        root.refreshActiveConnection()
        root.refreshIp()
        root.refreshKnownConnections()
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: {
            root.refreshRadioState()
            root.refreshActiveConnection()
            root.refreshIp()
        }
    }

    Timer {
        interval: 5000
        running: root.expanded
        repeat: true
        onTriggered: {
            root.refreshActiveConnection()
            root.refreshIp()
        }
    }

    Timer {
        interval: 15000
        running: root.expanded
        repeat: true
        onTriggered: root.scanNetworks()
    }

    HyprlandFocusGrab {
        id: focusGrab
        windows: [root]
        onCleared: root.hide()
    }

    onVisibleChanged: {
        if (visible && !root.expanded)
            root.expanded = true
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 8
        color: root.bgPanel
        border.width: 3
        border.color: root.borderColor

        transformOrigin: Item.Top

        opacity: 0
        scale: 0.85

        focus: true
        Keys.onEscapePressed: root.hide()

        SequentialAnimation {
            id: openAnim

            ScriptAction {
                script: {
                    topSection.opacity = 0
                    topSectionTranslate.y = -12
                    networkList.opacity = 0
                    networkListTranslate.y = -12
                }
            }

            ParallelAnimation {
                NumberAnimation { target: card; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
                NumberAnimation { target: card; property: "scale"; to: 1; duration: 190; easing.type: Easing.OutBack; easing.overshoot: 1.1 }

                SequentialAnimation {
                    PauseAnimation { duration: 35 }
                    ParallelAnimation {
                        NumberAnimation { target: topSection; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
                        NumberAnimation { target: topSectionTranslate; property: "y"; to: 0; duration: 170; easing.type: Easing.OutCubic }
                    }
                }

                SequentialAnimation {
                    PauseAnimation { duration: 70 }
                    ParallelAnimation {
                        NumberAnimation { target: networkList; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
                        NumberAnimation { target: networkListTranslate; property: "y"; to: 0; duration: 170; easing.type: Easing.OutCubic }
                    }
                }
            }
        }

        SequentialAnimation {
            id: closeAnim
            ParallelAnimation {
                NumberAnimation { target: card; property: "opacity"; to: 0; duration: 110; easing.type: Easing.InCubic }
                NumberAnimation { target: card; property: "scale"; to: 0.85; duration: 110; easing.type: Easing.InCubic }
            }
            ScriptAction {
                script: root.closing = false
            }
        }

        Connections {
            target: root
            function onExpandedChanged() {
                closeAnim.stop()
                openAnim.stop()
                if (root.expanded)
                    openAnim.start()
                else
                    closeAnim.start()
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 14
            visible: root.wifiEnabled

            ColumnLayout {
                id: topSection
                Layout.fillWidth: true
                spacing: 14
                opacity: 0

                transform: Translate {
                    id: topSectionTranslate
                    y: -12
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        text: root.wifiEnabled ? "󰖩" : "󰖪"
                        font.pixelSize: 20
                        color: root.accentPrimary
                    }

                    Text {
                        text: root.wifiEnabled ? (root.activeSsid !== "" ? root.activeSsid : "Wi-Fi") : "Wi-Fi выключен"
                        color: root.textMain
                        font.pixelSize: 18
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Layout.maximumWidth: 170
                    }

                    Item { Layout.fillWidth: true }

                    Item {
                        width: 44
                        height: 24
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    visible: root.wifiEnabled
                    clip: true
                    implicitHeight: connectionColumn.implicitHeight + 20
                    radius: 10
                    color: "transparent"
                    border.width: 1
                    border.color: root.accentPrimary

                    ColumnLayout {
                        id: connectionColumn
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        readonly property real actionButtonWidth: Math.max(forgetLabel.implicitWidth, disconnectLabel.implicitWidth) + 20

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "󰩟"
                                font.pixelSize: 13
                                color: root.accentPrimary
                            }

                            Text {
                                text: "IP: " + root.ipAddress
                                color: root.textMain
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: root.activeSsid !== ""

                            Item { Layout.fillWidth: true }

                            Rectangle {
                                implicitWidth: connectionColumn.actionButtonWidth
                                height: 28
                                radius: 10
                                color: forgetArea.pressed ? Qt.darker(root.accentPrimary, 1.2)
                                       : forgetArea.containsMouse ? root.accentSecondary : root.accentPrimary
                                scale: forgetArea.pressed ? 0.95 : 1.0

                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                                Text {
                                    id: forgetLabel
                                    anchors.centerIn: parent
                                    text: "Забыть"
                                    color: root.bgPanel
                                    font.pixelSize: 12
                                }

                                MouseArea {
                                    id: forgetArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.forgetActive()
                                }
                            }

                            Rectangle {
                                implicitWidth: connectionColumn.actionButtonWidth
                                height: 28
                                radius: 10
                                color: disconnectArea.pressed ? Qt.darker(root.accentPrimary, 1.2)
                                       : disconnectArea.containsMouse ? root.accentSecondary : root.accentPrimary
                                scale: disconnectArea.pressed ? 0.95 : 1.0

                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                                Text {
                                    id: disconnectLabel
                                    anchors.centerIn: parent
                                    text: "Отключить"
                                    color: root.bgPanel
                                    font.pixelSize: 12
                                }

                                MouseArea {
                                    id: disconnectArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.disconnectActive()
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: root.separatorColor
                    visible: root.wifiEnabled
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.wifiEnabled

                    Text {
                        text: "Доступные сети"
                        color: root.textDim
                        font.pixelSize: 12
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        id: refreshButton
                        width: 30
                        height: 30
                        radius: 15
                        color: refreshArea.pressed ? Qt.darker(root.accentPrimary, 1.2)
                               : refreshArea.containsMouse ? root.accentSecondary : root.accentPrimary
                        scale: refreshArea.pressed ? 0.88 : 1.0

                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                        Text {
                            id: refreshIcon
                            anchors.centerIn: parent
                            text: "󰑐"
                            font.pixelSize: 14
                            color: root.bgPanel

                            RotationAnimation on rotation {
                                running: root.scanning
                                loops: Animation.Infinite
                                from: 0
                                to: 360
                                duration: 900
                            }
                        }

                        MouseArea {
                            id: refreshArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.scanNetworks()
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.errorText !== ""
                    text: root.errorText
                    color: root.accentText
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }

            Flickable {
                id: networkList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                visible: root.wifiEnabled
                contentHeight: networkColumn.height
                boundsBehavior: Flickable.StopAtBounds
                opacity: 0

                transform: Translate {
                    id: networkListTranslate
                    y: -12
                }

                ColumnLayout {
                    id: networkColumn
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: root.availableNetworks

                        delegate: Rectangle {
                            Layout.fillWidth: true
                            height: 48
                            radius: 12
                            color: modelData.active ? root.workspaceActive
                                   : netArea.containsMouse ? root.bgTrack : "transparent"
                            scale: netArea.pressed ? 0.98 : 1.0

                            Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10

                                Text {
                                    text: root.wifiIcon(modelData.signal)
                                    font.pixelSize: 16
                                    color: modelData.active ? root.bgPanel : root.accentPrimary
                                }

                                Text {
                                    text: modelData.ssid
                                    color: modelData.active ? root.bgPanel : root.textMain
                                    font.pixelSize: 13
                                    font.bold: modelData.active
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Text {
                                    visible: modelData.secure
                                    text: "󰌾"
                                    font.pixelSize: 12
                                    color: modelData.active ? root.bgPanel : root.textDim
                                }

                                Text {
                                    visible: root.connectingSsid === modelData.ssid
                                    text: "…"
                                    font.pixelSize: 14
                                    color: root.accentPrimary
                                }
                            }

                            MouseArea {
                                id: netArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.active)
                                        return
                                    root.connectTo(modelData.ssid, modelData.secure, modelData.known === true)
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        visible: root.availableNetworks.length === 0 && !root.scanning
                        text: "Сети не найдены"
                        color: root.textDim
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }

        Rectangle {
            id: wifiToggleButton
            z: 20
            clip: true
            color: toggleMouseArea.pressed ? Qt.darker(root.accentPrimary, 1.2)
                   : toggleMouseArea.containsMouse ? root.accentSecondary
                   : root.accentPrimary

            scale: toggleMouseArea.pressed ? 0.9 : 1.0

            Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            state: root.wifiEnabled ? "small" : "big"

            states: [
                State {
                    name: "big"
                    AnchorChanges {
                        target: wifiToggleButton
                        anchors.top: undefined
                        anchors.right: undefined
                        anchors.horizontalCenter: card.horizontalCenter
                        anchors.verticalCenter: card.verticalCenter
                    }
                    PropertyChanges {
                        target: wifiToggleButton
                        width: 120
                        height: 120
                        radius: 28
                    }
                },
                State {
                    name: "small"
                    AnchorChanges {
                        target: wifiToggleButton
                        anchors.horizontalCenter: undefined
                        anchors.verticalCenter: undefined
                        anchors.top: card.top
                        anchors.right: card.right
                    }
                    PropertyChanges {
                        target: wifiToggleButton
                        width: 36
                        height: 36
                        radius: 10
                        anchors.topMargin: 24
                        anchors.rightMargin: 24
                    }
                }
            ]

            transitions: Transition {
                AnchorAnimation { duration: 260; easing.type: Easing.OutCubic }
                NumberAnimation { properties: "width,height,radius"; duration: 260; easing.type: Easing.OutCubic }
            }

            Rectangle {
                id: holdFill
                visible: root.wifiEnabled
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                color: Qt.rgba(0, 0, 0, 0.28)
                height: 0
            }

            NumberAnimation {
                id: holdFillAnim
                target: holdFill
                property: "height"
                from: 0
                to: wifiToggleButton.height
                duration: toggleMouseArea.pressAndHoldInterval
                easing.type: Easing.Linear
            }

            NumberAnimation {
                id: holdResetAnim
                target: holdFill
                property: "height"
                to: 0
                duration: 140
                easing.type: Easing.OutCubic
            }

            Text {
                anchors.centerIn: parent
                text: "󰖪"
                color: root.bgPanel
                font.pixelSize: 42
                opacity: wifiToggleButton.state === "big" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }

            Text {
                anchors.centerIn: parent
                text: "󰖩"
                color: root.bgPanel
                font.pixelSize: 17
                opacity: wifiToggleButton.state === "small" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }

            MouseArea {
                id: toggleMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                pressAndHoldInterval: 650

                onPressed: {
                    if (root.wifiEnabled) {
                        holdResetAnim.stop()
                        holdFill.width = 0
                        holdFillAnim.restart()
                    }
                }

                onReleased: {
                    holdFillAnim.stop()
                    holdResetAnim.restart()
                }

                onCanceled: {
                    holdFillAnim.stop()
                    holdResetAnim.restart()
                }

                onClicked: {
                    if (!root.wifiEnabled)
                        root.toggleRadio()
                }

                onPressAndHold: {
                    if (root.wifiEnabled) {
                        holdFillAnim.stop()
                        holdFill.width = 0
                        root.toggleRadio()
                    }
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: Qt.rgba(0, 0, 0, 0.55)
            visible: root.passwordPromptVisible

            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            Rectangle {
                width: parent.width - 40
                anchors.centerIn: parent
                radius: 18
                color: root.bgPanel
                border.width: 2
                border.color: root.accentPrimary
                height: promptColumn.height + 32

                ColumnLayout {
                    id: promptColumn
                    anchors.centerIn: parent
                    width: parent.width - 32
                    spacing: 12

                    Text {
                        text: root.pendingSsid
                        color: root.textMain
                        font.pixelSize: 15
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 38
                        radius: 12
                        color: root.bgInput
                        border.width: 1
                        border.color: passwordField.activeFocus ? root.accentPrimary : root.separatorColor

                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        TextInput {
                            id: passwordField
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            verticalAlignment: TextInput.AlignVCenter
                            color: root.inputTextColor
                            font.pixelSize: 13
                            echoMode: TextInput.Password
                            clip: true
                            Keys.onReturnPressed: root.connectWithPassword()
                            Keys.onEscapePressed: root.cancelPassword()
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            Layout.fillWidth: true
                            height: 34
                            radius: 12
                            color: cancelArea.pressed ? Qt.darker(root.accentPrimary, 1.2)
                                   : cancelArea.containsMouse ? root.accentSecondary : root.accentPrimary
                            scale: cancelArea.pressed ? 0.96 : 1.0

                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                            Text {
                                anchors.centerIn: parent
                                text: "Отмена"
                                color: root.bgPanel
                                font.pixelSize: 12
                            }

                            MouseArea {
                                id: cancelArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.cancelPassword()
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 34
                            radius: 12
                            color: connectArea.pressed ? Qt.darker(root.accentPrimary, 1.15)
                                   : connectArea.containsMouse ? root.accentSecondary : root.accentPrimary
                            opacity: passwordField.text.length > 0 ? 1.0 : 0.5
                            scale: connectArea.pressed ? 0.96 : 1.0

                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                            Text {
                                anchors.centerIn: parent
                                text: "Подключить"
                                color: root.bgPanel
                                font.pixelSize: 12
                                font.bold: true
                            }

                            MouseArea {
                                id: connectArea
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: passwordField.text.length > 0
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.connectWithPassword()
                            }
                        }
                    }
                }
            }
        }
    }
}
