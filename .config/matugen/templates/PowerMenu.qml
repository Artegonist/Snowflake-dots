import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

PanelWindow {
    id: root

    // VISIBILITY
    property bool menuVisible: false
    // CLOSING
    property bool closing: false
    visible: menuVisible || closing

    // BACKGROUND
    color: "transparent"

    // PALETTE
    readonly property color accentPrimary: "{{theme.accent_primary.hex}}"
    readonly property color accentSecondary: "{{theme.accent_secondary.hex}}"
    readonly property color bgPanel: "{{theme.bg_panel_battery.hex}}"
    readonly property color bgTrack: "{{theme.bg_track.hex}}"
    readonly property color borderColor: "{{theme.accent_primary.hex}}"
    readonly property color textMain: "{{theme.text_main.hex}}"

    // ANCHORS
    anchors {
        top: true
        right: true
    }
    margins {
        top: 3
        right: 3
    }

    // SIZES
    readonly property int fullWidth: 64
    readonly property int fullHeight: 196
    readonly property int lineThickness: 8

    // ANIMSTATE
    property real animWidth: lineThickness
    property real animHeight: 0

    implicitWidth: animWidth
    implicitHeight: animHeight

    // TOGGLE
    onMenuVisibleChanged: {
        if (menuVisible) {
            closeAnimation.stop()
            closing = false

            buttonsAppearAnimation.stop()
            btn1.scale = 0
            btn2.scale = 0
            btn3.scale = 0

            animWidth = lineThickness
            animHeight = 0
            openAnimation.restart()
        } else {
            openAnimation.stop()
            buttonsAppearAnimation.stop()
            closing = true
            closeAnimation.restart()
        }
    }

    // OPEN
    SequentialAnimation {
        id: openAnimation

        NumberAnimation {
            target: root
            property: "animHeight"
            to: root.fullHeight
            duration: 220
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: root
            property: "animWidth"
            to: root.fullWidth
            duration: 220
            easing.type: Easing.OutQuad
        }

        onFinished: buttonsAppearAnimation.restart()
    }

    // APPEAR
    SequentialAnimation {
        id: buttonsAppearAnimation

        NumberAnimation {
            target: btn1
            property: "scale"
            from: 0
            to: 1
            duration: 140
            easing.type: Easing.OutBack
        }
        NumberAnimation {
            target: btn2
            property: "scale"
            from: 0
            to: 1
            duration: 140
            easing.type: Easing.OutBack
        }
        NumberAnimation {
            target: btn3
            property: "scale"
            from: 0
            to: 1
            duration: 140
            easing.type: Easing.OutBack
        }
    }

    // CLOSE
    SequentialAnimation {
        id: closeAnimation

        ParallelAnimation {
            NumberAnimation {
                target: btn1
                property: "scale"
                to: 0
                duration: 110
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: btn2
                property: "scale"
                to: 0
                duration: 110
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: btn3
                property: "scale"
                to: 0
                duration: 110
                easing.type: Easing.InQuad
            }
        }
        NumberAnimation {
            target: root
            property: "animWidth"
            to: root.lineThickness
            duration: 180
            easing.type: Easing.InQuad
        }
        NumberAnimation {
            target: root
            property: "animHeight"
            to: 0
            duration: 180
            easing.type: Easing.InQuad
        }

        ScriptAction {
            script: root.closing = false
        }
    }

    // IPC
    IpcHandler {
        target: "powermenu"

        function toggle(): void {
            root.menuVisible = !root.menuVisible
        }

        function show(): void {
            root.menuVisible = true
        }

        function hide(): void {
            root.menuVisible = false
        }
    }

    // FOCUSGRAB
    HyprlandFocusGrab {
        id: grab
        windows: [root]
        active: root.menuVisible
        onCleared: root.menuVisible = false
    }

    // BUTTON
    component PowerButton: Rectangle {
        id: btn

        property string iconText: ""
        signal clicked()

        // HOLDTIME
        readonly property int holdDuration: 1500

        Layout.fillWidth: true
        Layout.preferredHeight: 52

        // SCALE
        scale: 0

        // STYLE
        radius: 10
        border.width: mouseArea.pressed ? 2 : 1
        border.color: root.accentSecondary
        color: mouseArea.pressed ? "transparent" : (mouseArea.containsMouse ? root.accentSecondary : root.accentPrimary)

        Behavior on color {
            ColorAnimation { duration: 120 }
        }
        Behavior on border.width {
            NumberAnimation { duration: 120 }
        }

        // CLIP
        clip: true

        // FILL
        Rectangle {
            id: holdFill
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 0
            radius: btn.radius
            color: root.accentPrimary
        }

        // REMAINING
        readonly property real holdRemaining: btn.holdDuration / 1000 * (1 - holdFill.height / btn.height)

        NumberAnimation {
            id: holdAnimation
            target: holdFill
            property: "height"
            from: 0
            to: btn.height
            duration: btn.holdDuration
            easing.type: Easing.Linear
            onFinished: btn.clicked()
        }

        // ICON
        Text {
            anchors.centerIn: parent
            text: mouseArea.pressed ? btn.holdRemaining.toFixed(1) : btn.iconText
            color: mouseArea.pressed ? root.accentPrimary : root.bgPanel

            Behavior on color {
                ColorAnimation { duration: 120 }
            }

            font.pixelSize: mouseArea.pressed ? 16 : 20
            font.family: "Symbols Nerd Font"
        }

        // OVERLAY
        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: holdFill.height
            clip: true

            Text {
                text: mouseArea.pressed ? btn.holdRemaining.toFixed(1) : ""
                color: root.bgPanel
                font.pixelSize: 16
                font.family: "Symbols Nerd Font"
                x: (btn.width - width) / 2
                y: holdFill.height - (btn.height + height) / 2
            }
        }

        // MOUSE
        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onPressed: {
                holdFill.height = 0
                holdAnimation.restart()
            }
            onReleased: {
                holdAnimation.stop()
                holdFill.height = 0
            }
            onCanceled: {
                holdAnimation.stop()
                holdFill.height = 0
            }
        }
    }

    // PANEL
    Rectangle {
        anchors.fill: parent
        color: root.bgPanel
        // RADIUS
        radius: Math.min(8, root.animWidth / 2, root.animHeight / 2)
        border.width: 3
        border.color: root.borderColor

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            PowerButton {
                id: btn1
                iconText: "\uf011" // power off
                onClicked: {
                    root.menuVisible = false
                    poweroffProcess.running = true
                }
            }

            PowerButton {
                id: btn2
                iconText: "\uf021" // reboot
                onClicked: {
                    root.menuVisible = false
                    rebootProcess.running = true
                }
            }

            PowerButton {
                id: btn3
                iconText: "\uf08b" // exit Hyprland
                onClicked: {
                    root.menuVisible = false
                    exitProcess.running = true
                }
            }
        }
    }

    Process {
        id: poweroffProcess
        command: ["systemctl", "poweroff"]
    }

    Process {
        id: rebootProcess
        command: ["systemctl", "reboot"]
    }

    Process {
        id: exitProcess
        command: ["hyprctl", "dispatch", "exit"]
    }
}
