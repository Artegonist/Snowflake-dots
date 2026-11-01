import QtQuick
import QtQuick.Layouts

Item {
    id: dd

    // ------------------------- STATE -------------------------
    required property var hub

    property string label: ""
    property bool expanded: false
    property real popupHeight: 160
    property int headerHeight: 44
    property bool openUpward: false

    property alias header: headerSlot.data
    default property alias popup: popupSlot.data

    readonly property bool popupVisible: popupBox.visible

    readonly property int slotLeft: 12
    readonly property int slotRight: 30
    readonly property real labelSpace: dd.label !== "" ? labelText.implicitHeight + 6 : 0

    Layout.fillWidth: true
    implicitHeight: dd.labelSpace + dd.headerHeight
    z: popupBox.visible ? 100 : 1

    Connections {
        target: dd
        function onExpandedChanged() {
            if (dd.expanded)
                dd.hub.activeDropdown = dd
        }
    }

    Connections {
        target: dd.hub
        function onActiveDropdownChanged() {
            if (dd.hub.activeDropdown !== dd)
                dd.expanded = false
        }
    }

    Text {
        id: labelText
        visible: dd.label !== ""
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        text: dd.label
        color: dd.hub.textDim
        font.pixelSize: 15
        font.bold: true
    }

    // ------------------------- HEADER BUTTON -------------------------
    Rectangle {
        id: headerBtn
        anchors.top: parent.top
        anchors.topMargin: dd.labelSpace
        anchors.left: parent.left
        anchors.right: parent.right
        height: dd.headerHeight
        topLeftRadius: (popupBox.visible && dd.openUpward) ? 0 : 10
        topRightRadius: (popupBox.visible && dd.openUpward) ? 0 : 10
        bottomLeftRadius: (popupBox.visible && !dd.openUpward) ? 0 : 10
        bottomRightRadius: (popupBox.visible && !dd.openUpward) ? 0 : 10
        color: dd.hub.bgTrack
        border.width: (headerArea.containsMouse && !popupBox.visible) ? 2 : 0
        border.color: dd.hub.accentPrimary

        Item {
            id: headerSlot
            anchors.fill: parent
            anchors.leftMargin: dd.slotLeft
            anchors.rightMargin: dd.slotRight
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "▾"
            color: dd.hub.textDim
            font.pixelSize: 13
            rotation: (dd.expanded !== dd.openUpward) ? 180 : 0

            Behavior on rotation { Anim { kind: "fast" } }
        }

        MouseArea {
            id: headerArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: dd.expanded = !dd.expanded
        }
    }

    // ------------------------- POPUP -------------------------
    Rectangle {
        id: popupBox
        anchors.top: dd.openUpward ? undefined : headerBtn.bottom
        anchors.bottom: dd.openUpward ? headerBtn.top : undefined
        anchors.left: parent.left
        anchors.right: parent.right
        height: dd.expanded ? dd.popupHeight : 0
        visible: height > 0
        clip: true
        color: dd.hub.bgTrack
        topLeftRadius: dd.openUpward ? 10 : 0
        topRightRadius: dd.openUpward ? 10 : 0
        bottomLeftRadius: dd.openUpward ? 0 : 10
        bottomRightRadius: dd.openUpward ? 0 : 10

        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        Rectangle {
            anchors.top: dd.openUpward ? undefined : parent.top
            anchors.bottom: dd.openUpward ? parent.bottom : undefined
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            height: 1
            color: dd.hub.separatorColor
        }

        Item {
            id: popupSlot
            anchors.top: dd.openUpward ? undefined : parent.top
            anchors.bottom: dd.openUpward ? parent.bottom : undefined
            anchors.left: parent.left
            anchors.right: parent.right
            height: dd.popupHeight
        }
    }

    // ------------------------- FRAME -------------------------
    Rectangle {
        anchors.top: dd.openUpward ? popupBox.top : headerBtn.top
        anchors.left: headerBtn.left
        anchors.right: headerBtn.right
        anchors.bottom: dd.openUpward ? headerBtn.bottom : popupBox.bottom
        visible: popupBox.visible
        color: "transparent"
        radius: 10
        border.width: 2
        border.color: dd.hub.accentPrimary
    }
}
