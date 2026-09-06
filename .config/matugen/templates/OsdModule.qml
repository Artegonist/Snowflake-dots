import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

PanelWindow {
    id: root

    //------------------STATE-----------------------
    property bool menuVisible: false
    property bool closing: false
    visible: menuVisible || closing

    color: "transparent"
    focusable: true

    //------------------COLORS-----------------------
    readonly property color accentPrimary: "{{theme.accent_primary.hex}}"
    readonly property color accentSecondary: "{{theme.accent_secondary.hex}}"
    readonly property color bgPanel: "{{theme.bg_panel_battery.hex}}"
    readonly property color bgTrack: "{{theme.bg_track.hex}}"
    readonly property color borderColor: "{{theme.accent_primary.hex}}"
    readonly property color textMain: "{{theme.text_main.hex}}"

    //------------------LAYOUT-----------------------
    anchors {
        top: true
        right: true
    }
    margins {
        top: 3
        right: 3
    }

    readonly property int fullWidth: 64
    readonly property int fullHeight: 258
    readonly property int lineThickness: 8

    property real animWidth: lineThickness
    property real animHeight: 0

    implicitWidth: animWidth
    implicitHeight: animHeight

    //------------------TOGGLE-----------------------
    onMenuVisibleChanged: {
        if (menuVisible) {
            closeAnimation.stop()
            closing = false

            buttonsAppearAnimation.stop()
            btn1.scale = 0
            btn2.scale = 0
            btn3.scale = 0
            btn4.scale = 0

            animWidth = lineThickness
            animHeight = 0
            openAnimation.restart()
            panel.forceActiveFocus()
        } else {
            openAnimation.stop()
            buttonsAppearAnimation.stop()
            closing = true
            closeAnimation.restart()
        }
    }

    //------------------ANIMATIONS-----------------------
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
        NumberAnimation {
            target: btn4
            property: "scale"
            from: 0
            to: 1
            duration: 140
            easing.type: Easing.OutBack
        }
    }

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
            NumberAnimation {
                target: btn4
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

    //------------------IPC-----------------------
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

    HyprlandFocusGrab {
        id: grab
        windows: [root]
        active: root.menuVisible
        onCleared: root.menuVisible = false
    }

    //------------------POWERBUTTON-----------------------
    component PowerButton: Rectangle {
        id: btn

        property string iconText: ""
        signal clicked()

        readonly property int holdDuration: 1500

        Layout.fillWidth: true
        Layout.preferredHeight: 52

        scale: 0
        radius: 10
        border.width: mouseArea.pressed ? 2 : 1
        border.color: root.accentSecondary
        color: mouseArea.pressed ? root.bgPanel : (mouseArea.containsMouse ? root.accentSecondary : root.accentPrimary)
        clip: true

        Behavior on color {
            ColorAnimation { duration: 120 }
        }
        Behavior on border.width {
            NumberAnimation { duration: 120 }
        }

        Rectangle {
            id: holdFill
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 0
            radius: btn.radius
            color: "transparent"
            clip: true

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: btn.height
                radius: btn.radius
                color: root.accentPrimary
            }
        }

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

        Text {
            anchors.centerIn: parent
            text: mouseArea.pressed ? btn.holdRemaining.toFixed(1) : btn.iconText
            color: mouseArea.pressed ? root.accentPrimary : root.bgPanel
            font.pixelSize: mouseArea.pressed ? 16 : 20
            font.family: "Symbols Nerd Font"

            Behavior on color {
                ColorAnimation { duration: 120 }
            }
        }

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

    //------------------PANEL-----------------------
    Rectangle {
        id: panel
        anchors.fill: parent
        color: root.bgPanel
        radius: Math.min(8, root.animWidth / 2, root.animHeight / 2)
        border.width: 3
        border.color: root.borderColor

        focus: true
        Keys.onEscapePressed: root.menuVisible = false

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            PowerButton {
                id: btn1
                iconText: "\uf011"
                onClicked: {
                    root.menuVisible = false
                    poweroffProcess.running = true
                }
            }

            PowerButton {
                id: btn2
                iconText: "\uf021"
                onClicked: {
                    root.menuVisible = false
                    rebootProcess.running = true
                }
            }

            PowerButton {
                id: btn3
                iconText: "\uf08b"
                onClicked: {
                    root.menuVisible = false
                    exitProcess.running = true
                }
            }

            PowerButton {
                id: btn4
                iconText: "\uf023"
                onClicked: {
                    root.menuVisible = false
                    lockProcess.running = true
                }
            }
        }
    }

    //------------------PROCESSES-----------------------
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
        command: ["bash", "-c", "loginctl terminate-session $XDG_SESSION_ID && uwsm stop"]
    }

    Process {
        id: lockProcess
        command: ["hyprlock"]
    }
}
