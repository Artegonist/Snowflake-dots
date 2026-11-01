import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root

    // ------------------------- STATE -------------------------
    required property var hub
    required property var usage
    property var apps: null

    spacing: 10

    readonly property var sorted: root.usage.allAppsSorted
    readonly property real total: root.usage.focusTotal
    readonly property int segments: Math.min(5, root.sorted.length)
    readonly property real restSecs: {
        let s = root.total
        for (let i = 0; i < root.segments; i++) s -= root.sorted[i][1]
        return Math.max(0, s)
    }

    function percent(secs) {
        if (root.total <= 0) return "0%"
        const p = secs / root.total * 100
        return p > 0 && p < 1 ? "<1%" : Math.round(p) + "%"
    }

    function segColor(i) {
        const h = root.hub
        if (i === 0) return h.accentPrimary
        if (i === 1) return h.accentSecondary
        if (i === 2) return Qt.tint(h.accentPrimary, Qt.rgba(h.textMain.r, h.textMain.g, h.textMain.b, 0.45))
        if (i === 3) return Qt.tint(h.accentSecondary, Qt.rgba(h.textMain.r, h.textMain.g, h.textMain.b, 0.3))
        if (i === 4) return h.textDim
        return Qt.rgba(h.textDim.r, h.textDim.g, h.textDim.b, 0.45)
    }

    function windowOf(cls) {
        if (!root.apps) return null
        for (const w of root.apps.windows)
            if (w.cls === cls) return w
        return null
    }

    // ------------------------- LIST MODEL -------------------------
    ListModel { id: appsModel }

    function syncModel() {
        const arr = root.sorted
        for (let i = 0; i < arr.length; i++) {
            const item = { cls: arr[i][0], secs: arr[i][1] }
            if (i < appsModel.count) appsModel.set(i, item)
            else appsModel.append(item)
        }
        if (appsModel.count > arr.length)
            appsModel.remove(arr.length, appsModel.count - arr.length)
    }

    onSortedChanged: root.syncModel()
    Component.onCompleted: root.syncModel()

    // ------------------------- REVEAL ANIMATION -------------------------
    readonly property bool shown: root.hub.expanded && root.hub.currentPage === 1
    property real reveal: 1
    onShownChanged: if (root.shown) revealAnim.restart()

    NumberAnimation {
        id: revealAnim
        target: root
        property: "reveal"
        from: 0
        to: 1
        duration: 800
        easing.type: Easing.OutCubic
    }

    function appearAt(frac) {
        return Math.max(0, Math.min(1, (root.reveal - frac * 0.45) / 0.55))
    }

    // ------------------------- SUMMARY -------------------------
    Rectangle {
        Layout.fillWidth: true
        visible: root.sorted.length > 0
        implicitHeight: summary.implicitHeight + 24
        radius: 10
        color: root.hub.bgTrack

        ColumnLayout {
            id: summary
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: root.usage.formatHM(root.total)
                    color: root.hub.textMain
                    font.pixelSize: 26
                    font.bold: true
                    font.family: root.hub.monoFont
                }

                Text {
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: 4
                    text: "в фокусе сегодня"
                    color: root.hub.textDim
                    font.pixelSize: 13
                }

                Item { Layout.fillWidth: true }
            }

            Item {
                id: shareBar
                Layout.fillWidth: true
                implicitHeight: 10

                readonly property int parts: root.segments + (root.restSecs > 0 ? 1 : 0)

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: root.hub.bgPanel
                }

                Row {
                    height: parent.height
                    spacing: 2

                    Repeater {
                        model: shareBar.parts

                        delegate: Rectangle {
                            required property int index
                            readonly property bool rest: index >= root.segments
                            readonly property real secs: rest ? root.restSecs : (root.sorted[index] ? root.sorted[index][1] : 0)

                            height: shareBar.height
                            width: root.total > 0
                                ? Math.max(0, (shareBar.width - 2 * (shareBar.parts - 1)) * secs / root.total * root.appearAt(index / 5))
                                : 0
                            radius: height / 2
                            color: root.segColor(rest ? 5 : index)

                            Behavior on width { enabled: !revealAnim.running; NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 14

                Repeater {
                    model: root.segments

                    delegate: Row {
                        id: legendItem
                        required property int index
                        readonly property var app: root.sorted[index] || ["", 0]

                        spacing: 6

                        AppIcon {
                            id: legendIcon
                            hub: root.hub
                            appClass: legendItem.app[0]
                            visible: false
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 8
                            height: 8
                            radius: 4
                            color: root.segColor(legendItem.index)
                        }

                        Text {
                            text: legendIcon.appName
                            color: root.hub.textMain
                            font.pixelSize: 12
                        }

                        Text {
                            text: root.percent(legendItem.app[1])
                            color: root.hub.textDim
                            font.pixelSize: 12
                        }
                    }
                }
            }
        }
    }

    // ------------------------- LIST -------------------------
    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: appsModel.count > 0
        model: appsModel
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        spacing: 6

        SmoothScroll { flick: list }

        delegate: Rectangle {
            id: appRow
            required property int index
            required property string cls
            required property real secs

            readonly property var win: root.windowOf(appRow.cls)
            readonly property real appear: root.appearAt(Math.min(appRow.index, 8) / 8)

            width: list.width
            height: 54
            radius: 10
            color: rowHover.hovered ? Qt.lighter(root.hub.bgTrack, 1.18) : root.hub.bgTrack
            opacity: appRow.appear
            scale: rowTap.pressed ? 0.98 : 1.0
            transform: Translate { x: (1 - appRow.appear) * 18 }

            Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

            HoverHandler {
                id: rowHover
                cursorShape: appRow.win ? Qt.PointingHandCursor : Qt.ArrowCursor
            }

            TapHandler {
                id: rowTap
                enabled: appRow.win !== null
                onTapped: if (appRow.win && root.apps) root.apps.focusWindow(appRow.win.address)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 12
                spacing: 12

                Text {
                    Layout.preferredWidth: 18
                    horizontalAlignment: Text.AlignRight
                    text: String(appRow.index + 1)
                    color: appRow.index < 3 ? root.hub.accentPrimary : root.hub.textDim
                    font.pixelSize: 13
                    font.bold: appRow.index < 3
                    font.family: root.hub.monoFont
                }

                AppIcon {
                    id: appIcon
                    hub: root.hub
                    appClass: appRow.cls
                    size: 30

                    Rectangle {
                        visible: appRow.win !== null
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: -3
                        anchors.bottomMargin: -3
                        width: 11
                        height: 11
                        radius: 6
                        color: root.hub.accentPrimary
                        border.width: 2
                        border.color: appRow.color
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 7

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: appIcon.appName
                            color: root.hub.textMain
                            font.pixelSize: 14
                            elide: Text.ElideRight
                        }

                        Text {
                            text: root.percent(appRow.secs)
                            color: root.hub.textDim
                            font.pixelSize: 12
                        }

                        Text {
                            text: root.usage.formatHM(appRow.secs)
                            color: root.hub.accentPrimary
                            font.pixelSize: 14
                            font.bold: true
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 4
                        radius: 2
                        color: root.hub.bgPanel

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width * (root.usage.topMax > 0 ? appRow.secs / root.usage.topMax : 0) * appRow.appear
                            radius: 2
                            color: root.segColor(appRow.index < 5 ? appRow.index : 5)

                            Behavior on width { enabled: !revealAnim.running; NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.topMargin: 8
        visible: root.sorted.length === 0
        text: "Пока нет данных — время копится каждые " + root.usage.sampleSeconds + " с"
        color: root.hub.textDim
        font.pixelSize: 13
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
    }

    Item {
        visible: root.sorted.length === 0
        Layout.fillHeight: true
    }
}
