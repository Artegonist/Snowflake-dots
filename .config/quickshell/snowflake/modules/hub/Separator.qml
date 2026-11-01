import QtQuick
import QtQuick.Layouts

Rectangle {
    property bool vertical: false

    color: Qt.rgba(1, 1, 1, 0.08)
    implicitWidth: 1
    implicitHeight: 1
    Layout.fillWidth: !vertical
    Layout.fillHeight: vertical
}
