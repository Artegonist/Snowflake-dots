import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

PanelWindow {
    id: root

    //----------------WINDOW----------------
    visible: false
    focusable: true
    WlrLayershell.keyboardFocus: root.expanded ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    property bool expanded: false
    property bool closing: false

    function show() {
        root.closing = false
        if (!root.visible)
            root.visible = true
        focusGrab.active = true
        root.mask = null
        if (!root.expanded)
            root.resetSampling()
        root.expanded = true
    }

    function hide() {
        if (!root.expanded || root.closing)
            return
        root.closing = true
        focusGrab.active = false
        root.mask = emptyRegion
        root.expanded = false
    }

    function toggle() {
        if (root.expanded && !root.closing)
            hide()
        else
            show()
    }

    Region {
        id: emptyRegion
        x: 0
        y: 0
        width: 0
        height: 0
    }

    anchors {
        top: true
        right: true
    }

    margins {
        top: 30
        right: 390
    }

    exclusionMode: ExclusionMode.Ignore

    color: "transparent"
    implicitWidth: 420
    implicitHeight: 540

    //----------------COLORS----------------
    readonly property color accentPrimary: "{{theme.accent_primary.hex}}"
    readonly property color accentSecondary: "{{theme.accent_secondary.hex}}"
    readonly property color bgPanel: "{{theme.bg_panel_battery.hex}}"
    readonly property color bgTrack: "{{theme.bg_track.hex}}"
    readonly property color borderColor: "{{theme.accent_primary.hex}}"
    readonly property color separatorColor: Qt.rgba(1, 1, 1, 0.08)
    readonly property color textMain: "{{theme.text_main.hex}}"
    readonly property color textDim: "{{theme.text_dim.hex}}"
    readonly property color danger: "#c96a5a"

    //----------------SETTINGS----------------
    property string diskMount: "/"
    property string tempSensorPath: ""
    property int pollIntervalMs: 2000
    property int procIntervalMs: 4000
    property real tempSmoothing: 0.25
    property string terminalCommand: "kitty -e btop"
    property real warnFraction: 0.9
    property int warnTemp: 85
    property bool showGpu: true


    property real gpuFactor: root.showGpu ? 1 : 0
    Behavior on gpuFactor { NumberAnimation { duration: 380; easing.type: Easing.InOutCubic } }

    //----------------PERSISTENT STATE----------------
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
                                       + "/quickshell/system-info"
    property bool _stateReady: false

    function saveState() {
        if (!root._stateReady)
            return
        Quickshell.execDetached([
            "bash", "-c", 'mkdir -p "$1" && printf %s "$2" > "$1/settings.json"',
            "sysinfo", root.stateDir, JSON.stringify({ showGpu: root.showGpu })
        ])
    }

    onShowGpuChanged: root.saveState()

    Process {
        id: stateLoader
        running: true
        command: ["bash", "-c", 'cat "$1/settings.json" 2>/dev/null', "sysinfo", root.stateDir]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    if (typeof d.showGpu === "boolean")
                        root.showGpu = d.showGpu
                } catch (e) {
                }
                root._stateReady = true
            }
        }
    }

    //----------------VALUES----------------
    property real cpuUsage: 0
    property real ramUsage: 0
    property real ramUsedGB: 0
    property real ramTotalGB: 0
    property int  cpuTemp: 0
    property real netDownKBs: 0
    property real netUpKBs: 0
    property real diskUsage: 0
    property real diskUsedGB: 0
    property real diskTotalGB: 0
    property real gpuUsage: -1
    property var  topProcesses: []
    property string windowList: ""
    property var _prevCpu: null
    property var _prevNet: null
    property int _tick: 0
    property real _tempAvg: -1

    function resetSampling() {
        root._prevCpu = null
        root._prevNet = null
        root._tempAvg = -1
        root._tick = 0
    }

    function clamp01(v) {
        return Math.max(0, Math.min(1, v))
    }

    function buildWindowList() {
        const out = []
        try {
            const tl = Hyprland.toplevels.values
            for (let i = 0; i < tl.length; i++) {
                const o = tl[i].lastIpcObject
                if (o && o.pid > 0 && o["class"])
                    out.push(o.pid + " " + o["class"])
            }
        } catch (e) {
            console.warn("[sysinfo] window list failed:", e)
        }
        return out.join("\n")
    }

    function fmtRate(kbs) {
        if (kbs >= 1024)
            return (kbs / 1024).toFixed(1) + " MB/s"
        return Math.round(kbs) + " KB/s"
    }

    //----------------DATA COLLECTION----------------

    readonly property string statScript: [
        "exec 2>/dev/null",
        "export LC_ALL=C",
        "read -r _ u n s i w q sq st _ < /proc/stat",
        "echo \"cpu $u $n $s $i $w $q $sq $st\"",
        "awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{print \"mem\", t+0, a+0}' /proc/meminfo",
        "awk 'NR>2{sub(/:/,\" \"); if ($1 !~ /^(lo|docker|veth|br-|virbr)/) {rx+=$2; tx+=$10} } END{print \"net\", rx+0, tx+0}' /proc/net/dev",
        "t=",
        "[ -n \"$2\" ] && t=$(<\"$2\")",
        "if [ -z \"$t\" ]; then",
        "  for h in /sys/class/hwmon/hwmon*; do",
        "    case $(<\"$h/name\") in k10temp|coretemp|zenpower) t=$(<\"$h/temp1_input\"); break;; esac",
        "  done",
        "fi",
        "if [ -z \"$t\" ]; then",
        "  for z in /sys/class/thermal/thermal_zone*; do",
        "    case $(<\"$z/type\") in x86_pkg_temp|cpu*|k10temp*) t=$(<\"$z/temp\"); break;; esac",
        "  done",
        "fi",
        "[ -z \"$t\" ] && t=$(<\"/sys/class/thermal/thermal_zone0/temp\")",
        "echo \"temp ${t:-0}\"",
        "df -B1 --output=used,avail -- \"$1\" | awk 'NR==2{print \"disk\", $1+$2, $1}'",
        "g=",
        "if [ \"$3\" != 0 ]; then",
        "  for f in /sys/class/drm/card*/device/gpu_busy_percent; do",
        "    [ -r \"$f\" ] && { g=$(<\"$f\"); break; }",
        "  done",
        "  if [ -z \"$g\" ] && command -v nvidia-smi >/dev/null; then",
        "    g=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | head -n1)",
        "  fi",
        "fi",
        "g=${g//[^0-9]/}",
        "echo \"gpu ${g:--1}\""
    ].join("\n")

    readonly property string procScript: [
        "export LC_ALL=C",
        "snap() {",
        "  awk '{ s=$0; a=index(s,\"(\"); match(s,/[)][^)]*$/); n=split(substr(s,RSTART+2),f,\" \"); print $1, f[2], f[12]+f[13], substr(s,a+1,RSTART-a-1) }' /proc/[0-9]*/stat 2>/dev/null",
        "}",
        "wins() {",
        "  hyprctl clients 2>/dev/null | awk '/^[[:space:]]*class: /{c=$0; sub(/^[[:space:]]*class: /,\"\",c)} /^[[:space:]]*pid: /{ if (c != \"\") print $2, c; c=\"\" }'",
        "}",
        "w=$1",
        "[ -z \"$w\" ] && w=$(wins)",
        "[ -z \"$w\" ] && exit 0",
        "read -r t1 _ < /proc/uptime; a=$(snap)",
        "sleep 0.5",
        "read -r t2 _ < /proc/uptime; b=$(snap)",
        "hz=$(getconf CLK_TCK)",
        "{ echo \"$w\" | sed 's/^/W /'; echo \"$a\" | sed 's/^/A /'; echo \"$b\" | sed 's/^/B /'; } |",
        "awk -v dt=\"$(awk -v x=\"$t1\" -v y=\"$t2\" 'BEGIN{print y-x}')\" -v hz=\"${hz:-100}\" '",
        "  $1==\"W\" && NF>=3 { c=$0; sub(/^W [0-9]+ /,\"\",c); cls[$2]=c; next }",
        "  $1==\"A\" { ta[$2]=$4; next }",
        "  $1==\"B\" { tb[$2]=$4; pp[$2]=$3; next }",
        "  END {",
        "    for (w in cls) sum[cls[w]] += 0",
        "    for (p in tb) {",
        "      if (!(p in ta) || tb[p] <= ta[p]) continue",
        "      q=p; app=\"\"",
        "      for (d=0; d<40; d++) {",
        "        if (q in cls) { app=cls[q]; break }",
        "        if (!(q in pp) || pp[q] <= 1) break",
        "        q=pp[q]",
        "      }",
        "      if (app != \"\") sum[app] += tb[p]-ta[p]",
        "    }",
        "    for (app in sum) print sprintf(\"%.1f\", sum[app]/(dt*hz)*100) \" \" app",
        "  }' | sort -rn | head -n 3"
    ].join("\n")

    function applyStat(raw) {
        const lines = raw.split("\n")
        for (let i = 0; i < lines.length; i++) {
            const p = lines[i].trim().split(/\s+/)
            const key = p[0]

            if (key === "cpu" && p.length >= 5) {
                const v = p.slice(1).map(Number)
                const idle = v[3] + v[4]
                const total = v.reduce((a, b) => a + b, 0)
                if (root._prevCpu) {
                    const dTotal = total - root._prevCpu.total
                    const dIdle = idle - root._prevCpu.idle
                    if (dTotal > 0)
                        root.cpuUsage = root.clamp01(1 - dIdle / dTotal)
                }
                root._prevCpu = { idle: idle, total: total }

            } else if (key === "mem" && p.length >= 3) {
                const total = Number(p[1])
                const avail = Number(p[2])
                if (total > 0) {
                    root.ramUsage = root.clamp01(1 - avail / total)
                    root.ramTotalGB = total / 1024 / 1024
                    root.ramUsedGB = (total - avail) / 1024 / 1024
                }

            } else if (key === "net" && p.length >= 3) {
                const now = Date.now()
                const rx = Number(p[1]) || 0
                const tx = Number(p[2]) || 0
                if (root._prevNet) {
                    const dt = (now - root._prevNet.time) / 1000
                    if (dt > 0) {
                        root.netDownKBs = Math.max(0, (rx - root._prevNet.rx) / 1024 / dt)
                        root.netUpKBs = Math.max(0, (tx - root._prevNet.tx) / 1024 / dt)
                    }
                }
                root._prevNet = { rx: rx, tx: tx, time: now }

            } else if (key === "temp" && p.length >= 2) {
                let t = Number(p[1])
                if (isNaN(t) || t <= 0) {
                    root._tempAvg = -1
                    root.cpuTemp = 0
                } else {
                    if (t >= 1000)
                        t = t / 1000
                    root._tempAvg = root._tempAvg < 0
                            ? t
                            : root._tempAvg + (t - root._tempAvg) * root.tempSmoothing
                    root.cpuTemp = Math.round(root._tempAvg)
                }

            } else if (key === "disk" && p.length >= 3) {
                const total = Number(p[1])
                const used = Number(p[2])
                if (total > 0) {
                    root.diskUsage = root.clamp01(used / total)
                    root.diskTotalGB = total / 1024 / 1024 / 1024
                    root.diskUsedGB = used / 1024 / 1024 / 1024
                }

            } else if (key === "gpu" && p.length >= 2) {
                const g = Number(p[1])
                root.gpuUsage = (isNaN(g) || g < 0) ? -1 : root.clamp01(g / 100)
            }
        }
        root._tick = root._tick + 1
    }

    Process {
        id: statProc
        command: ["bash", "-c", root.statScript, "sysinfo", root.diskMount, root.tempSensorPath, root.showGpu ? "1" : "0"]
        stdout: StdioCollector {
            onStreamFinished: root.applyStat(text)
        }
    }

    Process {
        id: procListProc
        command: ["bash", "-c", root.procScript, "sysinfo", root.windowList]
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    console.warn("[sysinfo] procScript stderr:", text.trim())
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                console.log("[sysinfo] procScript output:", text.trim().replace(/\n/g, " | ") || "(empty)")
                const list = []
                const lines = text.trim().split("\n")
                for (let i = 0; i < lines.length; i++) {
                    const m = lines[i].match(/^([\d.]+)\s+(.+)$/)
                    if (m)
                        list.push({ name: m[2], cpu: parseFloat(m[1]) })
                }
                root.topProcesses = list
            }
        }
    }

    Timer {
        interval: root._tick < 2 ? 400 : root.pollIntervalMs
        running: root.expanded
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!statProc.running)
                statProc.running = true
        }
    }

    Timer {
        interval: root.procIntervalMs
        running: root.expanded
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            try {
                Hyprland.refreshToplevels()
            } catch (e) {
                console.warn("[sysinfo] refreshToplevels failed:", e)
            }
            root.windowList = root.buildWindowList()
            console.log("[sysinfo] windows from hyprland:", root.windowList.replace(/\n/g, ", ") || "(none, hyprctl fallback)")
            if (!procListProc.running)
                procListProc.running = true
        }
    }

    function launchBtop() {
        Quickshell.execDetached(["bash", "-c", root.terminalCommand])
        root.hide()
    }

    //----------------FOCUS----------------
    HyprlandFocusGrab {
        id: focusGrab
        windows: [root]
        onCleared: root.hide()
    }

    onVisibleChanged: {
        if (visible && !root.expanded)
            root.expanded = true
    }

    //----------------TILE----------------

    component MetricTile: Rectangle {
        id: tile

        property real fraction: 0
        property string icon: ""
        property string valueText: ""
        property string labelText: ""
        property bool critical: false

        property bool reveal: false
        property int revealDelay: 0
        property bool waveActive: false

        property color accent: "#5fa77c"
        property color accentDim: "#446b56"
        property color trackColor: "#2a322d"
        property color dangerColor: "#c96a5a"
        property color textMain: "#eef3ef"
        property color textDim: "#8fa196"

        property color tone: tile.critical ? tile.dangerColor : tile.accent
        property color toneDim: tile.critical ? tile.dangerColor : tile.accentDim
        Behavior on tone { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on toneDim { ColorAnimation { duration: 250; easing.type: Easing.OutCubic } }

        property real _level: tile.fraction < 0 ? 0 : Math.max(0, Math.min(1, tile.fraction))
        Behavior on _level { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

        property real _progress: tile.reveal ? 1 : 0
        Behavior on _progress {
            SequentialAnimation {
                PauseAnimation { duration: tile.reveal ? tile.revealDelay : 0 }
                NumberAnimation { duration: tile.reveal ? 650 : 160; easing.type: Easing.OutCubic }
            }
        }

        readonly property real shown: tile._level * tile._progress
        onShownChanged: water.requestPaint()
        onToneChanged: water.requestPaint()
        onToneDimChanged: water.requestPaint()

        radius: 10
        color: tile.trackColor
        border.width: 2
        border.color: tile.toneDim

        Canvas {
            id: water
            anchors.fill: parent
            anchors.margins: tile.border.width
            visible: tile.shown > 0.002

            property real phase: 0
            NumberAnimation on phase {
                running: tile.waveActive && water.visible
                loops: Animation.Infinite
                from: 0
                to: Math.PI * 2
                duration: 2200
            }

            onPhaseChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onVisibleChanged: if (visible) requestPaint()

            function rgba(c, a) {
                return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
                        + Math.round(c.b * 255) + "," + a + ")"
            }

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const w = width
                const h = height
                if (w <= 0 || h <= 0 || tile.shown <= 0.002)
                    return

                const r = Math.max(0, tile.radius - tile.border.width)
                ctx.beginPath()
                ctx.moveTo(r, 0)
                ctx.lineTo(w - r, 0)
                ctx.arcTo(w, 0, w, r, r)
                ctx.lineTo(w, h - r)
                ctx.arcTo(w, h, w - r, h, r)
                ctx.lineTo(r, h)
                ctx.arcTo(0, h, 0, h - r, r)
                ctx.lineTo(0, r)
                ctx.arcTo(0, 0, r, 0, r)
                ctx.closePath()
                ctx.clip()

                const amp = 2.2
                const surface = h * (1 - tile.shown)
                const k = (Math.PI * 2) / Math.max(40, w / 1.6)

                ctx.beginPath()
                ctx.moveTo(0, surface + amp * Math.sin(phase))
                for (let x = 0; x < w; x += 3)
                    ctx.lineTo(x, surface + amp * Math.sin(x * k + phase))
                ctx.lineTo(w, surface + amp * Math.sin(w * k + phase))
                ctx.lineTo(w, h)
                ctx.lineTo(0, h)
                ctx.closePath()

                const grad = ctx.createLinearGradient(0, surface, 0, h)
                grad.addColorStop(0, rgba(tile.tone, 0.55))
                grad.addColorStop(1, rgba(tile.toneDim, 0.30))
                ctx.fillStyle = grad
                ctx.fill()

                ctx.beginPath()
                ctx.moveTo(0, surface + amp * Math.sin(phase))
                for (let x2 = 0; x2 < w; x2 += 3)
                    ctx.lineTo(x2, surface + amp * Math.sin(x2 * k + phase))
                ctx.lineTo(w, surface + amp * Math.sin(w * k + phase))
                ctx.strokeStyle = rgba(tile.tone, 0.95)
                ctx.lineWidth = 1.3
                ctx.stroke()
            }
        }

        ColumnLayout {
            anchors.centerIn: parent
            width: Math.max(0, parent.width - 16)
            spacing: 2

            Text {
                text: tile.icon
                font.pixelSize: 20
                color: tile.textMain
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: tile.valueText
                font.pixelSize: 15
                font.bold: true
                color: tile.textMain
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }

            Text {
                text: tile.labelText
                font.pixelSize: 10
                color: tile.textDim
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }
        }
    }

    //----------------LAYOUT----------------
    Rectangle {
        id: card
        anchors.fill: parent
        radius: 8
        color: root.bgPanel
        border.width: 3
        border.color: root.borderColor

        transformOrigin: Item.Top

        opacity: 0
        scale: 0.85

        focus: true
        Keys.onEscapePressed: root.hide()

        //----------------ANIMATIONS----------------
        SequentialAnimation {
            id: openAnim

            ScriptAction {
                script: {
                    headerSection.opacity = 0
                    headerTranslate.y = -12
                    tilesGrid.opacity = 0
                    tilesTranslate.y = -12
                    footSection.opacity = 0
                    footTranslate.y = -12
                }
            }

            ParallelAnimation {
                NumberAnimation { target: card; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
                NumberAnimation { target: card; property: "scale"; to: 1; duration: 190; easing.type: Easing.OutBack; easing.overshoot: 1.1 }

                SequentialAnimation {
                    PauseAnimation { duration: 35 }
                    ParallelAnimation {
                        NumberAnimation { target: headerSection; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
                        NumberAnimation { target: headerTranslate; property: "y"; to: 0; duration: 170; easing.type: Easing.OutCubic }
                    }
                }

                SequentialAnimation {
                    PauseAnimation { duration: 70 }
                    ParallelAnimation {
                        NumberAnimation { target: tilesGrid; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
                        NumberAnimation { target: tilesTranslate; property: "y"; to: 0; duration: 170; easing.type: Easing.OutCubic }
                    }
                }

                SequentialAnimation {
                    PauseAnimation { duration: 105 }
                    ParallelAnimation {
                        NumberAnimation { target: footSection; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
                        NumberAnimation { target: footTranslate; property: "y"; to: 0; duration: 170; easing.type: Easing.OutCubic }
                    }
                }
            }
        }

        SequentialAnimation {
            id: closeAnim
            ParallelAnimation {
                NumberAnimation { target: card; property: "opacity"; to: 0; duration: 110; easing.type: Easing.InCubic }
                NumberAnimation { target: card; property: "scale"; to: 0.85; duration: 110; easing.type: Easing.InCubic }
            }
            ScriptAction {
                script: root.closing = false
            }
        }

        Connections {
            target: root
            function onExpandedChanged() {
                closeAnim.stop()
                openAnim.stop()
                if (root.expanded)
                    openAnim.start()
                else
                    closeAnim.start()
            }
        }

        //----------------CONTENT----------------
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            //----------------HEADER----------------
            RowLayout {
                id: headerSection
                Layout.fillWidth: true
                spacing: 10
                opacity: 0

                transform: Translate {
                    id: headerTranslate
                    y: -12
                }

                Rectangle {
                    id: gpuSwitch
                    Layout.preferredWidth: 38
                    Layout.preferredHeight: 20
                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                    radius: 10
                    color: root.showGpu ? root.accentPrimary : root.bgTrack
                    border.width: 1
                    border.color: root.showGpu ? root.accentPrimary : root.accentSecondary

                    Behavior on color {
                        ColorAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }

                    Behavior on border.color {
                        ColorAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }

                    Rectangle {
                        width: 14
                        height: 14
                        radius: 7
                        anchors.verticalCenter: parent.verticalCenter
                        x: root.showGpu ? parent.width - width - 3 : 3
                        color: root.showGpu ? root.bgPanel : root.textDim

                        Behavior on x {
                            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                        }

                        Behavior on color {
                            ColorAnimation { duration: 180; easing.type: Easing.OutCubic }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showGpu = !root.showGpu
                    }
                }

                Text {
                    text: "GPU"
                    color: root.textDim
                    font.pixelSize: 12
                }

                Item { Layout.fillWidth: true }
            }

            //----------------TILES----------------
            ColumnLayout {
                id: tilesGrid
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10
                opacity: 0

                transform: Translate {
                    id: tilesTranslate
                    y: -12
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: 100
                    spacing: 10

                    MetricTile {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 100
                        Layout.preferredHeight: 100
                        icon: "󰻠"
                        accent: root.accentPrimary
                        accentDim: root.accentSecondary
                        trackColor: root.bgTrack
                        dangerColor: root.danger
                        textMain: root.textMain
                        textDim: root.textDim
                        waveActive: root.expanded
                        fraction: root.cpuUsage
                        critical: root.cpuUsage >= root.warnFraction
                        valueText: Math.round(root.cpuUsage * 100) + "%"
                        labelText: "CPU"
                        reveal: root.expanded
                        revealDelay: 0
                    }

                    MetricTile {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 100
                        Layout.preferredHeight: 100
                        icon: "󰍛"
                        accent: root.accentPrimary
                        accentDim: root.accentSecondary
                        trackColor: root.bgTrack
                        dangerColor: root.danger
                        textMain: root.textMain
                        textDim: root.textDim
                        waveActive: root.expanded
                        fraction: root.ramUsage
                        critical: root.ramUsage >= root.warnFraction
                        valueText: Math.round(root.ramUsage * 100) + "%"
                        labelText: root.ramUsedGB.toFixed(1) + "/" + root.ramTotalGB.toFixed(1) + " GB"
                        reveal: root.expanded
                        revealDelay: 60
                    }

                    MetricTile {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 100
                        Layout.preferredHeight: 100
                        icon: "󰔏"
                        accent: root.accentPrimary
                        accentDim: root.accentSecondary
                        trackColor: root.bgTrack
                        dangerColor: root.danger
                        textMain: root.textMain
                        textDim: root.textDim
                        waveActive: root.expanded
                        fraction: root.cpuTemp > 0 ? root.cpuTemp / 100 : -1
                        critical: root.cpuTemp >= root.warnTemp
                        valueText: root.cpuTemp > 0 ? root.cpuTemp + "°C" : "н/д"
                        labelText: "Темп. CPU"
                        reveal: root.expanded
                        revealDelay: 120
                    }
                }

                Item {
                    id: bottomRow
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: 100

                    readonly property real gap: 10
                    readonly property real tileW: Math.max(0, (width - gap * (1 + root.gpuFactor)) / (2 + root.gpuFactor))

                    MetricTile {
                        x: 0
                        y: 0
                        width: bottomRow.tileW
                        height: bottomRow.height
                        icon: "󰛳"
                        accent: root.accentPrimary
                        accentDim: root.accentSecondary
                        trackColor: root.bgTrack
                        dangerColor: root.danger
                        textMain: root.textMain
                        textDim: root.textDim
                        waveActive: root.expanded
                        fraction: Math.min(1, Math.log(1 + root.netDownKBs + root.netUpKBs) / Math.log(1 + 102400))
                        valueText: "↓" + root.fmtRate(root.netDownKBs)
                        labelText: "↑" + root.fmtRate(root.netUpKBs)
                        reveal: root.expanded
                        revealDelay: 180
                    }

                    MetricTile {
                        x: bottomRow.tileW + bottomRow.gap
                        y: 0
                        width: bottomRow.tileW
                        height: bottomRow.height
                        icon: "󰋊"
                        accent: root.accentPrimary
                        accentDim: root.accentSecondary
                        trackColor: root.bgTrack
                        dangerColor: root.danger
                        textMain: root.textMain
                        textDim: root.textDim
                        waveActive: root.expanded
                        fraction: root.diskUsage
                        critical: root.diskUsage >= root.warnFraction
                        valueText: Math.round(root.diskUsage * 100) + "%"
                        labelText: root.diskUsedGB.toFixed(0) + "/" + root.diskTotalGB.toFixed(0) + " GB"
                        reveal: root.expanded
                        revealDelay: 240
                    }

                    MetricTile {
                        x: 2 * bottomRow.tileW + bottomRow.gap * (1 + root.gpuFactor)
                        y: 0
                        width: bottomRow.tileW * root.gpuFactor
                        height: bottomRow.height
                        visible: root.gpuFactor > 0.001
                        opacity: root.gpuFactor * root.gpuFactor
                        clip: true
                        icon: "󰢮"
                        accent: root.accentPrimary
                        accentDim: root.accentSecondary
                        trackColor: root.bgTrack
                        dangerColor: root.danger
                        textMain: root.textMain
                        textDim: root.textDim
                        waveActive: root.expanded && root.gpuFactor > 0
                        fraction: root.gpuUsage
                        critical: root.gpuUsage >= root.warnFraction
                        valueText: root.gpuUsage >= 0 ? Math.round(root.gpuUsage * 100) + "%" : "н/д"
                        labelText: "GPU"
                        reveal: root.expanded
                        revealDelay: 300
                    }
                }
            }

            //----------------TOP PROCESSES + BUTTON----------------
            ColumnLayout {
                id: footSection
                Layout.fillWidth: true
                spacing: 10
                opacity: 0

                transform: Translate {
                    id: footTranslate
                    y: -12
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: root.separatorColor
                }

                Text {
                    text: "Топ программ"
                    color: root.textDim
                    font.pixelSize: 12
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 66
                    spacing: 6

                    Repeater {
                        model: root.topProcesses

                        delegate: RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: (index + 1) + ". " + modelData.name
                                color: root.textMain
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Text {
                                text: modelData.cpu.toFixed(1) + "%"
                                color: root.accentPrimary
                                font.pixelSize: 13
                                font.bold: true
                            }
                        }
                    }

                    Text {
                        visible: root.topProcesses.length === 0
                        text: "нет данных"
                        color: root.textDim
                        font.pixelSize: 13
                    }

                    Item { Layout.fillHeight: true }
                }

                Rectangle {
                    id: btopButton
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    radius: 10

                    color: btopMouse.containsMouse ? root.accentSecondary : root.bgTrack
                    scale: btopMouse.pressed ? 0.96 : 1.0

                    Behavior on color {
                        ColorAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }

                    Behavior on scale {
                        NumberAnimation { duration: 140; easing.type: Easing.OutBack }
                    }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            text: "󰆍"
                            font.pixelSize: 16
                            color: btopMouse.containsMouse ? root.textMain : root.accentPrimary

                            Behavior on color {
                                ColorAnimation { duration: 180; easing.type: Easing.OutCubic }
                            }
                        }

                        Text {
                            text: "Открыть btop"
                            color: root.textMain
                            font.pixelSize: 13
                            font.bold: true
                        }
                    }

                    MouseArea {
                        id: btopMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.launchBtop()
                    }
                }
            }
        }
    }
}
