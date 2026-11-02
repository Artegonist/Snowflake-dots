import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import "../../services"

Scope {
    id: root

    property var targetScreen: Quickshell.screens[0]

    // ---- THEME --------------------------------------
    QtObject {
        id: theme
        readonly property color accentPrimary:   Theme.accentPrimary
        readonly property color accentSecondary: Theme.accentSecondary
        readonly property color bgPanel:         Theme.bgPanelBattery
        readonly property color bgTrack:         Theme.bgTrack
        readonly property color borderColor:     Theme.accentPrimary
        readonly property color textMain:        Theme.textMain
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

    readonly property var sinkAudio: Pipewire.defaultAudioSink?.ready ? Pipewire.defaultAudioSink.audio : null
    readonly property var sourceAudio: Pipewire.defaultAudioSource?.ready ? Pipewire.defaultAudioSource.audio : null
    readonly property real volumePct: Math.round((sinkAudio?.volume ?? 0) * 100)
    readonly property bool volumeMuted: !!sinkAudio?.muted
    property real brightnessPct: 0
    readonly property bool micOn: !(sourceAudio?.muted ?? true)
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

    property var lastSink: null

    Connections {
        target: root.sinkAudio
        function onVolumeChanged() {
            if (root.oskReady && root.lastSink === root.sinkAudio) root.reveal("vol", 2200)
        }
        function onMutedChanged() {
            if (root.oskReady && root.lastSink === root.sinkAudio) root.reveal("vol", 1600)
        }
    }

    onSinkAudioChanged: Qt.callLater(function() { root.lastSink = root.sinkAudio })

    Connections {
        target: root.sourceAudio
        function onMutedChanged() {
            if (root.oskReady) root.reveal("mic", 1500)
        }
    }

    function volumesPreservingBalance(currentVolumes, targetAvg) {
        if (!currentVolumes || currentVolumes.length === 0) return currentVolumes
        const sum = currentVolumes.reduce((a, b) => a + b, 0)
        const currentAvg = sum / currentVolumes.length
        if (currentAvg <= 0.0001) {
            return currentVolumes.map(() => targetAvg)
        }
        const scale = targetAvg / currentAvg
        return currentVolumes.map(v => Math.max(0, Math.min(1, v * scale)))
    }

    function setVolume(pct) {
        const sink = Pipewire.defaultAudioSink
        if (!sink?.ready || !sink.audio) return
        pct = Math.max(0, Math.min(100, pct))
        const audio = sink.audio
        audio.muted = false

        const vols = audio.volumes
        if (vols && vols.length > 0) {
            audio.volumes = root.volumesPreservingBalance(vols, pct / 100)
        } else {
            audio.volume = pct / 100
        }
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

    FileView {
        id: capsLedFile
        property string ledDir: capsLedPath.text.trim()
        path: ledDir !== "" ? ledDir + "/brightness" : ""
        onLoaded: {
            const newState = text().trim() !== "0"
            if (!root.capsReady) {
                root.capsOn = newState
                root.capsReady = true
            } else if (newState !== root.capsOn) {
                root.capsOn = newState
                root.reveal("caps", 1400)
            }
        }
    }

    Timer {
        interval: 100
        running: capsLedFile.path !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: capsLedFile.reload()
    }

    // ------------------------- IPC ---------------------------------------
    IpcHandler {
        target: "osd"

        function incVolume(delta: int): void {
            if (!root.sinkAudio) return
            root.setVolume(Math.round(root.sinkAudio.volume * 100) + delta)
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

    // Держим окно (и его wl_surface / zwlr_layer_surface) полностью
    // уничтоженным, когда OSD не показывается, и создаём заново
    // при каждом reveal(). Раньше окно всегда было замаплено, и просто
    // скрывалось через mask — Hyprland в таком случае держит последний
    // закоммиченный буфер поверхности в памяти, и при быстром свайпе
    // между рабочими столами иногда на кадр-другой показывает именно
    // его — это и выглядит как "тень"/призрак сжатого OSD.
    // Loader.active гарантирует настоящее destroy/create surface,
    // так что закешировать что-либо просто не успевает.
    property bool closing: false

    onShowingChanged: {
        if (showing) {
            closing = false
            closeTeardownTimer.stop()
        } else {
            closing = true
            closeTeardownTimer.restart()
        }
    }

    Timer {
        id: closeTeardownTimer
        // чуть больше длительности анимации схлопывания (380ms),
        // чтобы окно не уничтожилось раньше, чем закроется визуально
        interval: 450
        repeat: false
        onTriggered: root.closing = false
    }

    Loader {
        id: notchLoader
        active: root.showing || root.closing
        sourceComponent: notchWindowComponent
    }

    Component {
        id: notchWindowComponent

    PanelWindow {
        id: notchWindow
        screen: root.targetScreen
        anchors { bottom: true }
        implicitWidth: root.notchWidth + 2 * root.earRadius
        implicitHeight: root.notchHeight + root.earRadius + root.topInset
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:osd"

        property int activeWorkspaceWindows: 0
        property int activeWindowFullscreenState: 0
        readonly property bool hasOpenWindows: activeWorkspaceWindows > 0
        readonly property bool isRealFullscreen: activeWindowFullscreenState === 2
        margins.bottom: (hasOpenWindows && !isRealFullscreen) ? -3 : -8

        function refreshActiveWorkspace() {
            activeWorkspaceProc.running = true
            activeWindowProc.running = true
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

        Process {
            id: activeWindowProc
            command: ["hyprctl", "activewindow", "-j"]
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const data = JSON.parse(this.text)
                        notchWindow.activeWindowFullscreenState = data.fullscreen ?? 0
                    } catch (e) {
                    }
                }
            }
        }

        Connections {
            target: Hyprland
            function onRawEvent(event) {
                notchWindow.refreshActiveWorkspace()
                // Известный баг Hyprland: при быстрой смене воркспейса
                // компоситор иногда на секунду-другую показывает старый
                // закешированный кадр layer-shell поверхности вместо
                // актуального (обычно — промежуточный кадр анимации).
                // Форсируем перерисовку Canvas при любом событии
                // компоситора, чтобы минимизировать шанс и длительность
                // такого "призрака".
                if (shapeCanvas.available)
                    shapeCanvas.requestPaint()
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
                        property color fill: theme.bgPanel
                        property color stroke: theme.borderColor

                        onFillChanged: requestPaint()
                        onStrokeChanged: requestPaint()
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
}
