import QtQuick
import Quickshell

Item {
    id: icon

    required property var hub
    property string appClass: ""
    property int size: 30
    property bool highlighted: false

    implicitWidth: icon.size
    implicitHeight: icon.size

    readonly property var entry: {
        const cls = icon.appClass
        if (!cls) return null
        try {
            const all = DesktopEntries.applications ? DesktopEntries.applications.values : null
            if (typeof DesktopEntries.heuristicLookup === "function")
                return DesktopEntries.heuristicLookup(cls)
            return DesktopEntries.byId(cls) || DesktopEntries.byId(cls.toLowerCase())
        } catch (e) {
            return null
        }
    }

    readonly property string appName: icon.entry && icon.entry.name ? icon.entry.name : icon.appClass

    readonly property string iconSource: {
        const name = icon.entry && icon.entry.icon ? icon.entry.icon : icon.appClass.toLowerCase()
        if (!name) return ""
        if (name.startsWith("/")) return "file://" + name
        try {
            return Quickshell.iconPath(name, true)
        } catch (e) {
            return ""
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Math.round(icon.size * 0.24)
        visible: img.status !== Image.Ready
        color: icon.highlighted ? Qt.rgba(0, 0, 0, 0.18) : icon.hub.bgInput

        Text {
            anchors.centerIn: parent
            text: icon.appName.length > 0 ? icon.appName.charAt(0).toUpperCase() : "?"
            color: icon.highlighted ? icon.hub.onWorkspaceActive : icon.hub.accentPrimary
            font.pixelSize: Math.round(icon.size * 0.48)
            font.bold: true
        }
    }

    Image {
        id: img
        anchors.fill: parent
        source: icon.iconSource
        sourceSize.width: icon.size * 2
        sourceSize.height: icon.size * 2
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        mipmap: true
        opacity: img.status === Image.Ready ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }
}
