import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Quickshell.Wayland
import "../../services"

PanelWindow {
    id: root

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
    }

    function hide() {
        if (!root.expanded || root.closing)
            return
        root.closing = true
        focusGrab.active = false
        root.mask = emptyRegion
        root.expanded = false
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
        right: 3
    }

    exclusionMode: ExclusionMode.Ignore

    color: "transparent"
    implicitWidth: 300
    implicitHeight: 300

    // ---------- COLORS ----------
    readonly property color accentPrimary: Theme.accentPrimary
    readonly property color accentSecondary: Theme.accentSecondary
    readonly property color bgPanel: Theme.bgPanelBattery
    readonly property color bgTrack: Theme.bgTrack
    readonly property color borderColor: Theme.accentPrimary
    readonly property color separatorColor: Qt.rgba(1, 1, 1, 0.08)
    readonly property color textMain: Theme.textMain
    readonly property color textDim: Theme.textDim

    // ---------- BATTERY(via Upower) ----------
    readonly property var battery: UPower.displayDevice
    readonly property bool ready: battery ? battery.ready : false
    readonly property int percent: ready ? Math.round(battery.percentage * 100) : 0
    readonly property bool charging: ready && battery.state === UPowerDeviceState.Charging
    readonly property bool fullyCharged: ready && battery.state === UPowerDeviceState.FullyCharged

    function formatTime(seconds) {
        if (!seconds || seconds <= 0)
            return "—"
        const totalMin = Math.round(seconds / 60)
        const h = Math.floor(totalMin / 60)
        const m = totalMin % 60
        if (h > 0)
            return h + " ч " + m + " мин"
        return m + " мин"
    }

    readonly property string timeLabel: {
        if (!ready) return "Нет данных о батарее"
        if (fullyCharged) return "Батарея заряжена"
        if (charging) return "До полной зарядки: " + formatTime(battery.timeToFull)
        return "Осталось: " + formatTime(battery.timeToEmpty)
    }

    // ---------- ANIMATED BATTERY FILL ----------
    property real animatedFraction: 0

    NumberAnimation {
        id: fillAnim
        target: root
        property: "animatedFraction"
        to: root.percent / 100
        duration: 700
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: liveUpdateAnim
        target: root
        property: "animatedFraction"
        duration: 400
        easing.type: Easing.OutCubic
    }

    onPercentChanged: {
        if (!root.expanded)
            return
        if (fillAnim.running)
            return
        liveUpdateAnim.stop()
        liveUpdateAnim.to = root.percent / 100
        liveUpdateAnim.start()
    }

    readonly property var profiles: [
        { label: "Экономия", profile: PowerProfile.PowerSaver },
        { label: "Баланс", profile: PowerProfile.Balanced },
        { label: "Мощность", profile: PowerProfile.Performance }
    ]

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

        transformOrigin: Item.TopRight

        opacity: 0
        scale: 0.85

        SequentialAnimation {
            id: openAnim
            ParallelAnimation {
                NumberAnimation { target: card; property: "opacity"; to: 1; duration: 150; easing.type: Easing.OutCubic }
                NumberAnimation { target: card; property: "scale"; to: 1; duration: 190; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
            }
        }

        SequentialAnimation {
            id: closeAnim
            ParallelAnimation {
                NumberAnimation { target: card; property: "opacity"; to: 0; duration: 120; easing.type: Easing.InCubic }
                NumberAnimation { target: card; property: "scale"; to: 0.85; duration: 120; easing.type: Easing.InCubic }
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
                fillAnim.stop()
                liveUpdateAnim.stop()
                if (root.expanded) {
                    root.animatedFraction = 0
                    fillAnim.to = root.percent / 100
                    openAnim.start()
                    fillAnim.start()
                } else {
                    closeAnim.start()
                }
            }
        }

        focus: true
        Keys.onEscapePressed: root.hide()

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            // --- TITLE ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: root.charging ? "󱐋" : "󱈏"
                    font.pixelSize: 20
                    color: root.accentPrimary
                }

                Text {
                    text: root.percent + "%"
                    color: root.textMain
                    font.pixelSize: 30
                    font.bold: true
                }

                Item { Layout.fillWidth: true }
            }

            // --- INDICATOR ---
            Rectangle {
                Layout.fillWidth: true
                height: 8
                radius: 4
                color: root.bgTrack

                Rectangle {
                    height: parent.height
                    radius: 4
                    width: parent.width * root.animatedFraction

                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: root.accentSecondary }
                        GradientStop { position: 1.0; color: root.accentPrimary }
                    }
                }
            }

            // --- TIME FROM BATTERY---
            Text {
                Layout.fillWidth: true
                text: root.timeLabel
                color: root.textDim
                font.pixelSize: 13
            }

            // --- DEVIDER ---
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: root.separatorColor
            }

            // --- HEADER OF MODES BLOCK ---
            Text {
                text: "Режим питания"
                color: root.textDim
                font.pixelSize: 12
            }

            // --- MODES SWITCHER ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: root.profiles

                    delegate: Rectangle {
                        Layout.fillWidth: true
                        height: 34
                        radius: 10

                        readonly property bool isActive: PowerProfiles.profile === modelData.profile
                        readonly property bool isDisabled: modelData.profile === PowerProfile.Performance
                                                             && !PowerProfiles.hasPerformanceProfile

                        color: isActive ? root.accentPrimary
                               : (mouseArea.containsMouse && !isDisabled ? root.accentSecondary : root.bgTrack)
                        opacity: isDisabled ? 0.4 : 1.0

                        // SMALL ANIMATION
                        scale: mouseArea.pressed && !isDisabled ? 0.93 : 1.0

                        Behavior on color {
                            ColorAnimation { duration: 180; easing.type: Easing.OutCubic }
                        }

                        Behavior on opacity {
                            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                        }

                        Behavior on scale {
                            NumberAnimation { duration: 140; easing.type: Easing.OutBack }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            font.pixelSize: 12
                            font.bold: parent.isActive
                            color: parent.isActive ? root.bgPanel : root.textMain

                            Behavior on color {
                                ColorAnimation { duration: 180; easing.type: Easing.OutCubic }
                            }
                        }

                        MouseArea {
                            id: mouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !parent.isDisabled
                            cursorShape: Qt.PointingHandCursor
                            onClicked: PowerProfiles.profile = modelData.profile
                        }
                    }
                }
            }
        }
    }
}
