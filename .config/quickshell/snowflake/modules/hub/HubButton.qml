import QtQuick

Rectangle {
    id: btn

    required property var hub

    property string text: ""
    property string icon: ""
    property bool outline: false
    property bool active: true
    property int fontSize: 13

    signal clicked

    readonly property color labelColor: btn.outline ? btn.hub.accentPrimary : btn.hub.bgPanel

    implicitWidth: label.implicitWidth + 26
    implicitHeight: 32
    radius: 10
    opacity: btn.active ? 1.0 : 0.5
    color: btn.outline
           ? (area.containsMouse ? btn.hub.hoverColor : "transparent")
           : (area.pressed ? Qt.darker(btn.hub.accentPrimary, 1.2)
              : area.containsMouse ? btn.hub.accentSecondary : btn.hub.accentPrimary)
    border.width: btn.outline ? 1 : 0
    border.color: btn.hub.accentPrimary
    scale: area.pressed ? 0.95 : 1.0

    Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 120 } }

    Row {
        id: label
        anchors.centerIn: parent
        spacing: 6

        Text {
            visible: btn.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: btn.icon
            font.family: btn.hub.iconFont
            font.pixelSize: btn.fontSize + 1
            color: btn.labelColor
        }

        Text {
            visible: btn.text !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: btn.text
            font.pixelSize: btn.fontSize
            font.bold: true
            color: btn.labelColor
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: btn.active
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
