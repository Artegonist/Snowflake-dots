import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Bluetooth

PanelWindow {
    id: root

    //----------------WINDOW----------------
    visible: false
    focusable: true
    WlrLayershell.keyboardFocus: root.expanded ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

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
        root.closeDeviceSettings()
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
        right: 123
    }

    exclusionMode: ExclusionMode.Ignore

    color: "transparent"
    implicitWidth: 380
    implicitHeight: 540

    //----------------COLORS----------------
    readonly property color accentPrimary:   "{{theme.accent_primary.hex}}"
    readonly property color accentSecondary: "{{theme.accent_secondary.hex}}"
    readonly property color bgPanelWaybar:   "{{theme.bg_panel_waybar.hex}}"
    readonly property color bgPanel:         "{{theme.bg_panel_battery.hex}}"
    readonly property color bgTrack:         "{{theme.bg_track.hex}}"
    readonly property color bgInput:         "{{theme.bg_input_wofi.hex}}"
    readonly property color textMain:        "{{theme.text_main.hex}}"
    readonly property color textDim:         "{{theme.text_dim.hex}}"
    readonly property color textWaybar:      "{{theme.text_waybar.hex}}"
    readonly property color workspaceActive: "{{theme.workspace_active.hex}}"
    readonly property color hoverLight:      "{{theme.hover_light.hex}}"
    readonly property color hoverSelect:     "{{theme.hover_wofi_select.hex}}"
    readonly property color inputTextColor:  "{{theme.wofi_input_text.hex}}"
    readonly property color accentText:      "{{theme.wofi_accent_text.hex}}"

    readonly property color borderColor: accentPrimary
    readonly property color separatorColor: Qt.rgba(1, 1, 1, 0.08)

    //----------------STATE----------------
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool btEnabled: root.adapter ? root.adapter.enabled : false
    readonly property bool scanning: root.adapter ? root.adapter.discovering : false
    readonly property var allDevices: root.adapter ? root.adapter.devices.values : []

    readonly property var connectedDevicesList: {
        const arr = root.allDevices.filter(function(d) { return d.connected })
        arr.sort(function(a, b) { return (a.name || "").localeCompare(b.name || "") })
        return arr
    }
    readonly property int connectedCount: root.connectedDevicesList.length
    readonly property var connectedDevice: root.connectedCount > 0 ? root.connectedDevicesList[0] : null

    readonly property var listDevices: {
        const list = root.allDevices.filter(function(d) {
            return !d.connected
        })
        list.sort(function(a, b) {
            if (a.paired !== b.paired) return a.paired ? -1 : 1
            return (a.name || "").localeCompare(b.name || "")
        })
        return list
    }

    //----------------OPS----------------
    property var deviceOps: ({})
    property int opsVersion: 0
    property string errorText: ""

    onErrorTextChanged: {
        if (root.errorText !== "")
            errorTextTimer.restart()
        else
            errorTextTimer.stop()
    }

    Timer {
        id: errorTextTimer
        interval: 4000
        repeat: false
        onTriggered: root.errorText = ""
    }

    //----------------AUTOCONNECT----------------
    property var autoConnectAttempts: ({})
    readonly property int autoConnectCooldownMs: 20000
    property var wasOursAt: ({})

    property bool deviceSettingsVisible: false
    property var activeSettingsDevice: null
    property string renameText: ""

    function opFor(path) {
        return root.opsVersion >= 0 ? root.deviceOps[path] : undefined
    }
    function isBusy(path) {
        return !!root.opFor(path)
    }
    function startOp(device, action, auto) {
        const ops = root.deviceOps
        ops[device.dbusPath] = { action: action, name: device.name, bounce: false, auto: !!auto }
        root.deviceOps = ops
        root.opsVersion++
    }
    function endOp(path, message) {
        const op = root.opFor(path)
        if (!op) {
            if (message !== undefined) root.errorText = message
            return
        }
        const ops = root.deviceOps
        delete ops[path]
        root.deviceOps = ops
        root.opsVersion++
        if (message !== undefined && !op.auto)
            root.errorText = message
    }
    function setBounce(path, val) {
        const ops = root.deviceOps
        if (ops[path]) {
            ops[path].bounce = val
            root.deviceOps = ops
            root.opsVersion++
        }
    }

    //----------------FUNCTIONS----------------
    function refreshAll() {
        root.scanDevices()
    }

    function toggleAdapter() {
        return root.setAdapterEnabled(!root.btEnabled)
    }

    function setAdapterEnabled(enabled) {
        if (!root.adapter) return false
        const turnOn = enabled === true
        root.adapter.enabled = turnOn
        if (!turnOn) {
            root.errorText = ""
            root.stopScan()
        }
        return true
    }

    function scanDevices() {
        if (!root.adapter || !root.btEnabled) return
        root.adapter.discovering = true
    }

    function stopScan() {
        if (root.adapter) root.adapter.discovering = false
    }

    function safeIconPath(name) {
        if (!name || name.length === 0) return ""
        return Quickshell.iconPath(name, true)
    }

    function fallbackGlyph(iconName) {
        const n = (iconName || "").toLowerCase()
        if (n.indexOf("headset") !== -1) return "\uee59"
        if (n.indexOf("headphone") !== -1) return "\uf025"
        if (n.indexOf("mouse") !== -1) return "\uefba"
        if (n.indexOf("keyboard") !== -1) return "\uf11c"
        if (n.indexOf("gaming") !== -1 || n.indexOf("joystick") !== -1 || n.indexOf("gamepad") !== -1)
            return "\uf11b"
        if (n.indexOf("tablet") !== -1) return "\uf10a"
        if (n.indexOf("phone") !== -1) return "\uf10b"
        if (n.indexOf("watch") !== -1) return "\uf017"
        if (n.indexOf("laptop") !== -1) return "\uf109"
        if (n.indexOf("desktop") !== -1 || n === "computer") return "\uf108"
        if (n.indexOf("printer") !== -1) return "\uf02f"
        if (n.indexOf("camera") !== -1) return "\uf030"
        if (n.indexOf("scanner") !== -1) return "\uf02f"
        if (n.indexOf("audio-card") !== -1 || n.indexOf("speaker") !== -1 || n.indexOf("multimedia") !== -1)
            return "\uf028"
        if (n.indexOf("microphone") !== -1) return "\uf130"
        if (n.indexOf("network-wireless") !== -1 || n.indexOf("wifi") !== -1) return "\uf1eb"
        if (n.indexOf("car") !== -1) return "\uf1b9"
        if (n.indexOf("tv") !== -1 || n.indexOf("display") !== -1) return "\uf26c"
        return "󰂯"
    }

    function connectDevice(device, auto) {
        if (!device || root.isBusy(device.dbusPath)) return
        if (device.connected) return
        if (!auto) root.errorText = ""
        root.startOp(device, "connect", !!auto)
        if (device.paired || device.bonded) {
            device.connected = true
        } else {
            device.pair()
        }
    }

    function disconnectDevice(device) {
        if (!device || root.isBusy(device.dbusPath)) return
        root.errorText = ""
        root.startOp(device, "disconnect")
        const wo = root.wasOursAt
        delete wo[device.dbusPath]
        root.wasOursAt = wo
        const attempts = root.autoConnectAttempts
        attempts[device.dbusPath] = Date.now()
        root.autoConnectAttempts = attempts
        device.connected = false
    }

    function forgetDevice(device) {
        if (!device) return
        root.endOp(device.dbusPath)
        const attempts = root.autoConnectAttempts
        delete attempts[device.dbusPath]
        root.autoConnectAttempts = attempts
        const wo = root.wasOursAt
        delete wo[device.dbusPath]
        root.wasOursAt = wo
        device.forget()
        root.closeDeviceSettings()
    }

    function toggleTrust(device) {
        if (!device) return
        device.trusted = !device.trusted
    }

    function openDeviceSettings(device) {
        root.activeSettingsDevice = device
        root.renameText = device.name
        root.deviceSettingsVisible = true
    }

    function closeDeviceSettings() {
        root.deviceSettingsVisible = false
        root.activeSettingsDevice = null
        card.forceActiveFocus()
    }

    function applyRename() {
        if (root.activeSettingsDevice && root.renameText.length > 0)
            root.activeSettingsDevice.name = root.renameText
    }

    function batteryText(device) {
        if (!device || !device.batteryAvailable) return ""
        return Math.round(device.battery * 100) + "%"
    }

    function batteryIcon(pct) {
        if (pct >= 90) return "\uf240"
        if (pct >= 60) return "\uf241"
        if (pct >= 30) return "\uf242"
        if (pct >= 10) return "\uf243"
        return "\uf244"
    }

    function statusLabel(device) {
        if (device.pairing) return "сопряжение…"
        if (device.connected) return "подключено"
        if (device.paired) return "сопряжено"
        return "доступно"
    }

    //----------------REACTIVE----------------
    Repeater {
        model: root.allDevices
        delegate: Item {
            id: opItem
            required property var modelData
            readonly property var op: root.opFor(modelData.dbusPath)

            onOpChanged: {
                if (op) watchdog.restart()
                else watchdog.stop()
            }

            Timer {
                id: watchdog
                interval: 15000
                repeat: false
                onTriggered: {
                    if (!opItem.op) return
                    const name = opItem.op.name || "устройство"
                    const action = opItem.op.action
                    if (modelData.pairing)
                        modelData.cancelPair()
                    root.endOp(modelData.dbusPath, action === "disconnect"
                        ? "Не удалось отключить " + name + " — истекло время ожидания"
                        : "Не удалось подключить " + name + " — истекло время ожидания")
                }
            }

            Timer {
                id: reconnectAfterPairTimer
                interval: 400
                repeat: false
                onTriggered: {
                    root.setBounce(modelData.dbusPath, false)
                    modelData.connected = true
                }
            }

            Connections {
                target: modelData
                function onPairedChanged() {
                    if (!opItem.op) return
                    if (modelData.paired) {
                        if (modelData.connected) {
                            root.setBounce(modelData.dbusPath, true)
                            modelData.connected = false
                            reconnectAfterPairTimer.restart()
                        } else {
                            modelData.connected = true
                        }
                    } else if (!modelData.pairing) {
                        root.endOp(modelData.dbusPath, "Не удалось сопрячь " + modelData.name)
                    }
                }
                function onConnectedChanged() {
                    const op = opItem.op
                    if (!op || op.bounce) return
                    if (op.action === "disconnect")
                        root.endOp(modelData.dbusPath,
                            modelData.connected ? ("Не удалось отключить " + modelData.name) : undefined)
                    else
                        root.endOp(modelData.dbusPath,
                            modelData.connected ? undefined : ("Не удалось подключить " + modelData.name))
                }
                function onPairingChanged() {
                    if (!modelData.pairing && !modelData.paired && opItem.op) {
                        root.endOp(modelData.dbusPath, "Сопряжение отменено")
                    }
                }
                function onStateChanged() {
                    const op = opItem.op
                    if (!op || op.bounce) return
                    if (modelData.state === BluetoothDeviceState.Connecting
                        || modelData.state === BluetoothDeviceState.Disconnecting)
                        return
                    if (op.action === "disconnect")
                        root.endOp(modelData.dbusPath, modelData.state === BluetoothDeviceState.Disconnected
                            ? undefined : ("Не удалось отключить " + modelData.name))
                    else
                        root.endOp(modelData.dbusPath, modelData.state === BluetoothDeviceState.Connected
                            ? undefined : ("Не удалось подключить " + modelData.name))
                }
            }
        }
    }

    //----------------TIMERS----------------
    Timer {
        interval: 12000
        running: root.expanded && root.btEnabled
        repeat: true
        onTriggered: root.scanDevices()
    }

    Timer {
        interval: 20000
        running: root.expanded && root.btEnabled
        repeat: true
        onTriggered: {
            if (!root.scanning) root.scanDevices()
        }
    }

    Timer {
        interval: 5000
        running: root.btEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: root.tryAutoConnect()
    }

    function tryAutoConnect() {
        if (!root.btEnabled) return
        const now = Date.now()
        const wo = root.wasOursAt
        let woChanged = false
        for (const d of root.allDevices) {
            if (d.connected) {
                wo[d.dbusPath] = now
                woChanged = true
                continue
            }
            if (!d.trusted || !d.paired) continue
            if (root.isBusy(d.dbusPath)) continue
            if (!(d.dbusPath in wo)) continue
            const last = root.autoConnectAttempts[d.dbusPath] || 0
            if (now - last < root.autoConnectCooldownMs) continue
            const attempts = root.autoConnectAttempts
            attempts[d.dbusPath] = now
            root.autoConnectAttempts = attempts
            root.connectDevice(d, true)
        }
        if (woChanged) root.wasOursAt = wo
    }

    onExpandedChanged: {
        if (!root.expanded) root.stopScan()
    }

    //----------------FOCUS----------------
    HyprlandFocusGrab {
        id: focusGrab
        windows: [root]
        onCleared: root.hide()
    }

    onVisibleChanged: {
        if (visible && !root.expanded)
            root.expanded = true
    }

    //----------------LAYOUT----------------
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

        //----------------ANIMATIONS----------------
        SequentialAnimation {
            id: openAnim

            ScriptAction {
                script: {
                    topSection.opacity = 0
                    topSectionTranslate.y = -12
                    deviceList.opacity = 0
                    deviceListTranslate.y = -12
                }
            }

            ParallelAnimation {
                NumberAnimation { target: card; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
                NumberAnimation {
                    target: card; property: "scale"; to: 1; duration: 190
                    easing.type: Easing.OutBack; easing.overshoot: 1.1
                }

                SequentialAnimation {
                    PauseAnimation { duration: 35 }
                    ParallelAnimation {
                        NumberAnimation {
                            target: topSection; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            target: topSectionTranslate; property: "y"; to: 0; duration: 170; easing.type: Easing.OutCubic
                        }
                    }
                }

                SequentialAnimation {
                    PauseAnimation { duration: 70 }
                    ParallelAnimation {
                        NumberAnimation {
                            target: deviceList; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            target: deviceListTranslate; property: "y"; to: 0; duration: 170; easing.type: Easing.OutCubic
                        }
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

        //----------------CONTENT----------------
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 14
            visible: root.btEnabled

            //----------------HEADER----------------
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

                    Item {
                        width: 44
                        height: 24
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: root.btEnabled
                              ? (root.connectedCount > 1
                                     ? root.connectedDevice.name + " +" + (root.connectedCount - 1)
                                     : (root.connectedDevice ? root.connectedDevice.name : "Bluetooth"))
                              : "Bluetooth выключен"
                        color: root.textMain
                        font.pixelSize: 18
                        font.bold: true
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignRight
                        Layout.fillWidth: true
                        Layout.maximumWidth: 170
                    }

                    Text {
                        text: root.btEnabled ? "󰂯" : "󰂲"
                        font.pixelSize: 20
                        color: root.accentPrimary
                    }
                }

                //----------------CONNECTED----------------
                Rectangle {
                    id: connectionInfo
                    Layout.fillWidth: true
                    visible: root.btEnabled
                    clip: true
                    implicitHeight: connectionColumn.implicitHeight + 20
                    radius: 10
                    color: "transparent"
                    border.width: 1
                    border.color: root.accentPrimary
                    property real changeOpacity: 1
                    property real changeScale: 1
                    property real disconnectionOpacity: 1
                    opacity: changeOpacity * disconnectionOpacity
                    scale: changeScale
                    transformOrigin: Item.Center

                    readonly property bool disconnecting: {
                        for (const d of root.connectedDevicesList) {
                            const op = root.opFor(d.dbusPath)
                            if (op && !op.auto) return true
                        }
                        return false
                    }

                    ParallelAnimation {
                        id: connectionStateAnim
                        NumberAnimation {
                            target: connectionInfo
                            property: "changeOpacity"
                            from: 0.6
                            to: 1
                            duration: 240
                            easing.type: Easing.OutCubic
                        }
                        SequentialAnimation {
                            NumberAnimation {
                                target: connectionInfo
                                property: "changeScale"
                                from: 0.94
                                to: 1.025
                                duration: 150
                                easing.type: Easing.OutCubic
                            }
                            NumberAnimation {
                                target: connectionInfo
                                property: "changeScale"
                                to: 1
                                duration: 190
                                easing.type: Easing.OutBack
                                easing.overshoot: 1.6
                            }
                        }
                    }

                    property string _lastPoppedKey: ""

                    Connections {
                        target: root
                        function onConnectedDevicesListChanged() {
                            const key = root.connectedDevicesList.map(function(d) { return d.dbusPath }).join(",")
                            if (key === connectionInfo._lastPoppedKey) return
                            connectionInfo._lastPoppedKey = key
                            if (root.expanded && root.btEnabled && root.connectedCount > 0)
                                connectionStateAnim.restart()
                        }
                    }

                    SequentialAnimation {
                        id: disconnectPulse
                        running: connectionInfo.disconnecting
                        loops: Animation.Infinite
                        NumberAnimation {
                            target: connectionInfo
                            property: "disconnectionOpacity"
                            to: 0.5
                            duration: 480
                            easing.type: Easing.InOutSine
                        }
                        NumberAnimation {
                            target: connectionInfo
                            property: "disconnectionOpacity"
                            to: 1
                            duration: 480
                            easing.type: Easing.InOutSine
                        }
                        onRunningChanged: {
                            if (!running)
                                disconnectSettle.restart()
                        }
                    }

                    NumberAnimation {
                        id: disconnectSettle
                        target: connectionInfo
                        property: "disconnectionOpacity"
                        to: 1
                        duration: 200
                        easing.type: Easing.OutCubic
                    }

                    ColumnLayout {
                        id: connectionColumn
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: root.connectedCount === 0

                            Text {
                                text: "󰂲"
                                font.pixelSize: 13
                                color: root.accentPrimary
                            }

                            Text {
                                text: "Нет подключённых устройств"
                                color: root.textMain
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        Repeater {
                            model: root.connectedDevicesList

                            delegate: ColumnLayout {
                                id: connectedBlock
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                spacing: 8
                                scale: 1
                                transformOrigin: Item.Center

                                readonly property real actionButtonWidth:
                                    Math.max(forgetLabel.implicitWidth, disconnectLabel.implicitWidth) + 20

                                Component.onCompleted: connectBounce.start()

                                SequentialAnimation {
                                    id: connectBounce
                                    NumberAnimation {
                                        target: connectedBlock; property: "scale"
                                        to: 1.035; duration: 130; easing.type: Easing.OutCubic
                                    }
                                    NumberAnimation {
                                        target: connectedBlock; property: "scale"
                                        to: 1.0; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2.0
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Rectangle {
                                        width: 22; height: 22; radius: 11
                                        color: gearArea.containsMouse ? root.accentSecondary : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰒓"
                                            font.pixelSize: 12
                                            color: root.textDim
                                        }
                                        MouseArea {
                                            id: gearArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.openDeviceSettings(connectedBlock.modelData)
                                        }
                                    }

                                    RowLayout {
                                        spacing: 4
                                        visible: connectedBlock.modelData.batteryAvailable
                                        Text {
                                            text: root.batteryText(connectedBlock.modelData)
                                            color: root.textDim
                                            font.pixelSize: 12
                                        }
                                        Text {
                                            text: root.batteryIcon(Math.round(connectedBlock.modelData.battery * 100))
                                            font.pixelSize: 13
                                            color: root.accentPrimary
                                        }
                                    }

                                    Text {
                                        text: connectedBlock.modelData.name
                                        color: root.textMain
                                        font.pixelSize: 13
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignRight
                                        Layout.fillWidth: true
                                    }

                                    Item {
                                        width: 16; height: 16

                                        readonly property string iconPath:
                                            root.safeIconPath(connectedBlock.modelData.icon)

                                        Image {
                                            anchors.fill: parent
                                            visible: parent.iconPath !== ""
                                            source: parent.iconPath
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            visible: parent.iconPath === ""
                                            text: root.fallbackGlyph(connectedBlock.modelData.icon)
                                            font.pixelSize: 12
                                            color: root.textDim
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Rectangle {
                                        implicitWidth: connectedBlock.actionButtonWidth
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
                                            onClicked: root.disconnectDevice(connectedBlock.modelData)
                                        }
                                    }

                                    Rectangle {
                                        implicitWidth: connectedBlock.actionButtonWidth
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
                                            onClicked: root.forgetDevice(connectedBlock.modelData)
                                        }
                                    }

                                    Item { Layout.fillWidth: true }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 2
                                    height: 1
                                    color: root.separatorColor
                                    visible: connectedBlock.index < root.connectedCount - 1
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: root.separatorColor
                    visible: root.btEnabled
                }

                //----------------DEVICES----------------
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.btEnabled

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
                            onClicked: root.scanDevices()
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: "Устройства"
                        color: root.textDim
                        font.pixelSize: 12
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

            //----------------LIST----------------
            Flickable {
                id: deviceList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                visible: root.btEnabled
                contentHeight: deviceColumn.height
                boundsBehavior: Flickable.StopAtBounds
                opacity: 0

                transform: Translate {
                    id: deviceListTranslate
                    y: -12
                }

                ColumnLayout {
                    id: deviceColumn
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: root.listDevices

                        delegate: Rectangle {
                            Layout.fillWidth: true
                            height: 48
                            radius: 12
                            color: devArea.containsMouse ? root.bgTrack : "transparent"
                            scale: devArea.pressed ? 0.98 : 1.0

                            Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                anchors.rightMargin: 10
                                spacing: 10

                                Text {
                                    visible: root.isBusy(modelData.dbusPath) || modelData.pairing
                                    text: "…"
                                    font.pixelSize: 14
                                    color: root.accentPrimary
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    Text {
                                        text: modelData.name
                                        color: root.textMain
                                        font.pixelSize: 13
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignRight
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        text: root.statusLabel(modelData)
                                        color: modelData.paired ? root.accentPrimary : root.textDim
                                        font.pixelSize: 10
                                        horizontalAlignment: Text.AlignRight
                                        Layout.fillWidth: true
                                    }
                                }

                                Item {
                                    id: deviceIcon
                                    width: 18; height: 18
                                    transformOrigin: Item.Center

                                    readonly property string iconPath: root.safeIconPath(modelData.icon)
                                    readonly property bool connectingThis: modelData.pairing
                                        || root.isBusy(modelData.dbusPath)

                                    Image {
                                        anchors.fill: parent
                                        visible: parent.iconPath !== ""
                                        source: parent.iconPath
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        visible: parent.iconPath === ""
                                        text: root.fallbackGlyph(modelData.icon)
                                        font.pixelSize: 13
                                        color: root.textDim
                                    }

                                    SequentialAnimation on opacity {
                                        running: deviceIcon.connectingThis
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 1; to: 0.35; duration: 420; easing.type: Easing.InOutSine }
                                        NumberAnimation { from: 0.35; to: 1; duration: 420; easing.type: Easing.InOutSine }
                                        onRunningChanged: {
                                            if (!running)
                                                deviceIcon.opacity = 1
                                        }
                                    }

                                    SequentialAnimation on scale {
                                        running: deviceIcon.connectingThis
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 1; to: 1.22; duration: 420; easing.type: Easing.InOutSine }
                                        NumberAnimation { from: 1.22; to: 1; duration: 420; easing.type: Easing.InOutSine }
                                        onRunningChanged: {
                                            if (!running)
                                                deviceIcon.scale = 1
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: devArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.connectDevice(modelData)
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        visible: root.listDevices.length === 0 && !root.scanning
                        text: "Устройства не найдены"
                        color: root.textDim
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }

        //----------------TOGGLE----------------
        Rectangle {
            id: btToggleButton
            z: 20
            clip: true
            color: toggleMouseArea.pressed ? Qt.darker(root.accentPrimary, 1.2)
                   : toggleMouseArea.containsMouse ? root.accentSecondary
                   : root.accentPrimary

            scale: toggleMouseArea.pressed ? 0.9 : 1.0

            Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            state: root.btEnabled ? "small" : "big"

            states: [
                State {
                    name: "big"
                    AnchorChanges {
                        target: btToggleButton
                        anchors.top: undefined
                        anchors.left: undefined
                        anchors.horizontalCenter: card.horizontalCenter
                        anchors.verticalCenter: card.verticalCenter
                    }
                    PropertyChanges {
                        target: btToggleButton
                        width: 120
                        height: 120
                        radius: 28
                    }
                },
                State {
                    name: "small"
                    AnchorChanges {
                        target: btToggleButton
                        anchors.horizontalCenter: undefined
                        anchors.verticalCenter: undefined
                        anchors.top: card.top
                        anchors.left: card.left
                    }
                    PropertyChanges {
                        target: btToggleButton
                        width: 36
                        height: 36
                        radius: 10
                        anchors.topMargin: 24
                        anchors.leftMargin: 24
                    }
                }
            ]

            transitions: Transition {
                AnchorAnimation { duration: 260; easing.type: Easing.OutCubic }
                NumberAnimation { properties: "width,height,radius"; duration: 260; easing.type: Easing.OutCubic }
            }

            Rectangle {
                id: holdFill
                visible: root.btEnabled
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
                to: btToggleButton.height
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
                text: "󰂲"
                color: root.bgPanel
                font.pixelSize: 42
                opacity: btToggleButton.state === "big" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }

            Text {
                anchors.centerIn: parent
                text: "󰂯"
                color: root.bgPanel
                font.pixelSize: 17
                opacity: btToggleButton.state === "small" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }

            MouseArea {
                id: toggleMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                pressAndHoldInterval: 650
                property bool enabledOnPress: false
                property bool holdArmed: false
                property bool pressHandled: true

                function resetFill() {
                    holdFillAnim.stop()
                    holdResetAnim.restart()
                }

                function cancelPress() {
                    holdArmed = false
                    pressHandled = true
                    resetFill()
                }

                onPressed: {
                    enabledOnPress = root.btEnabled
                    pressHandled = !root.expanded || root.closing
                    holdArmed = enabledOnPress && !pressHandled
                    holdFillAnim.stop()
                    holdResetAnim.stop()
                    holdFill.height = 0
                    if (!enabledOnPress && !pressHandled) {
                        pressHandled = true
                        root.setAdapterEnabled(true)
                    } else if (holdArmed) {
                        holdFillAnim.restart()
                    }
                }

                onReleased: {
                    holdArmed = false
                    resetFill()
                }

                onCanceled: cancelPress()
                onExited: {
                    if (pressed)
                        cancelPress()
                }

                onClicked: pressHandled = true

                onPressAndHold: {
                    if (!holdArmed || pressHandled || !pressed || !containsMouse || !root.expanded || root.closing)
                        return
                    holdArmed = false
                    pressHandled = true
                    resetFill()
                    root.setAdapterEnabled(false)
                }
            }
        }

        //----------------SETTINGS----------------
        Rectangle {
            anchors.fill: parent
            radius: 8
            color: Qt.rgba(0, 0, 0, 0.55)
            visible: root.deviceSettingsVisible

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
                height: settingsColumn.height + 32

                ColumnLayout {
                    id: settingsColumn
                    anchors.centerIn: parent
                    width: parent.width - 32
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: root.activeSettingsDevice ? root.activeSettingsDevice.name : ""
                            color: root.textMain
                            font.pixelSize: 15
                            font.bold: true
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignRight
                            Layout.fillWidth: true
                        }

                        Item {
                            width: 20; height: 20

                            readonly property string iconPath:
                                root.activeSettingsDevice ? root.safeIconPath(root.activeSettingsDevice.icon) : ""

                            Image {
                                anchors.fill: parent
                                visible: parent.iconPath !== ""
                                source: parent.iconPath
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: parent.iconPath === ""
                                text: root.activeSettingsDevice ? root.fallbackGlyph(root.activeSettingsDevice.icon) : "󰂯"
                                font.pixelSize: 13
                                color: root.textDim
                            }
                        }
                    }

                    //----------------RENAME----------------
                    Rectangle {
                        Layout.fillWidth: true
                        height: 38
                        radius: 12
                        color: root.bgInput
                        border.width: 1
                        border.color: renameField.activeFocus ? root.accentPrimary : root.separatorColor

                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        TextInput {
                            id: renameField
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            verticalAlignment: TextInput.AlignVCenter
                            color: root.inputTextColor
                            font.pixelSize: 13
                            clip: true
                            text: root.renameText
                            onTextChanged: root.renameText = text
                            Keys.onReturnPressed: root.applyRename()
                            Keys.onEscapePressed: root.closeDeviceSettings()
                        }
                    }

                    //----------------BATTERY----------------
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: root.activeSettingsDevice && root.activeSettingsDevice.batteryAvailable

                        Item { Layout.fillWidth: true }

                        Text {
                            text: "Заряд: "
                                  + (root.activeSettingsDevice ? root.batteryText(root.activeSettingsDevice) : "")
                            color: root.textMain
                            font.pixelSize: 13
                        }
                        Text {
                            text: root.activeSettingsDevice
                                  ? root.batteryIcon(Math.round(root.activeSettingsDevice.battery * 100)) : ""
                            font.pixelSize: 14
                            color: root.accentPrimary
                        }
                    }

                    //----------------TRUST----------------
                    Rectangle {
                        id: trustRow
                        Layout.fillWidth: true
                        height: 42
                        radius: 12
                        color: trustArea.containsMouse ? root.bgTrack : "transparent"
                        border.width: 1
                        border.color: root.separatorColor

                        Behavior on color { ColorAnimation { duration: 120 } }

                        readonly property bool trusted:
                            root.activeSettingsDevice ? root.activeSettingsDevice.trusted : false

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10

                            Rectangle {
                                id: trustSwitch
                                width: 38; height: 20; radius: 10
                                color: trustRow.trusted ? root.accentPrimary : root.bgInput
                                border.width: trustRow.trusted ? 0 : 1
                                border.color: root.separatorColor

                                Behavior on color { ColorAnimation { duration: 150 } }

                                Rectangle {
                                    width: 14; height: 14; radius: 7
                                    color: root.bgPanel
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: trustRow.trusted ? parent.width - width - 3 : 3
                                    Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                }
                            }

                            Text {
                                text: trustRow.trusted ? "Доверенное устройство" : "Сделать доверенным"
                                color: root.textMain
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignRight
                                Layout.fillWidth: true
                            }

                            Text {
                                text: "󰕥"
                                font.pixelSize: 14
                                color: trustRow.trusted ? root.accentPrimary : root.textDim

                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                        }

                        MouseArea {
                            id: trustArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleTrust(root.activeSettingsDevice)
                        }
                    }

                    //----------------ANC----------------
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: ancNote.implicitHeight + 16
                        radius: 12
                        color: root.bgTrack
                        opacity: 0.7

                        Text {
                            id: ancNote
                            anchors.fill: parent
                            anchors.margins: 8
                            text: "Управление шумоподавлением недоступно через системный Bluetooth: "
                                + "Nothing Ear использует закрытый протокол, а не стандартный BlueZ. "
                                + "Настраивается только в приложении Nothing X (Android/iOS)."
                            color: root.textDim
                            font.pixelSize: 10
                            wrapMode: Text.WordWrap
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            Layout.fillWidth: true
                            height: 34
                            radius: 12
                            color: doneArea.pressed ? Qt.darker(root.accentPrimary, 1.15)
                                   : doneArea.containsMouse ? root.accentSecondary : root.accentPrimary
                            scale: doneArea.pressed ? 0.96 : 1.0

                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                            Text {
                                anchors.centerIn: parent
                                text: "Готово"
                                color: root.bgPanel
                                font.pixelSize: 12
                                font.bold: true
                            }

                            MouseArea {
                                id: doneArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.applyRename()
                                    root.closeDeviceSettings()
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 34
                            radius: 12
                            color: settingsForgetArea.pressed ? Qt.darker(root.accentPrimary, 1.2)
                                   : settingsForgetArea.containsMouse ? root.accentSecondary : root.accentPrimary
                            scale: settingsForgetArea.pressed ? 0.96 : 1.0

                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

                            Text {
                                anchors.centerIn: parent
                                text: "Забыть"
                                color: root.bgPanel
                                font.pixelSize: 12
                            }

                            MouseArea {
                                id: settingsForgetArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.forgetDevice(root.activeSettingsDevice)
                            }
                        }
                    }
                }
            }
        }
    }
}
