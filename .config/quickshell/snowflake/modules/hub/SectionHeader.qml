import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property var hub
    property string title: ""
    property string badge: ""
    property bool badgeAccent: false

    Layout.fillWidth: true
    implicitHeight: Math.max(titleText.implicitHeight, 22)

    Text {
        id: titleText
        anchors.centerIn: parent
        width: Math.min(implicitWidth, parent.width - 2 * (badgeBox.visible ? badgeBox.width + 8 : 0))
        horizontalAlignment: Text.AlignHCenter
        text: root.title
        color: root.hub.textDim
        font.pixelSize: 15
        font.bold: true
        elide: Text.ElideRight
    }

    Rectangle {
        id: badgeBox
        visible: root.badge !== ""
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: badgeText.implicitWidth + 16
        implicitHeight: 22
        radius: 11
        color: root.badgeAccent ? root.hub.accentPrimary : root.hub.bgTrack

        Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Text {
            id: badgeText
            anchors.centerIn: parent
            text: root.badge
            color: root.badgeAccent ? root.hub.bgPanel : root.hub.textDim
            font.pixelSize: 12
            font.bold: true

            Behavior on color { ColorAnimation { duration: 160 } }
        }
    }
}
