import QtQuick
import QtQuick.Layouts
import Quickshell.Io

ColumnLayout {
    id: root

    // ------------------------- STATE -------------------------
    required property var hub

    spacing: 12

    property string uptimeText: "—"
    property string weeklyAvgText: "—"
    property string bootText: "—"
    property real uptimeSeconds: 0
    property var todayApps: ({})
    property var todayHours: root.zeroHours()
    property string todayDateStr: ""
    property int currentHour: new Date().getHours()

    property var rebootIntervals: []
    property var weekDays: []
    property int bootsWeek: 0

    readonly property int sampleSeconds: 20

    Connections {
        target: root.hub
        function onExpandedChanged() {
            if (root.hub.expanded) {
                root.refreshUptime()
                root.refreshWeeklyAverage()
            }
        }
    }

    function formatHM(totalSeconds) {
        const h = Math.floor(totalSeconds / 3600)
        const m = Math.floor((totalSeconds % 3600) / 60)
        if (h > 0) return h + "ч " + m + "м"
        return m + "м"
    }

    function pad2(n) { return n < 10 ? "0" + n : "" + n }

    function zeroHours() {
        const a = []
        for (let i = 0; i < 24; i++) a.push(0)
        return a
    }

    function todayKey() {
        const t = new Date()
        return t.getFullYear() + "-" + String(t.getMonth() + 1).padStart(2, "0") + "-" + String(t.getDate()).padStart(2, "0")
    }

    readonly property var monthsShort: ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]
    readonly property var dayNames: ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]

    readonly property var allAppsSorted: {
        const entries = Object.entries(root.todayApps)
        entries.sort((a, b) => b[1] - a[1])
        return entries
    }
    readonly property var topApps: root.allAppsSorted.slice(0, 3)
    readonly property real topMax: root.allAppsSorted.length > 0 ? root.allAppsSorted[0][1] : 0
    readonly property real focusTotal: {
        let s = 0
        for (const k in root.todayApps) s += root.todayApps[k]
        return s
    }

    readonly property real weekTotal: root.weekDays.reduce((s, d) => s + d.secs, 0)
    readonly property real weekMax: root.weekDays.reduce((m, d) => Math.max(m, d.secs), 0)
    readonly property int peakHour: {
        let best = -1, v = 0
        for (let i = 0; i < 24; i++)
            if (root.todayHours[i] > v) { v = root.todayHours[i]; best = i }
        return best
    }

    // ------------------------- UPTIME -------------------------
    Process {
        id: uptimeProc
        command: ["cat", "/proc/uptime"]
        stdout: StdioCollector {
            onStreamFinished: {
                const seconds = parseFloat(text.trim().split(" ")[0])
                if (!isNaN(seconds)) {
                    root.uptimeSeconds = seconds
                    root.uptimeText = root.formatHM(seconds)
                    root.bootText = root.bootLabel(new Date(Date.now() - seconds * 1000))
                    root.rebuildWeek()
                }
            }
        }
    }

    function refreshUptime() {
        root.currentHour = new Date().getHours()
        if (!uptimeProc.running)
            uptimeProc.running = true
    }

    function bootLabel(d) {
        const t = new Date()
        const hm = root.pad2(d.getHours()) + ":" + root.pad2(d.getMinutes())
        const day0 = new Date(t.getFullYear(), t.getMonth(), t.getDate()).getTime()
        if (d.getTime() >= day0) return "сегодня в " + hm
        if (d.getTime() >= day0 - 86400000) return "вчера в " + hm
        return d.getDate() + " " + root.monthsShort[d.getMonth()] + " в " + hm
    }

    // ------------------------- BOOT HISTORY -------------------------
    Process {
        id: lastRebootProc
        command: ["sh", "-c", "last reboot -F -100 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.rebootIntervals = root.parseReboots(text)
                root.rebuildWeek()
            }
        }
    }

    function refreshWeeklyAverage() {
        if (!lastRebootProc.running)
            lastRebootProc.running = true
    }

    readonly property var monthMap: ({
        Jan: 0, Feb: 1, Mar: 2, Apr: 3, May: 4, Jun: 5,
        Jul: 6, Aug: 7, Sep: 8, Oct: 9, Nov: 10, Dec: 11
    })

    function parseLastDate(str) {
        const parts = str.trim().split(/\s+/)
        if (parts.length < 5) return null
        const month = root.monthMap[parts[1]]
        const day = parseInt(parts[2])
        const timeParts = parts[3].split(":")
        const year = parseInt(parts[4])
        if (month === undefined || isNaN(day) || timeParts.length !== 3 || isNaN(year)) return null
        return new Date(year, month, day, parseInt(timeParts[0]), parseInt(timeParts[1]), parseInt(timeParts[2]))
    }

    function parseReboots(text) {
        const lineRe = /^reboot\s+system boot\s+\S+\s+(\w{3}\s+\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}\s+\d{4})\s+-\s+(.*)$/
        const list = []
        for (const line of text.split("\n")) {
            const m = line.match(lineRe)
            if (!m) continue

            const start = root.parseLastDate(m[1])
            if (!start) continue

            const rest = m[2].trim()
            if (rest.startsWith("still running")) {
                list.push({ start: start.getTime(), end: -1 })
                continue
            }
            const endMatch = rest.match(/^(\w{3}\s+\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}\s+\d{4})/)
            if (!endMatch) continue
            const end = root.parseLastDate(endMatch[1])
            if (!end) continue
            list.push({ start: start.getTime(), end: end.getTime() })
        }
        return list
    }

    function intervals() {
        if (root.rebootIntervals.length > 0) return root.rebootIntervals
        if (root.uptimeSeconds > 0) return [{ start: Date.now() - root.uptimeSeconds * 1000, end: -1 }]
        return []
    }

    function rebuildWeek() {
        const now = Date.now()
        const list = root.intervals()
        const t = new Date()

        const windowStart = now - 7 * 24 * 3600 * 1000
        let rolling = 0
        for (const iv of list) {
            const a = Math.max(iv.start, windowStart)
            const b = Math.min(iv.end < 0 ? now : iv.end, now)
            if (b > a) rolling += (b - a) / 1000
        }
        root.weeklyAvgText = list.length > 0 ? root.formatHM(rolling / 7) : "—"

        const days = []
        for (let d = 6; d >= 0; d--) {
            const day = new Date(t.getFullYear(), t.getMonth(), t.getDate() - d)
            const s = day.getTime()
            const e = new Date(t.getFullYear(), t.getMonth(), t.getDate() - d + 1).getTime()
            let secs = 0
            for (const iv of list) {
                const a = Math.max(iv.start, s)
                const b = Math.min(iv.end < 0 ? now : iv.end, e, now)
                if (b > a) secs += (b - a) / 1000
            }
            days.push({
                label: root.dayNames[day.getDay()],
                title: root.dayNames[day.getDay()] + ", " + day.getDate() + " " + root.monthsShort[day.getMonth()],
                secs: secs,
                today: d === 0
            })
        }
        root.weekDays = days

        const weekStart = new Date(t.getFullYear(), t.getMonth(), t.getDate() - 6).getTime()
        root.bootsWeek = list.filter(iv => iv.start >= weekStart).length
    }

    // ------------------------- ACTIVE WINDOW SAMPLER -------------------------
    Process {
        id: activeWinProc
        command: ["sh", "-c", "hyprctl activewindow -j 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text)
                    const cls = data.class
                    if (cls && cls.length > 0) {
                        const apps = Object.assign({}, root.todayApps)
                        apps[cls] = (apps[cls] || 0) + root.sampleSeconds
                        root.todayApps = apps

                        const hours = root.todayHours.slice()
                        const h = new Date().getHours()
                        hours[h] = (hours[h] || 0) + root.sampleSeconds
                        root.todayHours = hours

                        root.saveAppUsage()
                    }
                } catch (e) {
                }
            }
        }
    }

    JsonFile {
        id: usageFile
        path: root.hub.dataDir + "/app_usage.json"
        legacyPath: ".cache/hub-module/app_usage.json"
        onLoaded: function(value) {
            root.todayDateStr = root.todayKey()
            const sameDay = value && value.date === root.todayDateStr
            root.todayApps = sameDay && value.apps ? value.apps : {}
            root.todayHours = sameDay && Array.isArray(value.hours) && value.hours.length === 24
                ? value.hours.map(v => Number(v) || 0)
                : root.zeroHours()
        }
    }

    function saveAppUsage() {
        usageFile.save({ date: root.todayDateStr, apps: root.todayApps, hours: root.todayHours })
    }

    Component.onCompleted: {
        refreshUptime()
        refreshWeeklyAverage()
        usageFile.load()
    }

    Timer { interval: 30000; running: root.hub.expanded; repeat: true; onTriggered: root.refreshUptime() }
    Timer { interval: 300000; running: root.hub.expanded; repeat: true; onTriggered: root.refreshWeeklyAverage() }

    Timer {
        interval: root.sampleSeconds * 1000
        running: true
        repeat: true
        onTriggered: {
            const key = root.todayKey()
            if (key !== root.todayDateStr) {
                root.todayDateStr = key
                root.todayApps = {}
                root.todayHours = root.zeroHours()
            }
            if (!activeWinProc.running)
                activeWinProc.running = true
        }
    }

    // ------------------------- VIEW -------------------------
    readonly property bool shown: root.hub.expanded && root.hub.currentPage === 1
    property real reveal: 1
    onShownChanged: if (root.shown) revealAnim.restart()

    NumberAnimation {
        id: revealAnim
        target: root
        property: "reveal"
        from: 0
        to: 1
        duration: 900
        easing.type: Easing.OutCubic
    }

    function appearAt(frac) {
        return Math.max(0, Math.min(1, (root.reveal - frac * 0.45) / 0.55))
    }

    property int weekHover: -1
    property int hourHover: -1

    component StatTile: Rectangle {
        id: tile
        required property var hub
        property string value: ""
        property string label: ""

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 64
        radius: 10
        color: tile.hub.bgTrack

        Column {
            anchors.centerIn: parent
            width: parent.width - 16
            spacing: 3

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: tile.value
                color: tile.hub.accentPrimary
                font.pixelSize: 18
                font.bold: true
                font.family: tile.hub.monoFont
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: tile.label
                color: tile.hub.textDim
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }
    }

    // ------------------------- BIG UPTIME -------------------------
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.uptimeText
            color: root.hub.textMain
            font.pixelSize: 44
            font.bold: true
            font.family: root.hub.monoFont
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.bootText !== "—" ? "Аптайм системы · включён " + root.bootText : "аптайм системы"
            color: root.hub.textDim
            font.pixelSize: 13
            elide: Text.ElideRight
        }
    }

    // ------------------------- STATS -------------------------
    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        StatTile { hub: root.hub; value: root.weeklyAvgText; label: "в среднем за день" }
        StatTile { hub: root.hub; value: String(root.bootsWeek); label: "загрузок за неделю" }
        StatTile { hub: root.hub; value: root.formatHM(root.focusTotal); label: "в фокусе сегодня" }
    }

    // ------------------------- WEEK CHART -------------------------
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.topMargin: 4
        spacing: 6

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "За неделю"
                color: root.hub.textDim
                font.pixelSize: 13
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            Text {
                readonly property var d: root.weekHover >= 0 ? root.weekDays[root.weekHover] : null
                text: d ? d.title + " · " + root.formatHM(d.secs) : "всего " + root.formatHM(root.weekTotal)
                color: d ? root.hub.textMain : root.hub.textDim
                font.pixelSize: 12
            }
        }

        Item {
            id: weekChart
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 120

            RowLayout {
                anchors.fill: parent
                spacing: 10

                Repeater {
                    model: 7

                    delegate: ColumnLayout {
                        id: dayCol
                        required property int index
                        readonly property var d: root.weekDays[dayCol.index] || ({ label: "", title: "", secs: 0, today: false })
                        readonly property real frac: root.weekMax > 0 ? dayCol.d.secs / root.weekMax : 0
                        readonly property bool hovered: dayHoverHandler.hovered

                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true
                        spacing: 6

                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: dayCol.d.secs > 0 ? root.formatHM(dayCol.d.secs) : "—"
                            color: dayCol.d.today || dayCol.hovered ? root.hub.accentPrimary : root.hub.textDim
                            font.pixelSize: 11
                            font.bold: dayCol.d.today
                            elide: Text.ElideRight
                            opacity: root.appearAt(dayCol.index / 6)
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            HoverHandler {
                                id: dayHoverHandler
                                onHoveredChanged: {
                                    if (hovered) root.weekHover = dayCol.index
                                    else if (root.weekHover === dayCol.index) root.weekHover = -1
                                }
                            }

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.min(40, parent.width)
                                height: parent.height
                                radius: 8
                                color: root.hub.bgTrack
                                opacity: dayCol.hovered ? 1 : 0.6

                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.min(40, parent.width)
                                height: dayCol.d.secs > 0 ? Math.max(6, dayCol.frac * parent.height * root.appearAt(dayCol.index / 6)) : 0
                                radius: 8
                                opacity: dayCol.d.today || dayCol.hovered ? 1 : 0.55

                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: root.hub.accentPrimary }
                                    GradientStop { position: 1.0; color: root.hub.accentSecondary }
                                }

                                Behavior on height { enabled: !revealAnim.running; Anim { kind: "slow" } }
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: dayCol.d.today ? "сег" : dayCol.d.label
                            color: dayCol.d.today ? root.hub.textMain : root.hub.textDim
                            font.pixelSize: 12
                            font.bold: dayCol.d.today
                        }
                    }
                }
            }
        }
    }

    // ------------------------- TODAY BY HOUR -------------------------
    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 6

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "Сегодня по часам"
                color: root.hub.textDim
                font.pixelSize: 13
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            Text {
                text: root.hourHover >= 0
                    ? root.pad2(root.hourHover) + ":00–" + root.pad2((root.hourHover + 1) % 24) + ":00 · "
                      + root.formatHM(root.todayHours[root.hourHover] || 0)
                    : root.peakHour >= 0 ? "пик — " + root.pad2(root.peakHour) + ":00"
                    : "копится каждые " + root.sampleSeconds + " с"
                color: root.hourHover >= 0 ? root.hub.textMain : root.hub.textDim
                font.pixelSize: 12
            }
        }

        Item {
            id: hourChart
            Layout.fillWidth: true
            Layout.preferredHeight: 96
            Layout.minimumHeight: 96

            readonly property real gap: 3
            readonly property real barW: (hourChart.width - 23 * hourChart.gap) / 24
            readonly property real areaH: hourChart.height - 18

            Repeater {
                model: 24

                delegate: Item {
                    id: hourCol
                    required property int index
                    readonly property real v: Math.min(3600, root.todayHours[hourCol.index] || 0)
                    readonly property bool current: hourCol.index === root.currentHour
                    readonly property bool hovered: hourHoverHandler.hovered

                    x: hourCol.index * (hourChart.barW + hourChart.gap)
                    width: hourChart.barW
                    height: hourChart.areaH

                    HoverHandler {
                        id: hourHoverHandler
                        onHoveredChanged: {
                            if (hovered) root.hourHover = hourCol.index
                            else if (root.hourHover === hourCol.index) root.hourHover = -1
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 3
                        color: root.hub.bgTrack
                        opacity: hourCol.hovered ? 1 : 0.55
                        border.width: hourCol.current ? 1 : 0
                        border.color: root.hub.accentPrimary

                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: hourCol.v > 0 ? Math.max(3, hourCol.v / 3600 * parent.height * root.appearAt(hourCol.index / 23)) : 0
                        radius: 3
                        color: hourCol.current || hourCol.hovered ? root.hub.accentPrimary : root.hub.accentSecondary

                        Behavior on height { enabled: !revealAnim.running; NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }
            }

            Repeater {
                model: [0, 6, 12, 18, 23]

                delegate: Text {
                    required property var modelData
                    readonly property real cx: modelData * (hourChart.barW + hourChart.gap) + hourChart.barW / 2

                    x: Math.max(0, Math.min(hourChart.width - width, cx - width / 2))
                    y: hourChart.areaH + 4
                    text: root.pad2(modelData)
                    color: modelData === root.currentHour ? root.hub.accentPrimary : root.hub.textDim
                    font.pixelSize: 10
                    font.family: root.hub.monoFont
                }
            }
        }
    }
}
