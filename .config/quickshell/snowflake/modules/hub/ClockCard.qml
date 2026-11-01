import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root

    required property var hub

    spacing: 6

    property var now: new Date()

    readonly property var months: ["января", "февраля", "марта", "апреля", "мая", "июня",
        "июля", "августа", "сентября", "октября", "ноября", "декабря"]
    readonly property var weekdays: ["воскресенье", "понедельник", "вторник", "среда",
        "четверг", "пятница", "суббота"]

    readonly property string dateText: {
        const s = root.weekdays[root.now.getDay()] + ", " + root.now.getDate() + " " + root.months[root.now.getMonth()]
        return s.charAt(0).toUpperCase() + s.slice(1)
    }

    function pad(n) { return n < 10 ? "0" + n : "" + n }

    Timer {
        interval: 1000
        running: root.hub.expanded
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: root.pad(root.now.getHours()) + ":" + root.pad(root.now.getMinutes()) + ":" + root.pad(root.now.getSeconds())
        color: root.hub.textMain
        font.pixelSize: 72
        font.bold: true
        font.family: root.hub.monoFont
    }

    Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.dateText
        color: root.hub.textDim
        font.pixelSize: 24
    }

    Item {
        Layout.fillWidth: true
        Layout.topMargin: 6
        implicitHeight: 1

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.8
            height: 1
            color: root.hub.textDim
            opacity: 0.6
        }
    }
}
