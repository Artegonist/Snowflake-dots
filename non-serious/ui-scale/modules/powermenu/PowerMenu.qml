import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../../services"

PanelWindow {
    id: root

    //------------------STATE-----------------------
    property bool menuVisible: false
    property bool closing: false
    property bool hasShown: false
    property int savedWorkspaceId: 0
    property string savedWorkspaceName: ""
    property bool restoreWorkspaceOnClose: false
    visible: hasShown

    color: "transparent"
    focusable: menuVisible
    exclusionMode: ExclusionMode.Auto
    mask: menuVisible ? panelRegion : emptyRegion

    Region { id: emptyRegion; width: 0; height: 0 }
    Region { id: panelRegion; item: panel }

    //------------------COLORS-----------------------
    readonly property color accentPrimary: Theme.accentPrimary
    readonly property color accentSecondary: Theme.accentSecondary
    readonly property color bgPanel: Theme.bgPanelBattery
    readonly property color bgTrack: Theme.bgTrack
    readonly property color borderColor: Theme.accentPrimary
    readonly property color textMain: Theme.textMain

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

    readonly property real uiScale: UiScale.scaleFor("power", root.screen, root.fullWidth, root.fullHeight)
    implicitWidth: Math.round(fullWidth * root.uiScale)
    implicitHeight: Math.round(fullHeight * root.uiScale)

    //------------------TOGGLE-----------------------
    function show() { menuVisible = true }

    function hide() {
        if (!menuVisible) return
        restoreWorkspaceOnClose = true
        menuVisible = false
    }

    function toggle() { if (menuVisible) hide(); else show() }

    function restoreSavedWorkspace() {
        const current = Hyprland.focusedWorkspace
        if (current && current.id === savedWorkspaceId) return
        if (savedWorkspaceId > 0) {
            Hyprland.dispatch("workspace " + savedWorkspaceId)
        } else if (savedWorkspaceId < 0 && savedWorkspaceName !== "" &&
                   savedWorkspaceName !== "special" && savedWorkspaceName.indexOf("special:") !== 0) {
            Hyprland.dispatch("workspace name:" + savedWorkspaceName)
        }
    }

    onMenuVisibleChanged: {
        if (menuVisible) {
            const workspace = Hyprland.focusedWorkspace
            savedWorkspaceId = workspace ? workspace.id : 0
            savedWorkspaceName = workspace ? workspace.name : ""
            restoreWorkspaceOnClose = true
            closeAnimation.stop()
            closing = false

            buttonsAppearAnimation.stop()
            btn1.scale = 0
            btn2.scale = 0
            btn3.scale = 0
            btn4.scale = 0

            animWidth = lineThickness
            animHeight = 0
            hasShown = true
            openAnimation.restart()
            Qt.callLater(function() {
                if (!root.menuVisible) return
                grab.active = true
                panel.forceActiveFocus()
            })
        } else {
            openAnimation.stop()
            buttonsAppearAnimation.stop()
            closing = true
            grab.active = false
            btn1.cancelHold()
            btn2.cancelHold()
            btn3.cancelHold()
            btn4.cancelHold()
            if (restoreWorkspaceOnClose) restoreSavedWorkspace()
            restoreWorkspaceOnClose = false
            savedWorkspaceId = 0
            savedWorkspaceName = ""
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

        onFinished: { if (root.menuVisible) buttonsAppearAnimation.restart() }
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
            script: { if (!root.menuVisible) root.closing = false }
        }
    }

    //------------------IPC-----------------------
    IpcHandler {
        target: "powermenu"

        function toggle(): void {
            root.toggle()
        }

        function show(): void {
            root.show()
        }

        function hide(): void {
            root.hide()
        }
    }

    HyprlandFocusGrab {
        id: grab
        windows: [root]
        onCleared: {
            if (!root.menuVisible) return
            root.restoreWorkspaceOnClose = false
            root.menuVisible = false
        }
    }

    //------------------POWERBUTTON-----------------------
    component PowerButton: Rectangle {
        id: btn

        property string iconText: ""
        signal clicked()

        readonly property int holdDuration: 1500

        function cancelHold() {
            holdAnimation.stop()
            holdFill.height = 0
        }

        onEnabledChanged: { if (!enabled) cancelHold() }

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
            onFinished: {
                if (root.menuVisible && btn.enabled && mouseArea.pressed) btn.clicked()
            }
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
            onReleased: btn.cancelHold()
            onCanceled: btn.cancelHold()
        }
    }

    //------------------PANEL-----------------------
    Item {
        id: scaler
        width: root.fullWidth
        height: root.fullHeight
        scale: root.uiScale
        transformOrigin: Item.TopLeft
    }

    Rectangle {
        id: panel
        parent: scaler
        anchors.top: parent.top
        anchors.right: parent.right
        width: root.animWidth
        height: root.animHeight
        opacity: root.menuVisible || root.closing ? 1 : 0
        enabled: root.menuVisible
        clip: true
        color: root.bgPanel
        radius: Math.min(8, root.animWidth / 2, root.animHeight / 2)
        border.width: 3
        border.color: root.borderColor

        focus: root.menuVisible
        Keys.onEscapePressed: root.hide()

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            PowerButton {
                id: btn1
                iconText: "\uf011"
                onClicked: {
                    root.hide()
                    poweroffProcess.running = true
                }
            }

            PowerButton {
                id: btn2
                iconText: "\uf021"
                onClicked: {
                    root.hide()
                    rebootProcess.running = true
                }
            }

            PowerButton {
                id: btn3
                iconText: "\uf08b"
                onClicked: {
                    root.hide()
                    exitProcess.running = true
                }
            }

            PowerButton {
                id: btn4
                iconText: "\uf023"
                onClicked: {
                    root.hide()
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
