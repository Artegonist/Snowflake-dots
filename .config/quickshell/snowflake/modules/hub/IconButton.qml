import QtQuick

Rectangle {
    id: btn

    required property string glyph
    required property var hub

    property int size: 30
    property bool filled: false
    property color glyphColor: btn.hub.textMain

    signal clicked

    implicitWidth: btn.size
    implicitHeight: btn.size
    radius: btn.filled ? btn.size / 2 : 8
    color: mouse.pressed ? Qt.darker(btn.hub.accentPrimary, 1.2)
         : mouse.containsMouse ? (btn.filled ? btn.hub.accentSecondary : btn.hub.accentPrimary)
         : (btn.filled ? btn.hub.accentPrimary : btn.hub.hoverColor)
    scale: mouse.pressed ? 0.9 : 1.0

    Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

    Text {
        anchors.centerIn: parent
        text: btn.glyph
        font.family: btn.hub.iconFont
        font.pixelSize: Math.round(btn.size * 0.46)
        color: (btn.filled || mouse.containsMouse) ? btn.hub.bgPanel : btn.glyphColor

        Behavior on color { ColorAnimation { duration: 120 } }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
