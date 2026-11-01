import QtQuick
import QtQuick.Layouts
import Quickshell.Io

Dropdown {
    id: root

    label: "Обои"
    popupHeight: Math.min(list.contentHeight, 300)

    // ------------------------- STATE -------------------------
    property string wallpaperDir: ""

    readonly property int thumbW: 52
    readonly property int thumbH: 30

    property var files: []
    property string currentPath: ""
    property string pendingPath: ""
    property int pendingIndex: -1

    readonly property int currentIndex: root.files.indexOf(root.currentPath)

    function fileUrl(path) {
        return "file://" + path.split("/").map(encodeURIComponent).join("/")
    }

    function baseName(path) {
        const parts = path.split("/")
        return parts[parts.length - 1].replace(/\.[^.]+$/, "")
    }

    function refresh() {
        if (!listProc.running)
            listProc.running = true
    }

    onExpandedChanged: {
        if (root.expanded)
            root.refresh()
    }

    Component.onCompleted: root.refresh()

    // ------------------------- WALLPAPER LOADER -------------------------
    Process {
        id: listProc
        command: ["sh", "-c",
            "d=\"$1\"; [ -n \"$d\" ] || d=\"${XDG_DATA_HOME:-$HOME/.local/share}/snowflake/wallpapers\"; "
            + "case \"$d\" in \"~\"/*) d=\"$HOME/${d#\\~/}\";; esac; "
            + "find \"$d\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \\) 2>/dev/null | sort; "
            + "printf '\\036'; cat \"${XDG_CACHE_HOME:-$HOME/.cache}/hypr/wallpaper\" 2>/dev/null",
            "sh", root.wallpaperDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("\x1e")
                const list = (parts[0] || "").split("\n").map(s => s.trim()).filter(s => s.length > 0)
                if (JSON.stringify(list) !== JSON.stringify(root.files))
                    root.files = list
                root.currentPath = (parts[1] || "").trim()
            }
        }
    }

    // ------------------------- APPLY -------------------------
    Process {
        id: applyProc
        command: ["sh", "-c",
            "s=\"$HOME/.config/hypr/scripts/wallpaper-set.sh\"; "
            + "if [ -f \"$s\" ]; then if [ -x \"$s\" ]; then exec \"$s\" \"$1\"; else exec bash \"$s\" \"$1\"; fi; fi; "
            + "c=\"${XDG_CACHE_HOME:-$HOME/.cache}/hypr\"; mkdir -p \"$c\" || exit 1; "
            + "printf '%s\\n' \"$1\" > \"$c/wallpaper\"; "
            + "[ \"$2\" -ge 0 ] 2>/dev/null && printf '%s\\n' \"$2\" > \"$c/wallpaper_index\"; "
            + "pkill -u \"$(id -u)\" -x swaybg 2>/dev/null; "
            + "if command -v setsid >/dev/null 2>&1; then setsid -f swaybg -i \"$1\" -m fill >/dev/null 2>&1; "
            + "else swaybg -i \"$1\" -m fill >/dev/null 2>&1 & fi",
            "sh", root.pendingPath, String(root.pendingIndex)]
        stdout: SplitParser {
            onRead: (line) => console.log("wallpaper-set:", line)
        }
        stderr: SplitParser {
            onRead: (line) => console.log("wallpaper-set ERR:", line)
        }
        onExited: root.hub.wallpaperTheme.wallpaperApplied(root.pendingPath)
    }

    function applyWallpaper(path, index) {
        root.currentPath = path
        root.pendingPath = path
        root.pendingIndex = index
        root.expanded = false
        applyProc.running = false
        applyProc.running = true
    }

    // ------------------------- HEADER -------------------------
    header: RowLayout {
        anchors.fill: parent
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: root.currentIndex >= 0 ? root.baseName(root.currentPath)
                : (root.files.length === 0 ? "Картинок не найдено" : "Выбрать обои")
            color: root.hub.textMain
            font.pixelSize: 14
            font.bold: true
            elide: Text.ElideMiddle
        }

        Rectangle {
            visible: root.currentIndex >= 0
            implicitWidth: root.thumbW
            implicitHeight: root.thumbH
            radius: 5
            clip: true
            color: root.hub.bgInput

            Image {
                anchors.fill: parent
                source: root.currentIndex >= 0 ? root.fileUrl(root.currentPath) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: root.thumbW * 2
                sourceSize.height: root.thumbH * 2
            }
        }
    }

    // ------------------------- WALLPAPER LIST -------------------------
    ListView {
        id: list
        anchors.fill: parent
        model: root.files
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        SmoothScroll { flick: list }

        delegate: Rectangle {
            id: wallRow
            required property var modelData
            required property int index
            readonly property bool isCurrent: wallRow.index === root.currentIndex

            width: list.width
            height: root.headerHeight
            color: wallArea.containsMouse ? root.hub.hoverColor
                 : wallRow.isCurrent ? Qt.rgba(1, 1, 1, 0.04) : "transparent"

            Behavior on color { ColorAnimation { duration: 120 } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: root.slotLeft
                anchors.rightMargin: root.slotRight
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: root.baseName(wallRow.modelData)
                    color: wallRow.isCurrent ? root.hub.accentPrimary : root.hub.textMain
                    font.pixelSize: 14
                    font.bold: wallRow.isCurrent
                    elide: Text.ElideMiddle
                }

                Rectangle {
                    implicitWidth: root.thumbW
                    implicitHeight: root.thumbH
                    radius: 5
                    clip: true
                    color: root.hub.bgInput

                    Image {
                        anchors.fill: parent
                        source: root.fileUrl(wallRow.modelData)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: root.thumbW * 2
                        sourceSize.height: root.thumbH * 2
                    }
                }
            }

            MouseArea {
                id: wallArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.applyWallpaper(wallRow.modelData, wallRow.index)
            }
        }
    }
}
