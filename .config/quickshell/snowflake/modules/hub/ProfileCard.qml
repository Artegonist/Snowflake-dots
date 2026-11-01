import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Rectangle {
    id: root

    // ------------------------- STATE -------------------------
    required property var hub

    implicitHeight: content.implicitHeight + 24
    radius: 10
    color: root.hub.bgTrack

    readonly property string repoUrl: "https://github.com/Artegonist/Snowflake-dots"

    property string userName: "—"
    property string realName: ""
    property string hostName: "—"
    property string distroName: "Linux"
    property string distroId: "linux"
    property string distroLike: ""
    property string shellName: ""
    property string packages: "—"
    property string hyprVersion: "—"
    property int hour: new Date().getHours()

    readonly property string displayName: {
        const first = root.realName.trim().split(/\s+/)[0]
        return first ? first : root.userName
    }

    readonly property string compositorText: root.hyprVersion === "—" ? "—"
        : root.hyprVersion === "есть" ? "Hyprland"
        : "Hyprland " + root.hyprVersion

    readonly property string greeting: {
        const h = root.hour
        if (h >= 5 && h < 12) return "Доброе утро"
        if (h >= 12 && h < 18) return "Добрый день"
        if (h >= 18 && h < 23) return "Добрый вечер"
        return "Доброй ночи"
    }

    readonly property string distroGlyph: {
        const map = {
            arch: 0xF303, endeavouros: 0xF322, manjaro: 0xF312, artix: 0xF31F, garuda: 0xF337,
            nixos: 0xF313, fedora: 0xF30A, debian: 0xF306, ubuntu: 0xF31B, linuxmint: 0xF30E,
            pop: 0xF32A, gentoo: 0xF30D, void: 0xF32E, alpine: 0xF300,
            opensuse: 0xF314, "opensuse-tumbleweed": 0xF314, "opensuse-leap": 0xF314
        }
        let code = map[root.distroId]
        if (code === undefined) {
            const like = root.distroLike.split(/\s+/)
            for (const l of like) {
                if (map[l] !== undefined) { code = map[l]; break }
            }
        }
        return String.fromCodePoint(code !== undefined ? code : 0xF31A)
    }

    readonly property string script: [
        "u=$(id -un)",
        "echo \"user=$u\"",
        "echo \"name=$(getent passwd \"$u\" 2>/dev/null | cut -d: -f5 | cut -d, -f1)\"",
        "echo \"host=$( (cat /etc/hostname 2>/dev/null || uname -n) | head -n 1)\"",
        "if [ -r /etc/os-release ]; then . /etc/os-release; fi",
        "echo \"distro=${NAME:-${PRETTY_NAME:-Linux}}\"",
        "echo \"distroId=${ID:-linux}\"",
        "echo \"distroLike=${ID_LIKE:-}\"",
        "echo \"shell=$(basename \"${SHELL:-sh}\")\"",
        "if command -v pacman >/dev/null 2>&1; then echo \"pkgs=$(pacman -Qq 2>/dev/null | wc -l)\"",
        "elif command -v dpkg-query >/dev/null 2>&1; then echo \"pkgs=$(dpkg-query -f '.\\n' -W 2>/dev/null | wc -l)\"",
        "elif command -v rpm >/dev/null 2>&1; then echo \"pkgs=$(rpm -qa 2>/dev/null | wc -l)\"",
        "elif command -v xbps-query >/dev/null 2>&1; then echo \"pkgs=$(xbps-query -l 2>/dev/null | wc -l)\"",
        "fi",
        "echo \"wm=$(hyprctl version -j 2>/dev/null | tr -d '\\n')\""
    ].join("\n")

    // ------------------------- SYSTEM INFO -------------------------
    Process {
        id: infoProc
        command: ["sh", "-c", root.script]
        stdout: StdioCollector {
            onStreamFinished: root.applyInfo(text)
        }
    }

    function applyInfo(text) {
        const info = {}
        for (const line of text.split("\n")) {
            const i = line.indexOf("=")
            if (i > 0) info[line.slice(0, i)] = line.slice(i + 1).trim()
        }
        if (info.user) root.userName = info.user
        root.realName = info.name || ""
        if (info.host) root.hostName = info.host
        if (info.distro) root.distroName = root.shortDistro(info.distro)
        if (info.distroId) root.distroId = info.distroId.toLowerCase()
        root.distroLike = (info.distroLike || "").toLowerCase()
        root.shellName = info.shell || ""
        if (info.pkgs) root.packages = info.pkgs

        let ver = ""
        try {
            const j = JSON.parse(info.wm || "")
            ver = j.version || (j.tag ? String(j.tag).replace(/^v/, "").split("-")[0] : "")
        } catch (e) {
            ver = ""
        }
        root.hyprVersion = ver !== "" ? ver : (info.wm ? "есть" : "—")
    }

    function paletteColor(i) {
        const h = root.hub
        return [h.accentPrimary, h.accentSecondary, h.workspaceActive, h.hoverLight,
                h.textMain, h.textDim, h.bgInput, h.bgPanel][i]
    }

    function shortDistro(name) {
        const s = String(name)
            .replace(/\(.*?\)/g, " ")
            .replace(/GNU\/Linux/gi, " ")
            .replace(/\b(GNU|Linux|LTS)\b/gi, " ")
            .replace(/\s\d[\w.]*/g, " ")
            .replace(/\s+/g, " ")
            .trim()
        return s !== "" ? s : "Linux"
    }

    function refresh() {
        root.hour = new Date().getHours()
        if (!infoProc.running)
            infoProc.running = true
    }

    Component.onCompleted: root.refresh()

    Connections {
        target: root.hub
        function onExpandedChanged() {
            if (root.hub.expanded)
                root.refresh()
        }
    }

    Timer {
        interval: 60000
        running: root.hub.expanded
        repeat: true
        onTriggered: root.hour = new Date().getHours()
    }

    component InfoChip: Rectangle {
        id: chip
        required property var hub
        property string glyph: ""
        property bool logo: false
        property string label: ""
        property string value: "—"
        property string url: ""

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 34
        radius: 8
        color: chipHover.hovered ? Qt.lighter(chip.hub.bgInput, 1.3) : chip.hub.bgInput
        scale: chipTap.pressed ? 0.97 : 1.0

        Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

        HoverHandler {
            id: chipHover
            cursorShape: chip.url !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
        }

        TapHandler {
            id: chipTap
            enabled: chip.url !== ""
            onTapped: {
                Quickshell.execDetached(["xdg-open", chip.url])
                chip.hub.hide()
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8

            Item {
                implicitWidth: 16
                implicitHeight: 16

                Text {
                    anchors.centerIn: parent
                    visible: !chip.logo
                    text: chip.glyph
                    font.family: chip.hub.iconFont
                    font.pixelSize: 15
                    color: chip.hub.accentPrimary
                }

                SnowLogo {
                    anchors.fill: parent
                    visible: chip.logo
                    color: chip.hub.accentPrimary
                }
            }

            Text {
                text: chip.label
                color: chip.hub.textDim
                font.pixelSize: 11
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                text: chip.value
                color: chip.hub.textMain
                font.pixelSize: 13
                font.bold: true
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 10
                elide: Text.ElideRight
            }
        }
    }

    // ------------------------- CONTENT -------------------------
    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 10

        // ------------------------- AVATAR + GREETING + PALETTE -------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            Item {
                id: avatar
                implicitWidth: 60
                implicitHeight: 60
                scale: avatarHover.hovered ? 1.05 : 1.0

                Behavior on scale { Anim { kind: "fast" } }

                HoverHandler { id: avatarHover }

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: avatarHover.hovered ? root.hub.accentSecondary : root.hub.accentPrimary

                    Behavior on border.color { ColorAnimation { duration: 160 } }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 50
                    height: 50
                    radius: 25
                    color: root.hub.bgPanel

                    SnowLogo {
                        anchors.centerIn: parent
                        width: 36
                        height: 36
                        color: root.hub.accentPrimary
                        rotation: avatarHover.hovered ? 60 : 0

                        Behavior on rotation { Anim {} }
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: -4
                    anchors.bottomMargin: -4
                    width: 26
                    height: 26
                    radius: 13
                    color: root.hub.bgPanel
                    border.width: 2
                    border.color: root.color

                    Text {
                        anchors.centerIn: parent
                        text: root.distroGlyph
                        font.family: root.hub.iconFont
                        font.pixelSize: 14
                        color: root.hub.accentPrimary
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: root.greeting + ","
                    color: root.hub.textDim
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: root.displayName
                    color: root.hub.textMain
                    font.pixelSize: 20
                    font.bold: true
                    elide: Text.ElideRight
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        Layout.fillWidth: true
                        Layout.maximumWidth: implicitWidth
                        text: root.userName + "@" + root.hostName
                        color: root.hub.accentPrimary
                        font.pixelSize: 12
                        font.family: root.hub.monoFont
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: root.shellName !== ""
                        text: "󰆍"
                        color: root.hub.textDim
                        font.pixelSize: 13
                        font.family: root.hub.iconFont
                    }

                    Text {
                        visible: root.shellName !== ""
                        text: root.shellName
                        color: root.hub.textDim
                        font.pixelSize: 12
                    }

                    Item { Layout.fillWidth: true }
                }
            }

            Grid {
                Layout.alignment: Qt.AlignVCenter
                columns: 4
                spacing: 5

                Repeater {
                    model: 8

                    delegate: Rectangle {
                        required property int index
                        width: 11
                        height: 11
                        radius: 3
                        color: root.paletteColor(index)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.08)
                    }
                }
            }
        }

        // ------------------------- SYSTEM -------------------------
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: 6
            columnSpacing: 6

            InfoChip { hub: root.hub; glyph: root.distroGlyph; label: "Система"; value: root.distroName }
            InfoChip { hub: root.hub; logo: true; label: "Райс"; value: "Snowflake"; url: root.repoUrl }
            InfoChip { hub: root.hub; glyph: "󰍹"; label: "Композитор"; value: root.compositorText }
            InfoChip { hub: root.hub; glyph: "󰏖"; label: "Пакеты"; value: root.packages }
        }
    }
}
