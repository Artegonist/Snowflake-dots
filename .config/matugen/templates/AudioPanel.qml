import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Wayland

PanelWindow {
    id: root

    visible: false
    focusable: true
    WlrLayershell.keyboardFocus: root.expanded ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // ------------------------- STATE -------------------------

    property bool expanded: false
    property bool closing: false
    property string currentTab: "mixer" // "mixer" | "eq"
    property int savedWorkspaceId: -1

    // ------------------------- OPEN / CLOSE -------------------------

    function show() {
        root.closing = false
        if (!root.visible)
            root.visible = true
        root.savedWorkspaceId = Hyprland.focusedMonitor
            ? Hyprland.focusedMonitor.activeWorkspace.id
            : -1
        focusGrab.active = true
        root.mask = null
        root.expanded = true
    }

    function hide() {
        closeInternal(true)
    }

    function closeInternal(restoreWorkspace) {
        if (!root.expanded || root.closing)
            return
        root.closing = true
        focusGrab.active = false
        root.mask = emptyRegion
        root.expanded = false
        if (restoreWorkspace)
            returnToWorkspaceTimer.start()
    }

    function toggle() {
        if (root.expanded && !root.closing)
            hide()
        else
            show()
    }

    function openEqualizer() {
        root.currentTab = "eq"
        if (!root.expanded || root.closing)
            root.show()
    }

    Timer {
        id: returnToWorkspaceTimer
        interval: 30
        onTriggered: {
            if (root.savedWorkspaceId !== -1)
                Hyprland.dispatch("workspace " + root.savedWorkspaceId)
        }
    }

    Region {
        id: emptyRegion
        x: 0
        y: 0
        width: 0
        height: 0
    }

    // ------------------------- WINDOW GEOMETRY -------------------------

    anchors {
        top: true
        right: true
    }

    margins {
        top: 30
        right: 170
    }

    exclusionMode: ExclusionMode.Ignore

    color: "transparent"
    implicitWidth: 420
    implicitHeight: 560

    // ------------------------- COLORS -------------------------

    readonly property color accentPrimary: "{{theme.accent_primary.hex}}"
    readonly property color accentSecondary: "{{theme.accent_secondary.hex}}"
    readonly property color bgPanel: "{{theme.bg_panel_battery.hex}}"
    readonly property color bgTrack: "{{theme.bg_track.hex}}"
    readonly property color borderColor: "{{theme.accent_primary.hex}}"
    readonly property color separatorColor: Qt.rgba(1, 1, 1, 0.08)
    readonly property color textMain: "{{theme.text_main.hex}}"
    readonly property color textDim: "{{theme.text_dim.hex}}"
    readonly property color danger: "#c96a5a"
    readonly property color thumbColor: "{{theme.text_main.hex}}"

    HyprlandFocusGrab {
        id: focusGrab
        windows: [root]
        onCleared: root.closeInternal(false)
    }


    onVisibleChanged: {
        if (visible && !root.expanded)
            root.expanded = true
    }

    // ------------------------- PIPEWIRE -------------------------

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource, ...root.streamNodes, ...root.outputDevices, ...root.inputDevices]
    }

    readonly property var sinkNode: Pipewire.defaultAudioSink
    readonly property var sourceNode: Pipewire.defaultAudioSource

    readonly property var outputDevices: {
        const list = []
        for (const node of Pipewire.nodes.values) {
            if (!node.isStream && node.audio && node.isSink)
                list.push(node)
        }
        return list
    }

    readonly property var inputDevices: {
        const list = []
        for (const node of Pipewire.nodes.values) {
            if (!node.isStream && node.audio && !node.isSink)
                list.push(node)
        }
        return list
    }

    readonly property var sinkAudio: sinkNode ? sinkNode.audio : null
    readonly property var sourceAudio: sourceNode ? sourceNode.audio : null

    function volumesPreservingBalance(currentVolumes, targetAvg) {
        if (!currentVolumes || currentVolumes.length === 0) return currentVolumes
        const sum = currentVolumes.reduce((a, b) => a + b, 0)
        const currentAvg = sum / currentVolumes.length
        if (currentAvg <= 0.0001) {
            return currentVolumes.map(() => targetAvg)
        }
        const scale = targetAvg / currentAvg
        return currentVolumes.map(v => Math.max(0, Math.min(1, v * scale)))
    }

    readonly property string sinkFormatLabel: {
        const props = sinkNode ? sinkNode.properties : null
        if (!props) return ""

        const rawFormat = props["audio.format"] || props["api.alsa.pcm.format"] || props["format.dsp"] || ""
        let rawRate = props["audio.rate"] || props["api.alsa.rate"] || ""
        if (!rawRate && props["node.rate"]) {
            const parts = props["node.rate"].split("/")
            if (parts.length === 2) rawRate = parts[1]
        }
        if (!rawRate) return ""

        let bits = ""
        if (rawFormat.indexOf("S16") === 0) bits = "16bit"
        else if (rawFormat.indexOf("S24") === 0) bits = "24bit"
        else if (rawFormat.indexOf("S32") === 0 || rawFormat.indexOf("F32") === 0) bits = "32bit"
        else if (rawFormat) bits = rawFormat

        const rateNum = parseInt(rawRate)
        if (isNaN(rateNum)) return ""
        const rateLabel = rateNum % 1000 === 0
            ? (rateNum / 1000) + "kHz"
            : (rateNum / 1000).toFixed(1) + "kHz"

        return bits !== "" ? (bits + " / " + rateLabel) : rateLabel
    }

    readonly property var streamNodes: {
        const list = []
        for (const node of Pipewire.nodes.values) {
            if (node.isStream && node.audio && node.type === PwNodeType.AudioOutStream)
                list.push(node)
        }
        return list
    }

    // ------------------------- SLIDER 1 -------------------------

    component VolumeRow: ColumnLayout {
        id: row
        spacing: 4

        property var root
        property string label: ""
        property string icon: "󰕾"
        property var audio: null

        readonly property bool muted: audio ? audio.muted : false
        readonly property real volume: audio ? audio.volume : 0
        property real dragFrac: -1
        readonly property real frac: row.dragFrac >= 0 ? row.dragFrac : Math.max(0, Math.min(1, row.volume))

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                id: muteBtn
                width: 24
                height: 24
                radius: 6
                color: row.muted ? row.root.danger
                     : muteArea.containsMouse ? row.root.accentPrimary
                     : Qt.rgba(1, 1, 1, 0.06)
                scale: muteArea.pressed ? 0.85 : 1.0

                Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

                Text {
                    anchors.centerIn: parent
                    text: row.muted ? "󰝟" : row.icon
                    font.pixelSize: 13
                    color: (row.muted || muteArea.containsMouse) ? row.root.bgPanel : row.root.textMain

                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                MouseArea {
                    id: muteArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (row.audio)
                            row.audio.muted = !row.audio.muted
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: row.label
                color: row.root.textMain
                font.pixelSize: 13
                elide: Text.ElideRight
            }

            Text {
                text: row.muted ? "выкл" : Math.round(row.frac * 100) + "%"
                color: row.root.textDim
                font.pixelSize: 12
            }
        }

        Item {
            id: sliderTrack
            Layout.fillWidth: true
            Layout.preferredHeight: 18

            readonly property bool enabledSlider: row.audio !== null

            Rectangle {
                id: track
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 8
                radius: 4
                color: row.root.bgTrack
                opacity: sliderTrack.enabledSlider ? 1.0 : 0.4

                Rectangle {
                    id: fill
                    height: parent.height
                    radius: 4
                    width: track.width * row.frac

                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: row.root.accentSecondary }
                        GradientStop { position: 1.0; color: row.root.accentPrimary }
                    }

                    Behavior on width {
                        enabled: !dragArea.pressed
                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }
                }
            }

            Rectangle {
                id: thumb
                width: 14
                height: 14
                radius: 7
                color: row.root.thumbColor
                opacity: sliderTrack.enabledSlider ? 1.0 : 0.4
                scale: dragArea.pressed ? 1.15 : 1.0
                y: track.y + track.height / 2 - height / 2
                x: Math.max(0, Math.min(track.width - width, track.width * row.frac - width / 2))

                Behavior on x {
                    enabled: !dragArea.pressed
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                }
            }

            MouseArea {
                id: dragArea
                anchors.fill: parent
                anchors.margins: -4
                enabled: sliderTrack.enabledSlider
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true

                function setFromX(x) {
                    if (!row.audio) return
                    const local = x - 4
                    const frac = Math.max(0, Math.min(1, local / track.width))
                    row.dragFrac = frac
                    row.audio.muted = false
                    const vols = row.audio.volumes
                    if (vols && vols.length > 1) {
                        row.audio.volumes = row.root.volumesPreservingBalance(vols, frac)
                    } else {
                        row.audio.volume = frac
                    }
                }

                onPressed: (mouse) => setFromX(mouse.x)
                onPositionChanged: (mouse) => { if (pressed) setFromX(mouse.x) }
                onReleased: row.dragFrac = -1
                onCanceled: row.dragFrac = -1
                onWheel: (wheel) => {
                    if (!row.audio) return
                    const step = wheel.angleDelta.y > 0 ? 0.02 : -0.02
                    const target = Math.max(0, Math.min(1, row.audio.volume + step))
                    const vols = row.audio.volumes
                    if (vols && vols.length > 1) {
                        row.audio.volumes = row.root.volumesPreservingBalance(vols, target)
                    } else {
                        row.audio.volume = target
                    }
                }
            }
        }
    }

    // ------------------------- SLIDER 2 -------------------------

    component BalanceSlider: RowLayout {
        id: balancer
        spacing: 8

        property var root
        property var audio: null

        readonly property var channels: audio ? audio.channels : []
        readonly property int leftIndex: balancer.channels.indexOf(PwAudioChannel.FrontLeft)
        readonly property int rightIndex: balancer.channels.indexOf(PwAudioChannel.FrontRight)
        readonly property bool stereoAvailable: audio !== null && balancer.leftIndex !== -1 && balancer.rightIndex !== -1

        property real dragBalance: -2

        readonly property real balance: {
            if (balancer.dragBalance > -2) return balancer.dragBalance
            if (!balancer.stereoAvailable || !audio.volumes) return 0
            const l = audio.volumes[balancer.leftIndex]
            const r = audio.volumes[balancer.rightIndex]
            if (l + r <= 0) return 0
            return Math.max(-1, Math.min(1, (r - l) / Math.max(l, r)))
        }

        function applyBalance(value) {
            if (!balancer.stereoAvailable) return
            const b = Math.max(-1, Math.min(1, value))
            const base = audio.volume
            const newVolumes = audio.volumes.slice()
            newVolumes[balancer.leftIndex] = Math.max(0, Math.min(1, base * (1 - b)))
            newVolumes[balancer.rightIndex] = Math.max(0, Math.min(1, base * (1 + b)))
            audio.volumes = newVolumes
        }

        Text {
            text: "L"
            font.pixelSize: 12
            font.bold: balancer.balance < -0.05
            color: balancer.balance < -0.05 ? balancer.root.accentPrimary : balancer.root.textDim
        }

        Item {
            id: trackArea
            Layout.fillWidth: true
            Layout.preferredHeight: 20
            implicitHeight: 20
            opacity: balancer.stereoAvailable ? 1.0 : 0.4

            Rectangle {
                id: balTrack
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 6
                radius: 3
                color: balancer.root.bgTrack
                clip: true

                Rectangle {
                    id: balFill
                    anchors.verticalCenter: parent.verticalCenter
                    height: parent.height
                    radius: parent.radius

                    readonly property real halfWidth: balTrack.width / 2
                    readonly property real fillWidth: Math.abs(balancer.balance) * halfWidth

                    x: balancer.balance >= 0 ? balFill.halfWidth : balFill.halfWidth - balFill.fillWidth
                    width: balFill.fillWidth

                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: balancer.balance >= 0 ? balancer.root.accentSecondary : balancer.root.accentPrimary }
                        GradientStop { position: 1.0; color: balancer.balance >= 0 ? balancer.root.accentPrimary : balancer.root.accentSecondary }
                    }

                    Behavior on width {
                        enabled: !balDrag.pressed
                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }
                    Behavior on x {
                        enabled: !balDrag.pressed
                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }
                }
            }

            Rectangle {
                width: 2
                height: 10
                radius: 1
                color: balancer.root.separatorColor
                anchors.verticalCenter: balTrack.verticalCenter
                x: balTrack.width / 2 - width / 2
            }

            Rectangle {
                id: balThumb
                width: 14
                height: 14
                radius: 7
                color: balancer.root.thumbColor
                scale: balDrag.pressed ? 1.15 : 1.0
                y: balTrack.y + balTrack.height / 2 - height / 2
                x: Math.max(0, Math.min(balTrack.width - width, (balancer.balance + 1) / 2 * balTrack.width - width / 2))

                Behavior on x {
                    enabled: !balDrag.pressed
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }
                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
            }

            MouseArea {
                id: balDrag
                anchors.fill: parent
                anchors.margins: -4
                enabled: balancer.stereoAvailable
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                function setFromX(x) {
                    const local = x - 4
                    const frac = Math.max(0, Math.min(1, local / balTrack.width))
                    const b = frac * 2 - 1
                    balancer.dragBalance = b
                    balancer.applyBalance(b)
                }

                onPressed: (mouse) => setFromX(mouse.x)
                onPositionChanged: (mouse) => { if (pressed) setFromX(mouse.x) }
                onReleased: balancer.dragBalance = -2
                onCanceled: balancer.dragBalance = -2
                onDoubleClicked: {
                    balancer.dragBalance = -2
                    balancer.applyBalance(0)
                }
                onWheel: (wheel) => {
                    const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05
                    balancer.applyBalance(balancer.balance + step)
                }
            }
        }

        Text {
            text: "R"
            font.pixelSize: 12
            font.bold: balancer.balance > 0.05
            color: balancer.balance > 0.05 ? balancer.root.accentPrimary : balancer.root.textDim
        }
    }

    // ------------------------- SLIDER 3 -------------------------

    component EqBandSlider: ColumnLayout {
        id: bandItem
        spacing: 6
        Layout.alignment: Qt.AlignHCenter

        property var root
        property string freqLabel: ""
        property real value: 0
        readonly property real minGain: -12
        readonly property real maxGain: 12
        signal changed(real newValue)

        readonly property real range: bandItem.maxGain - bandItem.minGain
        readonly property real valueFracFromTop: range > 0 ? (bandItem.maxGain - bandItem.value) / range : 0.5
        readonly property real zeroFracFromTop: range > 0 ? (bandItem.maxGain - 0) / range : 0.5

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: (bandItem.value > 0 ? "+" : "") + bandItem.value.toFixed(0)
            color: bandItem.value === 0 ? bandItem.root.textDim : bandItem.root.accentPrimary
            font.pixelSize: 10
            font.bold: bandItem.value !== 0
        }

        Item {
            id: track
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 18
            Layout.preferredHeight: 170

            readonly property real barThickness: 8

            Rectangle {
                id: trackBg
                anchors.horizontalCenter: parent.horizontalCenter
                width: track.barThickness
                height: parent.height
                radius: track.barThickness / 2
                color: bandItem.root.bgTrack
            }

            Rectangle {
                width: track.barThickness
                height: 1
                anchors.horizontalCenter: parent.horizontalCenter
                y: bandItem.zeroFracFromTop * parent.height
                color: bandItem.root.separatorColor
            }

            Rectangle {
                id: fill
                width: track.barThickness
                anchors.horizontalCenter: parent.horizontalCenter
                radius: track.barThickness / 2

                readonly property real topFrac: Math.min(bandItem.valueFracFromTop, bandItem.zeroFracFromTop)
                readonly property real bottomFrac: Math.max(bandItem.valueFracFromTop, bandItem.zeroFracFromTop)

                y: fill.topFrac * track.height
                height: Math.max(0, (fill.bottomFrac - fill.topFrac) * track.height)

                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: bandItem.root.accentPrimary }
                    GradientStop { position: 1.0; color: bandItem.root.accentSecondary }
                }

                Behavior on height { enabled: !dragArea.pressed; NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                Behavior on y { enabled: !dragArea.pressed; NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            }

            Rectangle {
                id: thumb
                width: 14
                height: 14
                radius: 7
                color: bandItem.root.thumbColor
                scale: dragArea.pressed ? 1.15 : 1.0
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.max(0, Math.min(track.height - height, bandItem.valueFracFromTop * track.height - height / 2))

                Behavior on y { enabled: !dragArea.pressed; NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
            }

            MouseArea {
                id: dragArea
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true

                function setFromY(y) {
                    const local = y - 4
                    const frac = Math.max(0, Math.min(1, local / track.height))
                    const v = Math.round(bandItem.maxGain - frac * bandItem.range)
                    if (v !== bandItem.value)
                        bandItem.changed(v)
                }

                onPressed: (mouse) => setFromY(mouse.y)
                onPositionChanged: (mouse) => { if (pressed) setFromY(mouse.y) }
                onWheel: (wheel) => {
                    const step = wheel.angleDelta.y > 0 ? 1 : -1
                    const v = Math.max(bandItem.minGain, Math.min(bandItem.maxGain, bandItem.value + step))
                    if (v !== bandItem.value)
                        bandItem.changed(v)
                }
                onDoubleClicked: bandItem.changed(0)
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: bandItem.freqLabel
            color: bandItem.root.textMain
            font.pixelSize: 10
        }
    }

    component DeviceSelector: Item {
        id: selector

        property var root
        property string label: ""
        property string icon: "󰕾"
        property var devices: []
        property var currentNode: null

        signal deviceSelected(var node)

        property bool open: false

        Layout.fillWidth: true
        implicitHeight: dsLabel.height + 4 + headerBtn.height
        z: selector.open ? 100 : 1

        Connections {
            target: selector.root
            function onExpandedChanged() {
                if (!selector.root.expanded)
                    selector.open = false
            }
        }

        Text {
            id: dsLabel
            anchors.top: parent.top
            anchors.left: parent.left
            text: selector.label
            color: selector.root.textDim
            font.pixelSize: 11
        }

        Rectangle {
            id: headerBtn
            anchors.top: dsLabel.bottom
            anchors.topMargin: 4
            anchors.left: parent.left
            anchors.right: parent.right
            height: 32
            topLeftRadius: 6
            topRightRadius: 6
            bottomLeftRadius: selector.open ? 0 : 6
            bottomRightRadius: selector.open ? 0 : 6
            color: selector.root.bgTrack
            border.width: (headerArea.containsMouse && !selector.open) ? 1 : 0
            border.color: selector.root.accentPrimary

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 6

                Text {
                    text: selector.icon
                    color: selector.root.accentPrimary
                    font.pixelSize: 13
                }

                Text {
                    Layout.fillWidth: true
                    text: selector.currentNode
                        ? (selector.currentNode.nickname || selector.currentNode.description || selector.currentNode.name)
                        : "Устройство не выбрано"
                    color: selector.root.textMain
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }

                Text {
                    text: selector.open ? "\u25B4" : "\u25BE"
                    color: selector.root.textDim
                    font.pixelSize: 10
                }
            }

            MouseArea {
                id: headerArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: selector.open = !selector.open
            }
        }

        Rectangle {
            id: dropdown
            anchors.top: headerBtn.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            topLeftRadius: 0
            topRightRadius: 0
            bottomLeftRadius: 6
            bottomRightRadius: 6
            color: selector.root.bgTrack
            clip: true
            visible: height > 0
            height: selector.open ? Math.min(list.contentHeight, 176) : 0
            Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

            ListView {
                id: list
                anchors.fill: parent
                model: selector.devices
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    width: list.width
                    height: 30

                    readonly property bool isCurrent: selector.currentNode && modelData.id === selector.currentNode.id

                    color: itemArea.containsMouse ? selector.root.accentSecondary
                         : (isCurrent ? Qt.rgba(1, 1, 1, 0.06) : "transparent")

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: Text.AlignVCenter
                        text: modelData.nickname || modelData.description || modelData.name
                        color: parent.isCurrent ? selector.root.accentPrimary : selector.root.textMain
                        font.pixelSize: 12
                        font.bold: parent.isCurrent
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        id: itemArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            selector.deviceSelected(modelData)
                            selector.open = false
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.top: headerBtn.top
            anchors.left: headerBtn.left
            anchors.right: headerBtn.right
            anchors.bottom: dropdown.bottom
            color: "transparent"
            radius: 6
            border.width: selector.open ? 1 : 0
            border.color: selector.root.accentPrimary
            visible: selector.open
        }
    }

    // ------------------------- MIXER -------------------------

    component MixerPage: Item {
        id: page
        property var root

        Connections {
            target: outputSelector
            function onOpenChanged() {
                if (outputSelector.open) inputSelector.open = false
            }
        }

        Connections {
            target: inputSelector
            function onOpenChanged() {
                if (inputSelector.open) outputSelector.open = false
            }
        }

        RowLayout {
            id: deviceRow
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 10
            z: (outputSelector.open || inputSelector.open) ? 100 : 1

            DeviceSelector {
                id: outputSelector
                Layout.fillWidth: true
                root: page.root
                label: "Устройство вывода"
                icon: "󰕾"
                devices: page.root.outputDevices
                currentNode: page.root.sinkNode
                onDeviceSelected: (node) => { Pipewire.preferredDefaultAudioSink = node }
            }

            DeviceSelector {
                id: inputSelector
                Layout.fillWidth: true
                root: page.root
                label: "Устройство ввода"
                icon: "󰍬"
                devices: page.root.inputDevices
                currentNode: page.root.sourceNode
                onDeviceSelected: (node) => { Pipewire.preferredDefaultAudioSource = node }
            }
        }

        MouseArea {
            id: outsideCatcher
            anchors.fill: parent
            z: 50
            enabled: outputSelector.open || inputSelector.open
            onPressed: (mouse) => {
                outputSelector.open = false
                inputSelector.open = false
                mouse.accepted = true
            }
        }

        ColumnLayout {
            anchors.top: deviceRow.bottom
            anchors.topMargin: 14
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: 14

            VolumeRow {
                Layout.fillWidth: true
                root: page.root
                label: "Выход: " + (page.root.sinkNode ? page.root.sinkNode.description : "—")
                icon: "󰕾"
                audio: page.root.sinkAudio
            }

            VolumeRow {
                Layout.fillWidth: true
                root: page.root
                label: "Микрофон: " + (page.root.sourceNode ? page.root.sourceNode.description : "—")
                icon: "󰍬"
                audio: page.root.sourceAudio
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: page.root.separatorColor
            }

            Text {
                text: "Приложения"
                color: page.root.textDim
                font.pixelSize: 12
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: appsColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: appsColumn
                    width: parent.width
                    spacing: 10

                    Repeater {
                        model: page.root.streamNodes

                        delegate: VolumeRow {
                            Layout.fillWidth: true
                            root: page.root
                            label: modelData.properties["application.name"] || modelData.description || "Приложение"
                            icon: "󰎈"
                            audio: modelData.audio
                        }
                    }

                    Text {
                        visible: page.root.streamNodes.length === 0
                        text: "Нет активных потоков"
                        color: page.root.textDim
                        font.pixelSize: 12
                        font.italic: true
                    }
                }
            }
        }
    }

    // ------------------------- EQ -------------------------

    component EqPage: Item {
        id: eqPage
        property var root

        readonly property var bandFreqs: [60, 170, 310, 600, 1000, 3000, 6000, 12000]
        readonly property var bandLabels: ["60", "170", "310", "600", "1k", "3k", "6k", "12k"]
        property var bandGains: [0, 0, 0, 0, 0, 0, 0, 0]
        property string activePreset: "Плоский"

        property var customPresets: [null, null, null, null]
        property var customPresetNames: ["", "", "", ""]
        property bool saveMode: false
        property bool stateReady: false

        onBandGainsChanged: if (eqPage.stateReady) eqState.bandGains = eqPage.bandGains
        onActivePresetChanged: if (eqPage.stateReady) eqState.activePreset = eqPage.activePreset
        onCustomPresetsChanged: if (eqPage.stateReady) eqState.customPresets = eqPage.customPresets
        onCustomPresetNamesChanged: if (eqPage.stateReady) eqState.customPresetNames = eqPage.customPresetNames

        FileView {
            id: stateFile
            path: Quickshell.stateDir + "/audio-eq-state.json"
            watchChanges: true
            onFileChanged: reload()
            onAdapterUpdated: writeAdapter()

            onLoaded: {
                eqPage.bandGains = eqState.bandGains
                eqPage.activePreset = eqState.activePreset
                eqPage.customPresets = eqState.customPresets
                eqPage.customPresetNames = eqState.customPresetNames
                eqPage.stateReady = true
                eqPage.pushToBackend()
            }

            onLoadFailed: (error) => {
                eqPage.stateReady = true
            }

            JsonAdapter {
                id: eqState
                property var bandGains: [0, 0, 0, 0, 0, 0, 0, 0]
                property string activePreset: "Плоский"
                property var customPresets: [null, null, null, null]
                property var customPresetNames: ["", "", "", ""]
            }
        }

        readonly property var presets: ({
            "Плоский":  [0, 0, 0, 0, 0, 0, 0, 0],
            "Бас+":     [6, 5, 3, 1, 0, 0, 0, 0],
            "Верхи+":   [0, 0, 0, 0, 0, 2, 4, 6],
            "Вокал":    [-3, -2, -1, 0, 3, 2, 0, -1],
            "Поп":      [-1, 0, 1, 1, 2, 2, 3, 2],
            "Рок":      [4, 3, -1, -2, -1, 1, 3, 3],
            "Джаз":     [2, 1, 0, -1, 0, 1, 2, 3],
            "Классика": [2, 1, 0, 0, 0, 0, 1, 2]
        })

        function applyPreset(name) {
            const values = eqPage.presets[name]
            if (!values) return
            eqPage.bandGains = values.slice()
            eqPage.activePreset = name
            eqPage.saveMode = false
            applyTimer.restart()
        }

        function customPresetName(i) {
            const custom = eqPage.customPresetNames[i]
            return (custom && custom.length > 0) ? custom : ("Польз. " + (i + 1))
        }

        function renameCustomPreset(i, newName) {
            const trimmed = newName.trim()
            const oldName = eqPage.customPresetName(i)
            const arr = eqPage.customPresetNames.slice()
            arr[i] = trimmed
            eqPage.customPresetNames = arr
            if (eqPage.activePreset === oldName) {
                eqPage.activePreset = eqPage.customPresetName(i)
            }
        }

        function applyCustomPreset(i) {
            const values = eqPage.customPresets[i]
            if (!values) return
            eqPage.bandGains = values.slice()
            eqPage.activePreset = eqPage.customPresetName(i)
            applyTimer.restart()
        }

        function saveCustomPreset(i) {
            const arr = eqPage.customPresets.slice()
            arr[i] = eqPage.bandGains.slice()
            eqPage.customPresets = arr
            eqPage.activePreset = eqPage.customPresetName(i)
            eqPage.saveMode = false
        }

        function onCustomChipClicked(i) {
            if (eqPage.saveMode) {
                eqPage.saveCustomPreset(i)
            } else if (eqPage.customPresets[i]) {
                eqPage.applyCustomPreset(i)
            }
        }

        function resetBands() {
            for (let i = 0; i < eqPage.customPresets.length; i++) {
                if (eqPage.activePreset === eqPage.customPresetName(i)) {
                    const arr = eqPage.customPresets.slice()
                    arr[i] = null
                    eqPage.customPresets = arr
                    break
                }
            }

            eqPage.bandGains = [0, 0, 0, 0, 0, 0, 0, 0]
            eqPage.activePreset = ""
            eqPage.saveMode = false
            applyTimer.restart()
        }

        function onBandDragged(index, value) {
            const arr = eqPage.bandGains.slice()
            arr[index] = value
            eqPage.bandGains = arr
            eqPage.activePreset = ""
            applyTimer.restart()
        }

        Timer {
            id: applyTimer
            interval: 300
            onTriggered: eqPage.pushToBackend()
        }

        Process {
            id: backendProcess
        }

        function bandType(index, count) {
            if (index === 0) return "Low Shelf"
            if (index === count - 1) return "High Shelf"
            return "Bell"
        }

        function buildBandEntry(index) {
            const freq = eqPage.bandFreqs[index]
            const gain = eqPage.bandGains[index]
            const type = eqPage.bandType(index, eqPage.bandFreqs.length)
            return '        "band' + index + '": {' +
                ' "type": "' + type + '",' +
                ' "mode": "RLC (BT)",' +
                ' "slope": "x1",' +
                ' "solo": false,' +
                ' "mute": false,' +
                ' "frequency": ' + freq.toFixed(1) + ',' +
                ' "gain": ' + gain.toFixed(1) + ',' +
                ' "q": 1.0,' +
                ' "width": 4.0' +
                ' }'
        }

        function pushToBackend() {
            const count = eqPage.bandFreqs.length
            const entries = []
            for (let i = 0; i < count; i++)
                entries.push(eqPage.buildBandEntry(i))
            const bandsBlock = entries.join(',\n')

            const json =
                '{\n' +
                '  "output": {\n' +
                '    "blocklist": [],\n' +
                '    "plugins_order": ["equalizer"],\n' +
                '    "equalizer": {\n' +
                '      "input-gain": 0.0,\n' +
                '      "output-gain": 0.0,\n' +
                '      "mode": "IIR",\n' +
                '      "num-bands": ' + count + ',\n' +
                '      "pitch-left": 0.0,\n' +
                '      "pitch-right": 0.0,\n' +
                '      "split-channels": false,\n' +
                '      "balance": 0.0,\n' +
                '      "left": {\n' + bandsBlock + '\n      },\n' +
                '      "right": {\n' + bandsBlock + '\n      }\n' +
                '    }\n' +
                '  }\n' +
                '}\n'

            const script =
                'mkdir -p "$HOME/.config/easyeffects/output" && ' +
                'tmp="$(mktemp "$HOME/.config/easyeffects/output/.quickshell.json.XXXXXX")" && ' +
                'cat > "$tmp" <<\'QSEOF\'\n' +
                json + 'QSEOF\n' +
                'mv -f "$tmp" "$HOME/.config/easyeffects/output/quickshell.json" && ' +
                'easyeffects -l quickshell'

            if (backendProcess.running)
                backendProcess.running = false
            backendProcess.command = ["bash", "-c", script]
            backendProcess.running = true
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 12

            Text {
                text: "Пресеты"
                color: eqPage.root.textDim
                font.pixelSize: 12
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 4
                rowSpacing: 8
                columnSpacing: 8

                Repeater {
                    model: Object.keys(eqPage.presets)

                    delegate: Rectangle {
                        id: chip
                        Layout.fillWidth: true
                        property string presetName: modelData
                        property bool active: eqPage.activePreset === presetName
                        property bool hovered: false
                        radius: 8
                        height: 32
                        color: chip.active ? eqPage.root.accentPrimary
                             : chip.hovered ? eqPage.root.bgTrack
                             : Qt.darker(eqPage.root.bgTrack, 1.08)
                        border.width: 1
                        border.color: chip.active ? eqPage.root.accentPrimary : eqPage.root.separatorColor
                        scale: chipArea.pressed ? 0.93 : 1.0

                        Behavior on color { ColorAnimation { duration: 100 } }
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

                        Text {
                            id: chipText
                            anchors.centerIn: parent
                            text: chip.presetName
                            font.pixelSize: 12
                            color: chip.active ? eqPage.root.bgPanel : eqPage.root.textMain
                        }

                        MouseArea {
                            id: chipArea
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onEntered: chip.hovered = true
                            onExited: chip.hovered = false
                            onClicked: eqPage.applyPreset(chip.presetName)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: 4

                    delegate: Rectangle {
                        id: customChip
                        required property int index
                        property bool filled: eqPage.customPresets[customChip.index] !== null
                        property bool active: eqPage.activePreset === eqPage.customPresetName(customChip.index)
                        property bool hovered: false
                        property bool editing: false
                        Layout.fillWidth: true
                        radius: 8
                        height: 32
                        color: customChip.active ? eqPage.root.accentPrimary
                             : customChip.hovered ? eqPage.root.bgTrack
                             : Qt.darker(eqPage.root.bgTrack, 1.08)
                        border.width: (eqPage.saveMode || customChip.editing) ? 2 : 1
                        border.color: (eqPage.saveMode || customChip.editing) ? eqPage.root.accentPrimary
                                    : customChip.active ? eqPage.root.accentPrimary
                                    : eqPage.root.separatorColor
                        opacity: (!customChip.filled && !eqPage.saveMode) ? 0.55 : 1.0
                        scale: customChipArea.pressed ? 0.93 : 1.0

                        Behavior on color { ColorAnimation { duration: 100 } }
                        Behavior on opacity { NumberAnimation { duration: 100 } }
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

                        function commitRename() {
                            eqPage.renameCustomPreset(customChip.index, renameField.text)
                            customChip.editing = false
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !customChip.editing
                            text: eqPage.customPresetName(customChip.index)
                            font.pixelSize: 12
                            color: customChip.active ? eqPage.root.bgPanel : eqPage.root.textMain
                        }

                        TextInput {
                            id: renameField
                            anchors.centerIn: parent
                            width: parent.width - 10
                            visible: customChip.editing
                            font.pixelSize: 12
                            color: customChip.active ? eqPage.root.bgPanel : eqPage.root.textMain
                            horizontalAlignment: TextInput.AlignHCenter
                            clip: true
                            selectByMouse: true

                            onVisibleChanged: if (visible) {
                                renameField.text = eqPage.customPresetName(customChip.index)
                                renameField.forceActiveFocus()
                                renameField.selectAll()
                            }

                            onAccepted: customChip.commitRename()
                            onActiveFocusChanged: if (!activeFocus && customChip.editing) customChip.commitRename()

                            Keys.onEscapePressed: customChip.editing = false
                        }

                        MouseArea {
                            id: customChipArea
                            anchors.fill: parent
                            enabled: !customChip.editing
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onEntered: customChip.hovered = true
                            onExited: customChip.hovered = false
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.LeftButton)
                                    eqPage.onCustomChipClicked(customChip.index)
                            }
                            onDoubleClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton)
                                    customChip.editing = true
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: eqPage.root.separatorColor
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: true
                spacing: 22

                Repeater {
                    model: eqPage.bandFreqs.length

                    delegate: EqBandSlider {
                        required property int index
                        root: eqPage.root
                        freqLabel: eqPage.bandLabels[index]
                        value: eqPage.bandGains[index]
                        onChanged: (v) => eqPage.onBandDragged(index, v)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    id: resetToggle
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: 8
                    color: resetArea.pressed ? eqPage.root.accentPrimary
                         : resetArea.containsMouse ? eqPage.root.bgTrack
                         : Qt.darker(eqPage.root.bgTrack, 1.08)
                    border.width: 1
                    border.color: resetArea.pressed ? eqPage.root.accentPrimary : eqPage.root.separatorColor
                    scale: resetArea.pressed ? 0.9 : 1.0

                    Behavior on color { ColorAnimation { duration: 100 } }
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

                    Text {
                        anchors.centerIn: parent
                        text: "↺"
                        font.pixelSize: 16
                        color: resetArea.pressed ? eqPage.root.bgPanel : eqPage.root.textMain
                    }

                    MouseArea {
                        id: resetArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: eqPage.resetBands()
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    id: saveToggle
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: 8
                    color: eqPage.saveMode ? eqPage.root.accentPrimary
                         : saveArea.containsMouse ? eqPage.root.bgTrack
                         : Qt.darker(eqPage.root.bgTrack, 1.08)
                    border.width: 1
                    border.color: eqPage.saveMode ? eqPage.root.accentPrimary : eqPage.root.separatorColor
                    scale: saveArea.pressed ? 0.9 : 1.0

                    Behavior on color { ColorAnimation { duration: 100 } }
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

                    Text {
                        anchors.centerIn: parent
                        text: "\u{1F4BE}"
                        font.pixelSize: 14
                        color: eqPage.saveMode ? eqPage.root.bgPanel : eqPage.root.textMain
                    }

                    MouseArea {
                        id: saveArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: eqPage.saveMode = !eqPage.saveMode
                    }
                }
            }

        }
    }

    // ------------------------- CARD -------------------------

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

        SequentialAnimation {
            id: openAnim

            ScriptAction {
                script: {
                    headerSection.opacity = 0
                    headerSectionTranslate.y = -12
                    contentSection.opacity = 0
                    contentSectionTranslate.y = -12
                }
            }

            ParallelAnimation {
                NumberAnimation { target: card; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
                NumberAnimation { target: card; property: "scale"; to: 1; duration: 190; easing.type: Easing.OutBack; easing.overshoot: 1.1 }

                SequentialAnimation {
                    PauseAnimation { duration: 35 }
                    ParallelAnimation {
                        NumberAnimation { target: headerSection; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
                        NumberAnimation { target: headerSectionTranslate; property: "y"; to: 0; duration: 170; easing.type: Easing.OutCubic }
                    }
                }

                SequentialAnimation {
                    PauseAnimation { duration: 70 }
                    ParallelAnimation {
                        NumberAnimation { target: contentSection; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
                        NumberAnimation { target: contentSectionTranslate; property: "y"; to: 0; duration: 170; easing.type: Easing.OutCubic }
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

        focus: true
        Keys.onEscapePressed: root.hide()

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            // ------------------------- HEADER -------------------------

            ColumnLayout {
                id: headerSection
                Layout.fillWidth: true
                spacing: 14
                opacity: 0

                transform: Translate {
                    id: headerSectionTranslate
                    y: -12
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    BalanceSlider {
                        Layout.fillWidth: true
                        root: root
                        audio: root.sinkAudio
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: root.separatorColor
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        id: mixerTab
                        Layout.fillWidth: true
                        height: 30
                        radius: 6
                        color: root.currentTab === "mixer" ? root.accentPrimary
                             : mixerTabArea.containsMouse ? root.accentSecondary
                             : root.bgTrack
                        scale: mixerTabArea.pressed ? 0.95 : 1.0
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

                        Text {
                            anchors.centerIn: parent
                            text: "Микшер"
                            font.pixelSize: 12
                            font.bold: root.currentTab === "mixer"
                            color: root.currentTab === "mixer" ? root.bgPanel : root.textDim
                        }

                        MouseArea {
                            id: mixerTabArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.currentTab = "mixer"
                        }
                    }

                    Rectangle {
                        id: eqTab
                        Layout.fillWidth: true
                        height: 30
                        radius: 6
                        color: root.currentTab === "eq" ? root.accentPrimary
                             : eqTabArea.containsMouse ? root.accentSecondary
                             : root.bgTrack
                        scale: eqTabArea.pressed ? 0.95 : 1.0
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

                        Text {
                            anchors.centerIn: parent
                            text: "Эквалайзер"
                            font.pixelSize: 12
                            font.bold: root.currentTab === "eq"
                            color: root.currentTab === "eq" ? root.bgPanel : root.textDim
                        }

                        MouseArea {
                            id: eqTabArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.currentTab = "eq"
                        }
                    }
                }
            }

            // ------------------------- PAGES -------------------------

            Item {
                id: contentSection
                Layout.fillWidth: true
                Layout.fillHeight: true
                opacity: 0

                transform: Translate {
                    id: contentSectionTranslate
                    y: -12
                }

                MixerPage {
                    anchors.fill: parent
                    root: root
                    opacity: root.currentTab === "mixer" ? 1 : 0
                    enabled: root.currentTab === "mixer"
                    y: root.currentTab === "mixer" ? 0 : -10

                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }

                EqPage {
                    anchors.fill: parent
                    root: root
                    opacity: root.currentTab === "eq" ? 1 : 0
                    enabled: root.currentTab === "eq"
                    y: root.currentTab === "eq" ? 0 : 10

                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
            }
        }

        // ------------------------- FORMAT BADGE -------------------------

        Rectangle {
            id: formatBadge
            visible: root.sinkFormatLabel !== ""
            anchors.left: card.left
            anchors.bottom: card.bottom
            anchors.leftMargin: 14
            anchors.bottomMargin: -9
            radius: 5
            color: root.bgPanel
            border.width: 1
            border.color: root.separatorColor
            width: formatBadgeText.implicitWidth + 14
            height: formatBadgeText.implicitHeight + 8

            Text {
                id: formatBadgeText
                anchors.centerIn: parent
                text: root.sinkFormatLabel
                color: root.textDim
                font.pixelSize: 10
            }
        }
    }
}
