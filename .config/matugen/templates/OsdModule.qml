import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire

Scope {
    id: root

    property var targetScreen: Quickshell.screens[0]

    // ---- THEME --------------------------------------
    QtObject {
        id: theme
        readonly property color accentPrimary:   "{{theme.accent_primary.hex}}"
        readonly property color accentSecondary: "{{theme.accent_secondary.hex}}"
        readonly property color bgPanel:         "{{theme.bg_panel_battery.hex}}"
        readonly property color bgTrack:         "{{theme.bg_track.hex}}"
        readonly property color borderColor:     "{{theme.accent_primary.hex}}"
        readonly property color textMain:        "{{theme.text_main.hex}}"
    }

    // ---- LAYOUT ---------------------------------------------
    readonly property int earRadius: 8
    readonly property int topRadius: 8
    readonly property int borderWidth: 3
    readonly property int topInset: borderWidth
    readonly property int notchWidthFixed: 240
    readonly property int notchHeightFixed: 70

    // ---- OSD STATE --------------------------------------------
    property string activeControl: ""
    property bool showing: false

    property real volumePct: 0
    property bool volumeMuted: false
    property real brightnessPct: 0
    property bool micOn: true
    property bool capsOn: false

    property bool brightnessReady: false
    property bool capsReady: false
    property bool oskReady: false

    Timer {
        interval: 500
        running: true
        repeat: false
        onTriggered: root.oskReady = true
    }

    readonly property bool isSlider: activeControl === "vol" || activeControl === "bright"
    readonly property int notchWidth: notchWidthFixed
    readonly property int notchHeight: notchHeightFixed

    Timer {
        id: hideTimer
        interval: 2200
        onTriggered: root.showing = false
    }

    function reveal(activeName, autohideMs) {
        activeControl = activeName
        showing = true
        hideTimer.interval = autohideMs || 2200
        hideTimer.restart()
    }

    function holdOpen() {
        hideTimer.stop()
    }

    // ---------- PIPEWIRE ----------------------------------------------
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    Connections {
        target: Pipewire.defaultAudioSink?.audio ?? null
        function onVolumeChanged() {
            root.volumePct = Math.round((Pipewire.defaultAudioSink?.audio.volume ?? 0) * 100)
            root.volumeMuted = !!Pipewire.defaultAudioSink?.audio.muted
            if (root.oskReady) root.reveal("vol", 2200)
        }
        function onMutedChanged() {
            root.volumeMuted = !!Pipewire.defaultAudioSink?.audio.muted
            if (root.oskReady) root.reveal("vol", 1600)
        }
    }

    Connections {
        target: Pipewire.defaultAudioSource?.audio ?? null
        function onMutedChanged() {
            root.micOn = !(Pipewire.defaultAudioSource?.audio.muted ?? true)
            if (root.oskReady) root.reveal("mic", 1500)
        }
    }

    function setVolume(pct) {
        const sink = Pipewire.defaultAudioSink
        if (!sink?.ready || !sink.audio) return
        pct = Math.max(0, Math.min(100, pct))
        sink.audio.muted = false
        sink.audio.volume = pct / 100
    }

    function toggleMute() {
        const sink = Pipewire.defaultAudioSink
        if (sink?.ready && sink.audio) sink.audio.muted = !sink.audio.muted
    }

    function toggleMic() {
        const src = Pipewire.defaultAudioSource
        if (src?.ready && src.audio) src.audio.muted = !src.audio.muted
    }

    // ---------------------- BRIGHTNESSCTL ---------------------------------
    property int maxBrightness: 100

    Process {
        id: maxBrightnessProc
        command: ["brightnessctl", "max"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(this.text.trim())
                if (!isNaN(n) && n > 0) root.maxBrightness = n
            }
        }
    }

    FileView {
        id: brightnessFile
        path: "/sys/class/backlight/" + backlightDeviceName.text.trim() + "/brightness"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const n = parseInt(text().trim())
            if (!isNaN(n) && root.maxBrightness > 0) {
                root.brightnessPct = Math.round((n / root.maxBrightness) * 100)
                if (root.brightnessReady) root.reveal("bright", 2200)
                root.brightnessReady = true
            }
        }
    }

    Process {
        id: backlightDeviceProc
        command: ["sh", "-c", "ls /sys/class/backlight | head -n1"]
        running: true
        stdout: StdioCollector { id: backlightDeviceName }
    }

    function setBrightness(pct) {
        pct = Math.max(1, Math.min(100, pct))
        root.brightnessPct = pct
        setBrightnessProc.command = ["brightnessctl", "set", pct + "%"]
        setBrightnessProc.running = true
        root.reveal("bright", 2200)
    }

    Process {
        id: setBrightnessProc
    }

    // ------------------------ CAPS --------------------------------
    Process {
        id: capsLedFindProc
        command: ["sh", "-c", "ls -d /sys/class/leds/*capslock* 2>/dev/null | head -n1"]
        running: true
        stdout: StdioCollector { id: capsLedPath }
    }

    Timer {
        id: capsPollTimer
        interval: 200
        running: capsLedPath.text.trim() !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: capsPollProc.running = true
    }

    Process {
        id: capsPollProc
        command: ["cat", capsLedPath.text.trim() + "/brightness"]
        stdout: StdioCollector {
            onStreamFinished: {
                const newState = this.text.trim() !== "0"
                if (!root.capsReady) {
                    root.capsOn = newState
                    root.capsReady = true
                } else if (newState !== root.capsOn) {
                    root.capsOn = newState
                    root.reveal("caps", 1400)
                }
            }
        }
    }

    // ------------------------- IPC ---------------------------------------
    IpcHandler {
        target: "osd"

        function incVolume(delta: int): void {
            root.setVolume(root.volumePct + delta)
        }
        function setVolumeAbs(pct: int): void {
            root.setVolume(pct)
        }
        function muteToggle(): void {
            root.toggleMute()
        }
        function incBrightness(delta: int): void {
            root.setBrightness(root.brightnessPct + delta)
        }
        function setBrightnessAbs(pct: int): void {
            root.setBrightness(pct)
        }
        function micToggle(): void {
            root.toggleMic()
        }
    }

    // --------------------------- UI --------------------------------------

    PanelWindow {
        id: notchWindow
        screen: root.targetScreen
        anchors { bottom: true }
        implicitWidth: root.notchWidth + 2 * root.earRadius
        implicitHeight: root.notchHeight + root.earRadius + root.topInset
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay

        property int activeWorkspaceWindows: 0
        readonly property bool hasOpenWindows: activeWorkspaceWindows > 0
        margins.bottom: hasOpenWindows ? -3 : -8

        function refreshActiveWorkspace() {
            activeWorkspaceProc.running = true
        }

        Component.onCompleted: refreshActiveWorkspace()

        Process {
            id: activeWorkspaceProc
            command: ["hyprctl", "activeworkspace", "-j"]
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const data = JSON.parse(this.text)
                        notchWindow.activeWorkspaceWindows = data.windows ?? 0
                    } catch (e) {
                    }
                }
            }
        }

        Connections {
            target: Hyprland
            function onRawEvent(event) {
                notchWindow.refreshActiveWorkspace()
            }
        }

        mask: Region {
            item: revealMask
        }

        Item {
            id: cardVisual
            anchors.fill: parent

            property real hn: root.showing ? root.notchHeight : 0
            
            Behavior on hn {
                NumberAnimation {
                    duration: 380
                    easing.type: root.showing ? Easing.OutCubic : Easing.InCubic
                }
            }

            Item {
                id: revealMask
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: root.notchHeight > 0
                        ? (cardVisual.hn / root.notchHeight) * (root.notchHeight + root.earRadius + root.topInset)
                        : 0
                clip: true

                Item {
                    id: fullCard
                    width: parent.width
                    height: root.notchHeight + root.earRadius + root.topInset
                    anchors.bottom: parent.bottom

                    Canvas {
                        id: shapeCanvas
                        anchors.fill: parent
                        renderTarget: Canvas.FramebufferObject

                        property real w: root.notchWidth   
                        property real h: root.notchHeight  
                        property real rc: root.earRadius
                        property real rt: root.topRadius

                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                        Component.onCompleted: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset()
                            ctx.translate(0, root.topInset)

                            const wn = w   
                            const hn = h   
                            const rcx = rc
                            const rcv = Math.min(rc, Math.max(0, hn))
                            const rt_ = Math.min(rt, hn)

                            ctx.beginPath()
                            ctx.moveTo(rcx + rt_, 0)
                            ctx.lineTo(rcx + wn - rt_, 0)
                            ctx.arc(rcx + wn - rt_, rt_, rt_, -Math.PI / 2, 0, false)
                            ctx.lineTo(rcx + wn, hn - rcv)
                            ctx.arc(wn + 2 * rcx, hn - rcv, rcv, Math.PI, Math.PI / 2, true)
                            ctx.lineTo(0, hn)
                            ctx.arc(0, hn - rcv, rcv, Math.PI / 2, 0, true)
                            ctx.lineTo(rcx, rt_)
                            ctx.arc(rcx + rt_, rt_, rt_, Math.PI, 3 * Math.PI / 2, false)
                            ctx.closePath()

                            ctx.fillStyle = theme.bgPanel
                            ctx.fill()

                            ctx.beginPath()
                            ctx.moveTo(0, hn)
                            ctx.arc(0, hn - rcv, rcv, Math.PI / 2, 0, true)
                            ctx.lineTo(rcx, rt_)
                            ctx.arc(rcx + rt_, rt_, rt_, Math.PI, 3 * Math.PI / 2, false)
                            ctx.lineTo(rcx + wn - rt_, 0)
                            ctx.arc(rcx + wn - rt_, rt_, rt_, -Math.PI / 2, 0, false)
                            ctx.lineTo(rcx + wn, hn - rcv)
                            ctx.arc(wn + 2 * rcx, hn - rcv, rcv, Math.PI, Math.PI / 2, true)

                            ctx.lineWidth = root.borderWidth
                            ctx.strokeStyle = theme.borderColor
                            ctx.stroke()
                        }
                    }

                    // ---- CONTENT ----
                    Item {
                        anchors.fill: parent
                        anchors.topMargin: root.topInset
                        anchors.bottomMargin: root.earRadius
                        anchors.leftMargin: root.earRadius
                        anchors.rightMargin: root.earRadius
                        clip: true
                        opacity: root.notchHeight > 0 ? cardVisual.hn / root.notchHeight : 0

                        Row {
                            id: miniRow
                            anchors.centerIn: parent
                            spacing: 10
                            visible: !root.isSlider

                            Rectangle {
                                width: 8; height: 8; radius: 4
                                anchors.verticalCenter: parent.verticalCenter
                                color: theme.accentPrimary
                                visible: (root.activeControl === "mic" && root.micOn) ||
                                         (root.activeControl === "caps" && root.capsOn)
                            }
                            Rectangle {
                                width: 8; height: 8; radius: 4
                                anchors.verticalCenter: parent.verticalCenter
                                color: theme.bgTrack
                                visible: (root.activeControl === "mic" && !root.micOn) ||
                                         (root.activeControl === "caps" && !root.capsOn)
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                font.pixelSize: 13
                                color: theme.textMain
                                text: root.activeControl === "mic"
                                      ? "Микрофон " + (root.micOn ? "ВКЛ" : "ВЫКЛ")
                                      : "КАПС " + (root.capsOn ? "ВКЛ" : "ВЫКЛ")
                            }
                        }

                        Column {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 6
                            visible: root.isSlider

                            Item {
                                width: parent.width
                                height: Math.max(labelText.implicitHeight, pctText.implicitHeight)

                                Text {
                                    id: labelText
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.activeControl === "vol" ? "Громкость" : "Яркость"
                                    font.pixelSize: 14
                                    color: theme.textMain
                                }
                                Text {
                                    id: pctText
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.activeControl === "vol"
                                          ? (root.volumeMuted ? "ВЫКЛ" : root.volumePct + "%")
                                          : root.brightnessPct + "%"
                                    font.pixelSize: 14
                                    color: theme.textMain
                                }
                            }

                            Item {
                                id: sliderTrack
                                width: parent.width
                                height: 16

                                readonly property real pct: root.activeControl === "vol" ? root.volumePct : root.brightnessPct

                                Rectangle {
                                    id: track
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    height: 8
                                    radius: 4
                                    color: theme.bgTrack

                                    Rectangle {
                                        width: track.width * (sliderTrack.pct / 100)
                                        height: parent.height
                                        radius: 4
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0; color: theme.accentSecondary }
                                            GradientStop { position: 1.0; color: theme.accentPrimary }
                                        }
                                        Behavior on width {
                                            enabled: !dragArea.pressed
                                            NumberAnimation { duration: 160 }
                                        }
                                    }
                                }

                                Rectangle {
                                    width: 14; height: 14; radius: 7
                                    color: theme.textMain
                                    y: track.y + track.height / 2 - 7
                                    x: Math.max(0, Math.min(track.width - width, track.width * (sliderTrack.pct / 100) - width / 2))
                                    Behavior on x {
                                        enabled: !dragArea.pressed
                                        NumberAnimation { duration: 160 }
                                    }
                                }

                                MouseArea {
                                    id: dragArea
                                    anchors.fill: parent
                                    onPressed: (mouse) => { root.holdOpen(); update(mouse.x) }
                                    onPositionChanged: (mouse) => { if (pressed) update(mouse.x) }
                                    onReleased: root.reveal(root.activeControl, 1800)

                                    function update(x) {
                                        const pct = Math.round((x / width) * 100)
                                        if (root.activeControl === "vol") root.setVolume(pct)
                                        else root.setBrightness(pct)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
