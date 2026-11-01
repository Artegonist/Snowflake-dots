import QtQuick
import QtQuick.Layouts
import Quickshell.Io

ColumnLayout {
    id: root

    // ------------------------- STATE -------------------------
    required property var hub

    spacing: 8

    readonly property int maxCities: 8
    readonly property var defaultCities: [
        { label: "Токио",    zone: "Asia/Tokyo",       utcOffset: 9 },
        { label: "Лондон",   zone: "Europe/London",    utcOffset: 0 },
        { label: "Нью-Йорк", zone: "America/New_York", utcOffset: -5 }
    ]
    property var cities: root.defaultCities

    property var offsets: ({})
    property double nowMs: Date.now()

    function pad(n) { return n < 10 ? "0" + n : "" + n }

    function zoneLabel(zone) {
        return String(zone).split("/").pop().replace(/_/g, " ")
    }

    function offsetFor(city, offsets) {
        const m = offsets[city.zone]
        if (m !== undefined) return m
        return city.utcOffset !== undefined ? city.utcOffset * 60 : undefined
    }

    function cityInfo(city, nowMs, offsets) {
        const off = root.offsetFor(city, offsets)
        if (off === undefined)
            return { hm: "--:--", night: false, sub: city.zone }

        const t = new Date(nowMs + off * 60000)
        const h = t.getUTCHours()

        const local = new Date(nowMs)
        const localKey = local.getFullYear() * 10000 + local.getMonth() * 100 + local.getDate()
        const cityKey = t.getUTCFullYear() * 10000 + t.getUTCMonth() * 100 + t.getUTCDate()

        const diff = off + local.getTimezoneOffset()
        let diffText = "как здесь"
        if (diff !== 0) {
            const a = Math.abs(diff)
            diffText = (diff > 0 ? "+" : "−") + Math.floor(a / 60) + (a % 60 ? ":" + root.pad(a % 60) : "") + " ч"
        }
        const dayText = cityKey > localKey ? " · завтра" : cityKey < localKey ? " · вчера" : ""

        return {
            hm: root.pad(h) + ":" + root.pad(t.getUTCMinutes()),
            night: h < 7 || h >= 20,
            sub: diffText + dayText
        }
    }

    // ------------------------- CITY LIST STORAGE -------------------------
    JsonFile {
        id: citiesFile
        path: root.hub.dataDir + "/worldclock.json"
        legacyPath: ".config/hub-module/worldclock.json"
        onLoaded: function(v) {
            if (v && Array.isArray(v.cities)) {
                root.cities = v.cities
                    .filter(c => c && typeof c.zone === "string" && c.zone.length > 0)
                    .slice(0, root.maxCities)
                    .map(c => ({ label: String(c.label || root.zoneLabel(c.zone)), zone: c.zone }))
            }
            root.refreshOffsets()
        }
    }

    function save() {
        citiesFile.save({ cities: root.cities.map(c => ({ label: c.label, zone: c.zone })) })
    }

    function addCity(label, zone) {
        zone = String(zone || "").trim()
        label = String(label || "").trim() || root.zoneLabel(zone)
        if (zone === "") return "Выберите часовой пояс"
        if (root.cities.length >= root.maxCities) return "Не больше " + root.maxCities + " городов"
        if (root.cities.some(c => c.zone === zone && c.label === label)) return "Такой город уже есть"
        root.cities = root.cities.concat([{ label: label, zone: zone }])
        root.save()
        root.refreshOffsets()
        return ""
    }

    function removeCity(index) {
        const list = root.cities.slice()
        list.splice(index, 1)
        root.cities = list
        root.save()
    }

    function moveCity(index, delta) {
        const to = index + delta
        if (to < 0 || to >= root.cities.length) return
        const list = root.cities.slice()
        const item = list.splice(index, 1)[0]
        list.splice(to, 0, item)
        root.cities = list
        root.save()
    }

    // ------------------------- OFFSETS -------------------------
    Process {
        id: offsetsProc
        command: ["sh", "-c",
            "for z in \"$@\"; do [ -e \"/usr/share/zoneinfo/$z\" ] || continue; "
            + "printf '%s %s\\n' \"$z\" \"$(TZ=\"$z\" date +%z)\"; done",
            "sh"].concat(root.cities.map(c => c.zone))
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {}
                for (const line of text.split("\n")) {
                    const m = line.trim().match(/^(\S+)\s+([+-])(\d{2})(\d{2})$/)
                    if (!m)
                        continue
                    const mins = parseInt(m[3], 10) * 60 + parseInt(m[4], 10)
                    map[m[1]] = m[2] === "-" ? -mins : mins
                }
                root.offsets = map
            }
        }
    }

    function refreshOffsets() {
        offsetsProc.running = false
        offsetsProc.running = true
    }

    Component.onCompleted: citiesFile.load()

    Connections {
        target: root.hub
        function onExpandedChanged() {
            if (root.hub.expanded)
                root.refreshOffsets()
        }
    }

    Timer {
        interval: 1000
        running: root.hub.expanded
        repeat: true
        triggeredOnStart: true
        onTriggered: root.nowMs = Date.now()
    }

    // ------------------------- CITY LIST -------------------------
    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 52
        visible: root.cities.length > 0
        model: root.cities
        spacing: 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        SmoothScroll { flick: list }

        delegate: Rectangle {
            id: cityRow
            required property var modelData
            readonly property var info: root.cityInfo(cityRow.modelData, root.nowMs, root.offsets)

            width: list.width
            height: 52
            radius: 10
            color: rowHover.hovered ? Qt.lighter(root.hub.bgTrack, 1.18) : root.hub.bgTrack

            Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }

            HoverHandler { id: rowHover }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        Layout.fillWidth: true
                        text: cityRow.modelData.label
                        color: root.hub.textMain
                        font.pixelSize: 14
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: cityRow.info.sub
                        color: root.hub.textDim
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                Text {
                    text: cityRow.info.night ? "󰖔" : "󰖙"
                    font.family: root.hub.iconFont
                    font.pixelSize: 15
                    color: cityRow.info.night ? root.hub.textDim : root.hub.accentPrimary
                }

                Text {
                    text: cityRow.info.hm
                    color: root.hub.textMain
                    font.bold: true
                    font.pixelSize: 20
                    font.family: root.hub.monoFont
                }
            }
        }
    }

    // ------------------------- EMPTY STATE -------------------------
    Rectangle {
        Layout.fillWidth: true
        visible: root.cities.length === 0
        implicitHeight: 52
        radius: 10
        color: emptyHover.hovered ? Qt.lighter(root.hub.bgTrack, 1.18) : root.hub.bgTrack

        HoverHandler { id: emptyHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.hub.openSettings("clock") }

        Text {
            anchors.centerIn: parent
            text: "Добавить города — в настройках"
            color: root.hub.textDim
            font.pixelSize: 13
        }
    }

    Item {
        visible: root.cities.length === 0
        Layout.fillHeight: true
    }
}
