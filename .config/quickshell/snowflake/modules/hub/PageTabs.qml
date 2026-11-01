import QtQuick

Rectangle {
    id: tabs

    // ------------------------- STATE -------------------------
    required property var hub
    required property var pages
    property int currentIndex: 0
    property int tabWidth: 150

    signal selected(int index)

    implicitWidth: tabs.tabWidth * tabs.pages.length + 8
    implicitHeight: 38
    radius: height / 2
    color: tabs.hub.bgTrack

    function step(delta) {
        const next = Math.max(0, Math.min(tabs.pages.length - 1, tabs.currentIndex + delta))
        if (next !== tabs.currentIndex)
            tabs.selected(next)
    }

    // ------------------------- ACTIVE TAB -------------------------
    Rectangle {
        id: highlight
        y: 4
        width: tabs.tabWidth
        height: tabs.height - 8
        radius: height / 2
        color: tabs.hub.accentPrimary
        x: 4 + tabs.currentIndex * tabs.tabWidth

        Behavior on x { Anim {} }
    }

    // ------------------------- TABS -------------------------
    Row {
        x: 4
        y: 4

        Repeater {
            model: tabs.pages

            delegate: Item {
                id: tab
                required property var modelData
                required property int index
                readonly property bool current: tab.index === tabs.currentIndex

                width: tabs.tabWidth
                height: tabs.height - 8

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: (!tab.current && tabArea.containsMouse) ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                Text {
                    anchors.centerIn: parent
                    text: tab.modelData.title
                    font.pixelSize: 14
                    font.bold: tab.current
                    color: tab.current ? tabs.hub.bgPanel : tabs.hub.textMain

                    Behavior on color { ColorAnimation { duration: 200 } }
                }

                MouseArea {
                    id: tabArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tabs.selected(tab.index)
                }
            }
        }
    }

    // ------------------------- WHEEL -------------------------
    WheelHandler {
        property real acc: 0
        onWheel: function(event) {
            acc += event.angleDelta.y
            if (acc <= -120) {
                acc = 0
                tabs.step(1)
            } else if (acc >= 120) {
                acc = 0
                tabs.step(-1)
            }
        }
    }
}
