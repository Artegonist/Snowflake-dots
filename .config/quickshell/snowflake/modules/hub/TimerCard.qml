import QtQuick
import QtQuick.Layouts
import Quickshell.Io

ColumnLayout {
    id: root

    required property var hub

    spacing: 12

    // ------------------------- SETTINGS -------------------------
    readonly property var defaultPresets: [300, 600, 900, 1500]
    readonly property int maxSeconds: 99 * 3600 + 59 * 60 + 59
    readonly property int maxPresets: 5
    property var presets: root.defaultPresets
    property bool notify: true
    property string mode: "timer"

    readonly property bool isStopwatch: root.mode === "stopwatch"
    readonly property string title: root.isStopwatch ? "Секундомер" : "Таймер"
    readonly property bool running: root.isStopwatch ? root.swRunning : root.isRunning
    readonly property string statusText: root.isStopwatch
        ? (root.swRunning ? "идёт" : root.swElapsed > 0 ? "пауза" : "")
        : (root.isRunning ? "идёт"
           : root.finished ? "готово"
           : root.remainingSeconds < root.totalSeconds ? "пауза" : "")

    JsonFile {
        id: settingsFile
        path: root.hub.dataDir + "/timer.json"
        legacyPath: ".config/hub-module/timer.json"
        onLoaded: function(s) {
            if (s) {
                if (Array.isArray(s.presetsSec)) {
                    const list = root.cleanPresets(s.presetsSec)
                    if (list.length > 0) root.presets = list
                } else if (Array.isArray(s.presets)) {
                    const list = root.cleanPresets(s.presets.map(v => Number(v) * 60))
                    if (list.length > 0) root.presets = list
                }
                if (typeof s.notify === "boolean") root.notify = s.notify
                if (s.mode === "timer" || s.mode === "stopwatch") root.mode = s.mode
            }
            if (!root.isRunning && !root.finished && root.remainingSeconds === root.totalSeconds)
                root.setDuration(root.presets[0])
        }
    }

    Component.onCompleted: settingsFile.load()

    function saveSettings() {
        settingsFile.save({ presetsSec: root.presets, notify: root.notify, mode: root.mode })
    }

    function cleanPresets(list) {
        const out = []
        for (const v of list) {
            const n = Math.round(Number(v))
            if (n >= 1 && n <= root.maxSeconds && out.indexOf(n) < 0) out.push(n)
        }
        return out.sort((a, b) => a - b).slice(0, root.maxPresets)
    }

    function addPreset(seconds) {
        const n = Math.round(Number(seconds))
        if (!(n >= 1)) return "Задайте время больше нуля"
        if (n > root.maxSeconds) return "Не больше 99 часов"
        if (root.presets.indexOf(n) >= 0) return "Такой пресет уже есть"
        if (root.presets.length >= root.maxPresets) return "Не больше " + root.maxPresets + " пресетов"
        root.presets = root.cleanPresets(root.presets.concat([n]))
        root.saveSettings()
        return ""
    }

    function removePreset(index) {
        if (root.presets.length <= 1) return "Нужен хотя бы один пресет"
        const list = root.presets.slice()
        list.splice(index, 1)
        root.presets = list
        root.saveSettings()
        return ""
    }

    function setNotify(on) {
        root.notify = on
        root.saveSettings()
    }

    function setMode(m) {
        if (m === root.mode) return
        root.editing = false
        root.mode = m
        root.saveSettings()
    }

    function pad(n) { return n < 10 ? "0" + n : "" + n }

    function presetLabel(sec, full) {
        const h = Math.floor(sec / 3600)
        const m = Math.floor((sec % 3600) / 60)
        const s = sec % 60
        const parts = []
        if (h > 0) parts.push(h + (full ? " ч" : "ч"))
        if (m > 0) parts.push(m + (full ? " мин" : "м"))
        if (s > 0) parts.push(s + (full ? " сек" : "с"))
        if (!full && parts.length > 2) return root.formatDuration(sec)
        return parts.join(" ")
    }

    // ------------------------- TIMER -------------------------
    property int totalSeconds: 300
    property int remainingSeconds: root.totalSeconds
    property bool isRunning: false
    property bool finished: false
    property double endTime: 0
    property bool editing: false

    readonly property real progress: root.totalSeconds > 0 ? root.remainingSeconds / root.totalSeconds : 0
    readonly property bool isCustom: root.presets.indexOf(root.totalSeconds) < 0

    function formatDuration(sec) {
        const h = Math.floor(sec / 3600)
        const m = Math.floor((sec % 3600) / 60)
        const s = sec % 60
        return h > 0 ? h + ":" + pad(m) + ":" + pad(s) : pad(m) + ":" + pad(s)
    }

    function secondsLeft() {
        return Math.max(0, Math.ceil((root.endTime - Date.now()) / 1000))
    }

    function setDuration(seconds) {
        tickTimer.stop()
        root.isRunning = false
        root.finished = false
        root.editing = false
        root.totalSeconds = seconds
        root.remainingSeconds = seconds
    }

    function toggleRun() {
        if (root.isRunning) {
            root.remainingSeconds = root.secondsLeft()
            tickTimer.stop()
            root.isRunning = false
            return
        }
        if (root.remainingSeconds <= 0)
            root.remainingSeconds = root.totalSeconds
        root.finished = false
        root.editing = false
        root.endTime = Date.now() + root.remainingSeconds * 1000
        root.isRunning = true
        tickTimer.start()
    }

    function reset() {
        root.setDuration(root.totalSeconds)
    }

    function openEditor() {
        if (root.isRunning) return
        hourInput.text = String(Math.floor(root.totalSeconds / 3600))
        minInput.text = root.pad(Math.floor((root.totalSeconds % 3600) / 60))
        secInput.text = root.pad(root.totalSeconds % 60)
        root.editing = true
        Qt.callLater(function() {
            minInput.input.forceActiveFocus()
            minInput.input.selectAll()
        })
    }

    function applyEditor() {
        const h = parseInt(hourInput.text, 10) || 0
        const m = parseInt(minInput.text, 10) || 0
        const s = parseInt(secInput.text, 10) || 0
        const total = Math.min(99, h) * 3600 + Math.min(59, m) * 60 + Math.min(59, s)
        if (total <= 0) {
            minInput.input.forceActiveFocus()
            return
        }
        root.setDuration(total)
    }

    Timer {
        id: tickTimer
        interval: 250
        repeat: true
        onTriggered: {
            const left = root.secondsLeft()
            if (left !== root.remainingSeconds)
                root.remainingSeconds = left
            if (left <= 0) {
                tickTimer.stop()
                root.isRunning = false
                root.finished = true
                if (root.notify)
                    notifyProc.running = true
            }
        }
    }

    Process {
        id: notifyProc
        command: ["sh", "-c",
            "command -v notify-send >/dev/null 2>&1 && notify-send -a Hub -i alarm-symbolic \"Таймер\" \"Время вышло · $1\"",
            "sh", root.formatDuration(root.totalSeconds)]
    }

    // ------------------------- STOPWATCH -------------------------
    property bool swRunning: false
    property double swStart: 0
    property double swAccum: 0
    property double swNow: 0
    property var laps: []

    readonly property double swElapsed: root.swAccum + (root.swRunning ? Math.max(0, root.swNow - root.swStart) : 0)

    function formatSw(ms) {
        const t = Math.floor(ms / 100)
        const d = t % 10
        const s = Math.floor(t / 10) % 60
        const m = Math.floor(t / 600) % 60
        const h = Math.floor(t / 36000)
        return h > 0 ? h + ":" + pad(m) + ":" + pad(s) : pad(m) + ":" + pad(s) + "." + d
    }

    function swToggle() {
        const now = Date.now()
        if (root.swRunning) {
            root.swAccum += now - root.swStart
            root.swRunning = false
        } else {
            root.swStart = now
            root.swNow = now
            root.swRunning = true
        }
    }

    function swLap() {
        if (!root.swRunning) return
        root.swNow = Date.now()
        const total = root.swElapsed
        const prev = root.laps.length > 0 ? root.laps[root.laps.length - 1].total : 0
        root.laps = root.laps.concat([{ n: root.laps.length + 1, total: total, split: total - prev }])
    }

    function swReset() {
        root.swRunning = false
        root.swAccum = 0
        root.swStart = 0
        root.swNow = 0
        root.laps = []
    }

    Timer {
        interval: 50
        repeat: true
        running: root.swRunning && root.isStopwatch && root.hub.expanded
        triggeredOnStart: true
        onTriggered: root.swNow = Date.now()
    }

    // ------------------------- MODE SWITCH -------------------------
    Rectangle {
        id: modeSwitch
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: 236
        implicitHeight: 28
        radius: 14
        color: root.hub.bgTrack

        Rectangle {
            x: 3 + (root.isStopwatch ? (modeSwitch.width - 6) / 2 : 0)
            y: 3
            width: (modeSwitch.width - 6) / 2
            height: modeSwitch.height - 6
            radius: height / 2
            color: root.hub.accentPrimary

            Behavior on x { Anim {} }
        }

        Row {
            x: 3
            y: 3

            Repeater {
                model: [{ id: "timer", title: "Таймер" }, { id: "stopwatch", title: "Секундомер" }]

                delegate: Item {
                    id: modeTab
                    required property var modelData
                    readonly property bool current: root.mode === modeTab.modelData.id

                    width: (modeSwitch.width - 6) / 2
                    height: modeSwitch.height - 6

                    Text {
                        anchors.centerIn: parent
                        text: modeTab.modelData.title
                        font.pixelSize: 12
                        font.bold: modeTab.current
                        color: modeTab.current ? root.hub.bgPanel : (modeArea.containsMouse ? root.hub.textMain : root.hub.textDim)

                        Behavior on color { ColorAnimation { duration: 160 } }
                    }

                    MouseArea {
                        id: modeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setMode(modeTab.modelData.id)
                    }
                }
            }
        }
    }

    // ------------------------- DIGITS -------------------------
    Item {
        Layout.fillWidth: true
        implicitHeight: timeLabel.implicitHeight

        Text {
            id: timeLabel
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.isStopwatch ? root.formatSw(root.swElapsed) : root.formatDuration(root.remainingSeconds)
            color: !root.isStopwatch && root.finished ? root.hub.accentPrimary
                 : (!root.isStopwatch && timeHover.hovered && !root.isRunning) ? root.hub.accentSecondary
                 : root.hub.textMain
            font.pixelSize: 44
            font.bold: true
            font.family: root.hub.monoFont

            Behavior on color { ColorAnimation { duration: 180 } }

            SequentialAnimation on opacity {
                running: !root.isStopwatch && root.finished && root.hub.expanded
                loops: Animation.Infinite
                NumberAnimation { to: 0.35; duration: 420; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 420; easing.type: Easing.InOutSine }
                onRunningChanged: {
                    if (!running)
                        timeLabel.opacity = 1
                }
            }

            HoverHandler {
                id: timeHover
                enabled: !root.isStopwatch && !root.isRunning
                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                enabled: !root.isStopwatch && !root.isRunning
                onTapped: root.openEditor()
            }
        }
    }

    // ------------------------- PROGRESS -------------------------
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 6
        radius: 3
        color: root.hub.bgTrack

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * (root.isStopwatch ? (root.swElapsed % 60000) / 60000 : root.progress)
            radius: 3

            Behavior on width {
                enabled: !root.isStopwatch
                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
            }

            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: root.hub.accentSecondary }
                GradientStop { position: 1.0; color: root.hub.accentPrimary }
            }
        }
    }

    // ------------------------- PRESETS / EDITOR / LAPS -------------------------
    Item {
        Layout.fillWidth: true
        implicitHeight: 32

        RowLayout {
            anchors.fill: parent
            spacing: 8
            visible: !root.isStopwatch && !root.editing

            Repeater {
                model: root.presets

                delegate: Rectangle {
                    id: presetBtn
                    required property int modelData
                    readonly property bool isActive: root.totalSeconds === presetBtn.modelData

                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: 32
                    radius: 16
                    color: presetBtn.isActive ? root.hub.accentPrimary
                         : presetArea.containsMouse ? root.hub.accentSecondary : root.hub.bgTrack
                    scale: presetArea.pressed ? 0.93 : 1.0

                    Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

                    Text {
                        anchors.centerIn: parent
                        text: root.presetLabel(presetBtn.modelData, false)
                        color: presetBtn.isActive ? root.hub.bgPanel : root.hub.textMain
                        font.pixelSize: 13
                        font.bold: presetBtn.isActive
                    }

                    MouseArea {
                        id: presetArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setDuration(presetBtn.modelData)
                    }
                }
            }

            Rectangle {
                id: customBtn
                Layout.fillWidth: true
                Layout.preferredWidth: 1.3
                implicitHeight: 32
                radius: 16
                color: root.isCustom ? root.hub.accentPrimary
                     : customArea.containsMouse ? root.hub.accentSecondary : root.hub.bgTrack
                scale: customArea.pressed ? 0.93 : 1.0

                Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

                Row {
                    anchors.centerIn: parent
                    spacing: 5

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰏫"
                        font.family: root.hub.iconFont
                        font.pixelSize: 13
                        color: root.isCustom ? root.hub.bgPanel : root.hub.textMain
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.isCustom ? root.formatDuration(root.totalSeconds) : "Своё"
                        color: root.isCustom ? root.hub.bgPanel : root.hub.textMain
                        font.pixelSize: 13
                        font.bold: root.isCustom
                    }
                }

                MouseArea {
                    id: customArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openEditor()
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            spacing: 6
            visible: !root.isStopwatch && root.editing

            Item { Layout.fillWidth: true }

            HubInput {
                id: hourInput
                hub: root.hub
                implicitWidth: 48
                centered: true
                placeholder: "ч"
                maximumLength: 2
                validator: IntValidator { bottom: 0; top: 99 }
                onAccepted: root.applyEditor()
            }

            Text {
                text: ":"
                color: root.hub.textDim
                font.pixelSize: 18
                font.bold: true
            }

            HubInput {
                id: minInput
                hub: root.hub
                implicitWidth: 48
                centered: true
                placeholder: "мин"
                maximumLength: 2
                validator: IntValidator { bottom: 0; top: 59 }
                onAccepted: root.applyEditor()
            }

            Text {
                text: ":"
                color: root.hub.textDim
                font.pixelSize: 18
                font.bold: true
            }

            HubInput {
                id: secInput
                hub: root.hub
                implicitWidth: 48
                centered: true
                placeholder: "сек"
                maximumLength: 2
                validator: IntValidator { bottom: 0; top: 59 }
                onAccepted: root.applyEditor()
            }

            HubButton {
                hub: root.hub
                icon: "󰄬"
                text: "Задать"
                onClicked: root.applyEditor()
            }

            HubButton {
                hub: root.hub
                outline: true
                text: "Отмена"
                onClicked: root.editing = false
            }

            Item { Layout.fillWidth: true }
        }

        RowLayout {
            anchors.fill: parent
            spacing: 8
            visible: root.isStopwatch

            Repeater {
                model: Math.min(3, root.laps.length)

                delegate: Rectangle {
                    id: lapChip
                    required property int index
                    readonly property var lap: root.laps[root.laps.length - 1 - lapChip.index]

                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: 32
                    radius: 16
                    color: lapChip.index === 0 ? Qt.lighter(root.hub.bgTrack, 1.15) : root.hub.bgTrack

                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰈻"
                            font.family: root.hub.iconFont
                            font.pixelSize: 12
                            color: root.hub.accentPrimary
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(lapChip.lap.n)
                            font.pixelSize: 12
                            font.bold: true
                            color: root.hub.accentPrimary
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.formatSw(lapChip.lap.split)
                            font.pixelSize: 13
                            font.family: root.hub.monoFont
                            color: root.hub.textMain
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.laps.length === 0
                horizontalAlignment: Text.AlignHCenter
                text: root.swRunning ? "«Круг» — отметить отрезок" : "Круги появятся здесь"
                color: root.hub.textDim
                font.pixelSize: 12
            }
        }
    }

    // ------------------------- CONTROLS -------------------------
    component CtrlButton: Rectangle {
        id: ctrl
        required property var hub
        property bool primary: false
        property string label: ""
        signal clicked

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 36
        radius: 10
        color: ctrl.primary
               ? (ctrlArea.pressed ? Qt.darker(ctrl.hub.accentPrimary, 1.2)
                  : ctrlArea.containsMouse ? ctrl.hub.accentSecondary : ctrl.hub.accentPrimary)
               : (ctrlArea.containsMouse ? Qt.lighter(ctrl.hub.bgTrack, 1.25) : ctrl.hub.bgTrack)
        scale: ctrlArea.pressed ? 0.96 : 1.0

        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

        Text {
            anchors.centerIn: parent
            text: ctrl.label
            color: ctrl.primary ? ctrl.hub.bgPanel : ctrl.hub.textMain
            font.pixelSize: 14
            font.bold: true
        }

        MouseArea {
            id: ctrlArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ctrl.clicked()
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        CtrlButton {
            hub: root.hub
            primary: true
            label: (root.isStopwatch ? root.swRunning : root.isRunning) ? "Пауза" : "Старт"
            onClicked: root.isStopwatch ? root.swToggle() : root.toggleRun()
        }

        CtrlButton {
            hub: root.hub
            label: root.isStopwatch && root.swRunning ? "Круг" : "Сброс"
            onClicked: {
                if (!root.isStopwatch) root.reset()
                else if (root.swRunning) root.swLap()
                else root.swReset()
            }
        }
    }
}
