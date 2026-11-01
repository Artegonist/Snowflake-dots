import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Wayland
import "../../services"

PanelWindow {
    id: root

    visible: false
    focusable: true
    WlrLayershell.namespace: "player-module"
    WlrLayershell.keyboardFocus: root.expanded ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // ------------------------- STATE -------------------------

    property bool expanded: false
    property bool closing: false
    property bool opening: false
    property string currentTab: "lyrics" // "lyrics" | "eq"
    property int savedWorkspaceId: -1
    property real panelLeft: 120

    // ------------------------- OPEN / CLOSE -------------------------

    function show() {
        if (root.opening || (root.expanded && !root.closing))
            return
        root.opening = true
        cursorProc.running = true
    }

    function reallyShow() {
        root.opening = false
        returnToWorkspaceTimer.stop()
        root.closing = false
        if (!root.visible)
            root.visible = true
        root.savedWorkspaceId = Hyprland.focusedMonitor
            ? Hyprland.focusedMonitor.activeWorkspace.id
            : -1
        focusGrab.active = true
        root.mask = null
        root.expanded = true
    }

    function hide() {
        if (root.opening) {
            root.opening = false
            cursorProc.running = false
        }
        closeInternal(true)
    }

    function closeInternal(restoreWorkspace) {
        if (!root.expanded || root.closing)
            return
        root.closing = true
        focusGrab.active = false
        root.mask = emptyRegion
        root.expanded = false
        if (restoreWorkspace)
            returnToWorkspaceTimer.start()
    }

    function toggle() {
        if (root.opening || (root.expanded && !root.closing))
            hide()
        else
            show()
    }

    Process {
        id: cursorProc
        command: ["hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const pos = JSON.parse(text)
                    const mon = Hyprland.focusedMonitor
                    const ipc = mon ? mon.lastIpcObject : null
                    const monX = (ipc && ipc.x !== undefined) ? ipc.x : 0
                    const screenW = root.screen ? root.screen.width : 1920
                    const wanted = pos.x - monX - root.implicitWidth / 2
                    root.panelLeft = Math.max(8, Math.min(screenW - root.implicitWidth - 8, wanted))
                } catch (e) {

                }
            }
        }
        onExited: if (root.opening) root.reallyShow()
    }

    Timer {
        interval: 600
        running: root.opening
        onTriggered: {
            cursorProc.running = false
            if (root.opening)
                root.reallyShow()
        }
    }

    Timer {
        id: returnToWorkspaceTimer
        interval: 30
        onTriggered: {
            if (root.savedWorkspaceId !== -1)
                Hyprland.dispatch("workspace " + root.savedWorkspaceId)
        }
    }

    Region {
        id: emptyRegion
        x: 0
        y: 0
        width: 0
        height: 0
    }

    // ------------------------- WINDOW GEOMETRY -------------------------

    anchors {
        top: true
        left: true
    }

    margins {
        top: 30
        left: root.panelLeft
    }

    exclusionMode: ExclusionMode.Ignore

    color: "transparent"
    implicitWidth: 440
    implicitHeight: 660

    // ------------------------- COLORS -------------------------

    readonly property color accentPrimary: Theme.accentPrimary
    readonly property color accentSecondary: Theme.accentSecondary
    readonly property color bgPanel: Theme.bgPanelBattery
    readonly property color bgTrack: Theme.bgTrack
    readonly property color borderColor: Theme.accentPrimary
    readonly property color separatorColor: Qt.rgba(1, 1, 1, 0.08)
    readonly property color textMain: Theme.textMain
    readonly property color textDim: Theme.textDim
    readonly property color danger: "#c96a5a"
    readonly property color thumbColor: Theme.textMain

    HyprlandFocusGrab {
        id: focusGrab
        windows: [root]
        onCleared: root.closeInternal(false)
    }

    // ------------------------- MPRIS -------------------------

    property var manualPlayer: null
    property var lastActive: null

    readonly property var playerList: Mpris.players.values

    readonly property var player: {
        const list = root.playerList
        if (root.manualPlayer && list.indexOf(root.manualPlayer) !== -1)
            return root.manualPlayer
        if (root.lastActive && list.indexOf(root.lastActive) !== -1 && root.lastActive.isPlaying)
            return root.lastActive
        for (let i = 0; i < list.length; i++) {
            if (list[i].isPlaying)
                return list[i]
        }
        if (root.lastActive && list.indexOf(root.lastActive) !== -1)
            return root.lastActive
        return list.length > 0 ? list[0] : null
    }

    readonly property int playerIndex: root.player ? root.playerList.indexOf(root.player) : -1

    Repeater {
        model: Mpris.players
        delegate: Item {
            required property var modelData
            Connections {
                target: modelData
                function onIsPlayingChanged() {
                    if (modelData.isPlaying && root.lastActive !== modelData)
                        root.lastActive = modelData
                }
            }
        }
    }

    function cyclePlayer() {
        const list = root.playerList
        if (list.length < 2)
            return
        root.manualPlayer = list[(root.playerIndex + 1) % list.length]
    }

    function useAutomaticPlayer() {
        root.manualPlayer = null
    }

    // ------------------------- SOURCE -------------------------
    
    property bool sourceMenuOpen: false
    property rect sourceMenuAnchor: Qt.rect(0, 0, 0, 0)

    readonly property var sourceMenuModel: {
        const out = [{ player: null }]
        const list = root.playerList
        for (let i = 0; i < list.length; i++)
            out.push({ player: list[i] })
        return out
    }

    function playerName(p) {
        return p ? (p.identity || p.desktopEntry || "Плеер") : ""
    }

    function playerTrackLine(p) {
        if (!p)
            return ""
        const line = [p.trackArtist || "", p.trackTitle || ""].filter(s => s !== "").join(" — ")
        return line !== "" ? line : "Ничего не играет"
    }

    function updateSourceMenuAnchor() {
        const p = sourceHeader.mapToItem(card, 0, 0)
        root.sourceMenuAnchor = Qt.rect(p.x, p.y, sourceHeader.width, sourceHeader.height)
    }

    function toggleSourceMenu() {
        if (root.sourceMenuOpen) {
            root.sourceMenuOpen = false
            return
        }
        root.updateSourceMenuAnchor()
        root.sourceMenuOpen = true
    }

    function selectSource(p) {
        root.manualPlayer = p
        root.sourceMenuOpen = false
    }

    function rememberActivePlayer() {
        if (root.player && root.player.isPlaying && root.lastActive !== root.player)
            root.lastActive = root.player
    }

    onPlayerListChanged: {
        if (root.manualPlayer && root.playerList.indexOf(root.manualPlayer) === -1)
            root.manualPlayer = null
        if (root.lastActive && root.playerList.indexOf(root.lastActive) === -1)
            root.lastActive = null
        if (root.playerList.length === 0)
            root.sourceMenuOpen = false
    }

    // ------------------------- WAYBAR -------------------------
    property int waybarSignal: 8

    function escapeMarkup(value) {
        return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    readonly property string waybarSnapshot: JSON.stringify({
        protocol: 1,
        text: root.isPlaying ? " 󰏤 " : " 󰐊 ",
        "class": !root.player ? "stopped" : root.isPlaying ? "playing"
            : root.player.playbackState === MprisPlaybackState.Paused ? "paused" : "stopped",
        tooltip: !root.player ? "Нет активных плееров"
            : root.escapeMarkup([root.trackArtist, root.trackTitle].filter(s => s !== "").join(" — ") || "Без названия")
                + "\n" + root.escapeMarkup(root.player.identity || "Плеер")
                + (root.playerList.length > 1 ? " · " + (root.playerIndex + 1) + "/" + root.playerList.length : "")
                + (root.manualPlayer ? " · выбран вручную" : ""),
        player: root.player ? root.player.identity : "",
        selectedIndex: root.playerIndex,
        players: root.playerList.length,
        manual: root.manualPlayer !== null
    })

    onWaybarSnapshotChanged: waybarNotifyTimer.restart()

    Timer {
        id: waybarNotifyTimer
        interval: 80
        onTriggered: {
            if (waybarNotifyProc.running)
                restart()
            else
                waybarNotifyProc.running = true
        }
    }

    Process {
        id: waybarNotifyProc
        command: ["pkill", "-RTMIN+" + root.waybarSignal, "-x", "waybar"]
    }

    function mediaAction(action) {
        if (action === "panel") { root.toggle(); return "ok" }
        if (action === "auto") { root.useAutomaticPlayer(); return "ok" }
        if (action === "cycle") { root.cyclePlayer(); return "ok" }
        const p = root.player
        if (!p)
            return "unavailable"
        if (action === "toggle" && p.canTogglePlaying) p.togglePlaying()
        else if (action === "play" && p.canPlay) p.play()
        else if (action === "pause" && p.canPause) p.pause()
        else if (action === "next" && p.canGoNext) p.next()
        else if (action === "previous" && p.canGoPrevious) p.previous()
        else if ((action === "seek-forward" || action === "seek-backward") && p.canSeek && p.positionSupported)
            root.seekTo(p.position + (action === "seek-forward" ? 5 : -5))
        else return "unavailable"
        return "ok"
    }

    IpcHandler {
        target: "playerSync"
        function snapshot(): string { return root.waybarSnapshot }
        function action(command: string): string { return root.mediaAction(command) }
    }

    // ------------------------- MPRIS DATA -------------------------

    readonly property string trackTitle: root.player ? (root.player.trackTitle || "") : ""
    readonly property string trackArtist: root.player ? (root.player.trackArtist || "") : ""
    readonly property string trackAlbum: root.player ? (root.player.trackAlbum || "") : ""
    readonly property string trackArtUrl: root.player ? (root.player.trackArtUrl || "") : ""
    readonly property int currentTrackId: root.player ? root.player.uniqueId : -1

    readonly property real reportedTrackLength: {
        const metadata = root.player ? root.player.metadata : null
        const micros = metadata ? Number(metadata["mpris:length"]) : 0
        return isFinite(micros) && micros > 0 ? micros / 1000000 : 0
    }
    property var trackLengthCache: ({ player: null, trackId: -1, seconds: 0 })
    readonly property real trackLength: {
        if (!root.player)
            return 0
        if (root.reportedTrackLength > 0)
            return root.reportedTrackLength
        const cached = root.trackLengthCache
        return cached.player === root.player && cached.trackId === root.currentTrackId
            ? cached.seconds : 0
    }

    function rememberTrackLength() {
        const cached = root.trackLengthCache
        const sameTrack = cached.player === root.player && cached.trackId === root.currentTrackId
        const seconds = root.reportedTrackLength > 0 ? root.reportedTrackLength
            : sameTrack ? cached.seconds : 0
        if (!sameTrack || cached.seconds !== seconds)
            root.trackLengthCache = { player: root.player, trackId: root.currentTrackId, seconds: seconds }
    }

    onReportedTrackLengthChanged: root.rememberTrackLength()

    property var knownPlayer: null
    onPlayerChanged: {
        if (root.player === root.knownPlayer)
            return
        root.knownPlayer = root.player
        Qt.callLater(root.rememberActivePlayer)
        root.rememberTrackLength()
        root.invalidateLyrics()
    }

    Connections {
        target: root.player
        function onPostTrackChanged() { root.rememberTrackLength() }
    }
    readonly property string trackUrl: {
        if (!root.player || !root.player.metadata)
            return ""
        const u = root.player.metadata["xesam:url"]
        return u ? String(u) : ""
    }
    readonly property real position: (root.player && root.player.positionSupported) ? root.player.position : 0
    readonly property bool isPlaying: root.player ? root.player.isPlaying : false

    Timer {
        interval: 250
        repeat: true
        triggeredOnStart: true
        running: root.expanded && root.player !== null && root.isPlaying
        onTriggered: root.player.positionChanged()
    }

    function playPause() {
        root.mediaAction("toggle")
    }

    function next() {
        root.mediaAction("next")
    }

    function previous() {
        root.mediaAction("previous")
    }

    function seekTo(seconds) {
        const p = root.player
        if (!p || !p.canSeek || !p.positionSupported || !isFinite(seconds))
            return
        root.rememberTrackLength()
        p.position = Math.max(0, Math.min(root.trackLength > 0 ? root.trackLength : seconds, seconds))
    }

    function cycleLoop() {
        const p = root.player
        if (!p || !p.loopSupported)
            return
        if (p.loopState === MprisLoopState.None)
            p.loopState = MprisLoopState.Playlist
        else if (p.loopState === MprisLoopState.Playlist)
            p.loopState = MprisLoopState.Track
        else
            p.loopState = MprisLoopState.None
    }

    function formatTime(sec) {
        if (!isFinite(sec) || sec < 0)
            sec = 0
        const s = Math.floor(sec)
        const m = Math.floor(s / 60)
        const r = s % 60
        return m + ":" + (r < 10 ? "0" : "") + r
    }

    // ------------------------- CAVA -------------------------
    readonly property int cavaBarCount: 40
    property string cavaInputMethod: "" 
    property string cavaSource: "auto"
    property var cavaLevels: []
    property string cavaState: "idle" 
    property bool cavaConfigReady: false
    property bool cavaStopping: false
    readonly property bool cavaWanted: root.expanded && root.player !== null && root.isPlaying
    readonly property string cavaConfig: [
        "[general]",
        "bars = " + root.cavaBarCount,
        "framerate = 30",
        "autosens = 1",
        "[input]",
        root.cavaInputMethod !== "" ? "method = " + root.cavaInputMethod : "",
        "source = " + root.cavaSource,
        "[output]",
        "method = raw",
        "raw_target = /dev/stdout",
        "data_format = ascii",
        "ascii_max_range = 100",
        "bar_delimiter = 59",
        "frame_delimiter = 10",
        "channels = mono",
        "mono_option = average",
        "[smoothing]",
        "noise_reduction = 77",
        ""
    ].join("\n")

    onCavaWantedChanged: root.syncCava()
    Component.onCompleted: root.syncCava()

    function syncCava() {
        if (!root.cavaWanted) {
            root.cavaLevels = []
            root.cavaState = "idle"
            if (cavaProc.running) {
                root.cavaStopping = true
                cavaProc.running = false
            }
            return
        }

        if (cavaProc.running || root.cavaStopping)
            return
        root.cavaState = "starting"
        if (!root.cavaConfigReady) {
            cavaConfigFile.setText(root.cavaConfig)
            return
        }
        cavaProc.running = true
    }

    function readCavaFrame(data) {
        if (!root.cavaWanted || root.cavaStopping
                || (root.cavaState !== "starting" && root.cavaState !== "live"))
            return
        const values = data.trim().split(";")
        if (values[values.length - 1] === "")
            values.pop()
        if (values.length !== root.cavaBarCount)
            return
        const levels = []
        for (let i = 0; i < values.length; i++) {
            
            if (!/^\d+$/.test(values[i]))
                return
            levels.push(Math.max(0, Math.min(1, Number(values[i]) / 100)))
        }
        root.cavaLevels = levels
        root.cavaState = "live"
    }

    FileView {
        id: cavaConfigFile
        path: Quickshell.stateDir + "/player-cava.ini"
        preload: false
        printErrors: false
        onSaved: {
            root.cavaConfigReady = true
            root.syncCava()
        }
        onSaveFailed: {
            root.cavaConfigReady = false
            if (root.cavaWanted)
                root.cavaState = "error"
        }
    }

    Process {
        id: cavaProc

        command: ["bash", "-c",
            'command -v cava >/dev/null 2>&1 || exit 127; exec cava -p "$1"',
            "quickshell-player-cava", cavaConfigFile.path]
        stdout: SplitParser {
            onRead: data => root.readCavaFrame(data)
        }
        stderr: SplitParser {
            onRead: data => {
                if (root.cavaWanted && data.trim() !== "")
                    console.warn("player cava: " + data)
            }
        }
        onStarted: {
            if (!root.cavaWanted) {
                root.cavaStopping = true
                cavaProc.running = false
            }
        }
        onExited: (exitCode, exitStatus) => {
            const stopped = root.cavaStopping
            root.cavaStopping = false
            root.cavaLevels = []
            if (!root.cavaWanted)
                root.cavaState = "idle"
            else if (stopped)
                Qt.callLater(root.syncCava)
            else
                root.cavaState = exitCode === 127 ? "missing" : "error"
        }
    }

    Timer {
        interval: 6000
        running: root.cavaWanted && root.cavaState === "starting"
        onTriggered: {
            root.cavaState = "error"
            cavaProc.running = false
            root.cavaLevels = []
        }
    }

    // ------------------------- SONGS TEXT -------------------------

    property var lyricLines: []
    property string plainLyrics: ""
    property string lyricsState: "idle" // idle | loading | synced | plain | none | error
    property string lyricsSource: ""
    property int lyricsToken: 0
    property string fetchedSig: ""
    property var pendingLyrics: null
    property var activeLyrics: null
    property bool lyricsStopping: false
    property bool lyricsResultReceived: false
    property string lyricsScript: Quickshell.shellPath("modules/player/lyrics.sh")

    readonly property string trackSig: JSON.stringify([
        root.currentTrackId, root.trackTitle, root.trackArtist, root.trackAlbum,
        Math.round(root.trackLength), root.trackUrl
    ])

    onTrackSigChanged: root.invalidateLyrics()
    onExpandedChanged: {
        if (root.expanded) {
            if (!lyricsDebounce.running)
                root.maybeFetchLyrics()
        } else {
            root.sourceMenuOpen = false
            lyricsDebounce.stop()
            root.pendingLyrics = null
            if (lyricsProc.running) {
                root.lyricsToken++
                root.lyricsStopping = true
                lyricsProc.running = false
            }
        }
    }

    function invalidateLyrics() {
        root.lyricsToken++
        root.fetchedSig = ""
        root.pendingLyrics = null
        root.lyricLines = []
        root.plainLyrics = ""
        root.lyricsSource = ""
        root.lyricsState = root.player && root.trackTitle !== "" ? "loading" : "idle"
        if (lyricsProc.running) {
            root.lyricsStopping = true
            lyricsProc.running = false
        }
        lyricsDebounce.stop()
        if (root.expanded)
            lyricsDebounce.restart()
    }

    Timer {
        id: lyricsDebounce
        interval: 350
        onTriggered: root.maybeFetchLyrics()
    }

    function maybeFetchLyrics() {
        if (!root.expanded || root.trackSig === root.fetchedSig)
            return
        root.fetchLyrics()
    }

    function fetchLyrics() {
        root.lyricsToken++
        root.lyricLines = []
        root.plainLyrics = ""
        root.lyricsSource = ""
        root.pendingLyrics = null
        if (!root.player || root.trackTitle === "") {
            root.lyricsState = "idle"
            return
        }
        root.lyricsState = "loading"
        root.pendingLyrics = {
            token: root.lyricsToken,
            signature: root.trackSig,
            player: root.player,
            command: ["bash", root.lyricsScript, String(root.lyricsToken),
                root.trackArtist, root.trackTitle, root.trackAlbum,
                String(Math.round(root.trackLength)), root.trackUrl]
        }
        if (lyricsProc.running) {
            root.lyricsStopping = true
            lyricsProc.running = false
        } else {
            root.startQueuedLyrics()
        }
    }

    function startQueuedLyrics() {
        if (lyricsProc.running || root.lyricsStopping || !root.expanded || !root.pendingLyrics)
            return
        const request = root.pendingLyrics
        root.pendingLyrics = null
        if (request.token !== root.lyricsToken || request.player !== root.player || request.signature !== root.trackSig)
            return
        root.activeLyrics = request
        root.lyricsResultReceived = false
        lyricsProc.command = request.command
        lyricsProc.running = true
    }

    Process {
        id: lyricsProc
        stdout: StdioCollector {
            onStreamFinished: root.onLyricsOutput(text)
        }

        stderr: SplitParser {
            onRead: data => {
                if (!root.lyricsStopping && data.trim() !== "")
                    console.warn("player lyrics: " + data)
            }
        }
        onExited: (exitCode, exitStatus) => {
            const stopped = root.lyricsStopping
            root.lyricsStopping = false
            if (!stopped && exitCode !== 0)
                console.warn("player lyrics: " + root.lyricsScript + " завершился с кодом " + exitCode
                    + (exitCode === 127 ? " — скрипт не найден, проверьте lyricsScript" : ""))
            const request = root.activeLyrics
            if (request && request.token === root.lyricsToken && !root.lyricsResultReceived)
                root.lyricsState = "error"
            if (root.pendingLyrics && root.expanded)
                Qt.callLater(root.startQueuedLyrics)
        }
    }

    Timer {
        interval: 12000
        running: lyricsProc.running && !root.lyricsStopping
        onTriggered: {
            root.lyricsToken++
            root.fetchedSig = ""
            root.lyricsState = "error"
            root.lyricsStopping = true
            lyricsProc.running = false
        }
    }

    function parseLrc(text) {
        const out = []
        const headRe = /^\s*((?:\[\d+:\d+(?:[.:]\d+)?\]\s*)+)(.*)$/
        const stampRe = /\[(\d+):(\d+(?:[.:]\d+)?)\]/g
        let offset = 0
        const offM = /^\s*\[offset:\s*([+-]?\d+)\s*\]/im.exec(text)
        if (offM)
            offset = parseInt(offM[1], 10) / 1000

        const lines = text.split(/\r?\n/)
        for (let i = 0; i < lines.length; i++) {
            const head = headRe.exec(lines[i])
            if (!head)
                continue
            const txt = head[2].replace(/<\d+:\d+(?:[.:]\d+)?>/g, "").replace(/\s+/g, " ").trim()
            let m
            stampRe.lastIndex = 0
            while ((m = stampRe.exec(head[1])) !== null) {
                const t = parseInt(m[1], 10) * 60 + parseFloat(m[2].replace(":", "."))
                if (isFinite(t))
                    out.push({ t: Math.max(0, t - offset), text: txt })
            }
        }
        out.sort((a, b) => a.t - b.t)
        return out
    }

    function lengthMismatch(item, wantedLen) {
        return wantedLen > 0 && item && item.duration > 0 && Math.abs(item.duration - wantedLen) > 10
    }

    function pickBestLyrics(list, wantedLen) {
        let best = null
        let bestScore = -1
        for (let i = 0; i < list.length; i++) {
            const it = list[i]
            if (!it || it.instrumental)
                continue
            let score = 0
            if (it.syncedLyrics)
                score += 100
            else if (it.plainLyrics)
                score += 50
            else
                continue
            if (wantedLen > 0 && it.duration) {
                const diff = Math.abs(it.duration - wantedLen)
                if (diff <= 3)
                    score += 30 - diff * 5
                else if (diff > 10)
                    score -= 40
            }
            if (score > bestScore) {
                best = it
                bestScore = score
            }
        }
        return best
    }

    function onLyricsOutput(out) {
        const lines = out.split("\n")
        const start = lines.findIndex(l => /^TOKEN \d+\s*$/.test(l))
        if (start < 0 || lines.length < start + 2)
            return
        const token = parseInt(lines[start].slice(6), 10)
        const request = root.activeLyrics
        if (!request || token !== root.lyricsToken || token !== request.token
                || request.player !== root.player || request.signature !== root.trackSig)
            return
        root.lyricsResultReceived = true

        const src = lines[start + 1].replace(/^SRC\s*/, "").trim()
        const body = lines.slice(start + 2).join("\n").trim()
        if (src === "error") {
            root.lyricsState = "error"
            root.fetchedSig = ""
            return
        }
        root.fetchedSig = request.signature

        let synced = ""
        let plain = ""

        if (src === "lrclib") {
            try {
                const data = JSON.parse(body)
                const item = Array.isArray(data) ? root.pickBestLyrics(data, root.trackLength) : data
                if (item && !item.instrumental) {
                    synced = item.syncedLyrics || ""
                    plain = item.plainLyrics || ""
                    if (synced && root.lengthMismatch(item, root.trackLength)) {
                        if (!plain)
                            plain = root.parseLrc(synced).map(l => l.text).join("\n")
                        synced = ""
                    }
                }
            } catch (e) {
                root.lyricsState = "error"
                root.fetchedSig = ""
                return
            }
        } else if (src === "local") {
            if (/\[\d+:\d+/.test(body))
                synced = body
            else
                plain = body
        }

        root.lyricsSource = src === "lrclib" ? "LRCLIB" : (src === "local" ? "локальный файл" : "")

        if (synced) {
            const parsed = root.parseLrc(synced)
            if (parsed.length > 0) {
                root.lyricLines = parsed
                root.lyricsState = "synced"
                return
            }
        }
        if (plain) {
            root.plainLyrics = plain
            root.lyricsState = "plain"
            return
        }
        root.lyricsState = "none"
    }

    readonly property int activeLine: {
        const lines = root.lyricLines
        if (lines.length === 0)
            return -1
        const t = root.position + 0.25
        let idx = -1
        for (let i = 0; i < lines.length; i++) {
            if (lines[i].t <= t)
                idx = i
            else
                break
        }
        return idx
    }

    // ------------------------- EQ PROFILE -------------------------

    readonly property string audioConfigName: Quickshell.env("QS_AUDIO_CONFIG") || "snowflake"
    property bool eqAvailable: false
    property var eqGains: []
    property var eqFreqs: []
    property var eqStateGains: null
    property string eqStatePreset: ""
    property var eqStateCustom: null
    property var eqStateCustomNames: null

    readonly property var eqBuiltinPresets: ({
        "Плоский":  [0, 0, 0, 0, 0, 0, 0, 0],
        "Бас+":     [6, 5, 3, 1, 0, 0, 0, 0],
        "Верхи+":   [0, 0, 0, 0, 0, 2, 4, 6],
        "Вокал":    [-3, -2, -1, 0, 3, 2, 0, -1],
        "Поп":      [-1, 0, 1, 1, 2, 2, 3, 2],
        "Рок":      [4, 3, -1, -2, -1, 1, 3, 3],
        "Джаз":     [2, 1, 0, -1, 0, 1, 2, 3],
        "Классика": [2, 1, 0, 0, 0, 0, 1, 2]
    })

    function sameGains(a, b) {
        if (!a || !b || a.length !== b.length)
            return false
        for (let i = 0; i < a.length; i++) {
            if (Math.round(a[i]) !== Math.round(b[i]))
                return false
        }
        return true
    }

    readonly property string eqPresetName: {
        const gains = root.eqGains
        if (!root.eqAvailable || gains.length === 0)
            return ""

        if (root.eqStatePreset !== "" && root.eqStateGains && root.sameGains(root.eqStateGains, gains))
            return root.eqStatePreset

        const names = Object.keys(root.eqBuiltinPresets)
        for (let i = 0; i < names.length; i++) {
            if (root.sameGains(root.eqBuiltinPresets[names[i]], gains))
                return names[i]
        }

        if (root.eqStateCustom) {
            for (let i = 0; i < root.eqStateCustom.length; i++) {
                if (root.eqStateCustom[i] && root.sameGains(root.eqStateCustom[i], gains)) {
                    const custom = root.eqStateCustomNames ? root.eqStateCustomNames[i] : ""
                    return custom ? custom : ("Польз. " + (i + 1))
                }
            }
        }
        return "Свой"
    }

    function freqLabel(f) {
        if (f >= 1000) {
            const k = f / 1000
            return (Math.abs(k - Math.round(k)) < 0.05 ? Math.round(k) : k.toFixed(1)) + "k"
        }
        return String(Math.round(f))
    }

    function parseEqFile(txt) {
        try {
            const j = JSON.parse(txt)
            const eq = j.output.equalizer
            const left = eq.left
            let n = eq["num-bands"]
            if (!n) {
                n = 0
                while (left["band" + n] !== undefined)
                    n++
            }
            const gains = []
            const freqs = []
            for (let i = 0; i < n; i++) {
                const b = left["band" + i]
                if (!b)
                    break
                gains.push(Number(b.gain) || 0)
                freqs.push(Number(b.frequency) || 0)
            }
            if (gains.length === 0)
                throw new Error("no bands")
            root.eqGains = gains
            root.eqFreqs = freqs
            root.eqAvailable = true
        } catch (e) {
            root.eqAvailable = false
        }
    }

    function parseEqState(txt) {
        if (!txt || txt.trim() === "") {
            root.eqStateGains = null
            root.eqStatePreset = ""
            return
        }
        try {
            const s = JSON.parse(txt)
            root.eqStateGains = s.bandGains || null
            root.eqStatePreset = s.activePreset || ""
            root.eqStateCustom = s.customPresets || null
            root.eqStateCustomNames = s.customPresetNames || null
        } catch (e) {
            root.eqStateGains = null
            root.eqStatePreset = ""
        }
    }

    FileView {
        id: eqFile
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/easyeffects/output/quickshell.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.parseEqFile(eqFile.text())
        onLoadFailed: root.eqAvailable = false
    }

    Process {
        id: eqStateProc
        command: ["bash", "-c",
            'qs -c "$1" ipc call audio eqState 2>/dev/null || cat "${XDG_DATA_HOME:-$HOME/.local/share}/snowflake/audio/eq.json" 2>/dev/null || { '
            + 'f=$(find "${XDG_STATE_HOME:-$HOME/.local/state}/quickshell" -name audio-eq-state.json -printf "%T@ %p\\n" 2>/dev/null | sort -nr | head -n1 | cut -d" " -f2-); '
            + '[ -n "$f" ] && cat "$f"; }', "quickshell-player-eq", root.audioConfigName]
        stdout: StdioCollector {
            onStreamFinished: root.parseEqState(text)
        }
    }

    Timer {
        interval: 3000
        repeat: true
        triggeredOnStart: true
        running: root.expanded && root.currentTab === "eq"
        onTriggered: {
            eqFile.reload()
            if (!eqStateProc.running)
                eqStateProc.running = true
        }
    }

    property var audioModule: null

    Process {
        id: openAudioProc
        command: ["qs", "-c", root.audioConfigName, "ipc", "call", "audio", "openEqualizer"]
        stdout: SplitParser {
            onRead: data => {
                if (data.trim() !== "")
                    console.warn("player eq: " + data)
            }
        }
        stderr: SplitParser {
            onRead: data => {
                if (data.trim() !== "")
                    console.warn("player eq: " + data)
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                console.warn("player eq: «qs -c " + root.audioConfigName
                    + " ipc call audio openEqualizer» вернул " + exitCode
                    + " — причина в сообщении qs выше (нет экземпляра, target или функции)")
        }
    }

    Timer {
        id: openAudioTimer
        interval: 180
        onTriggered: {
            const m = root.audioModule
            if (m && typeof m.openEqualizer === "function")
                m.openEqualizer()
            else if (!openAudioProc.running)
                openAudioProc.running = true
        }
    }

    function openAudioModule() {
        root.hide()
        openAudioTimer.start()
    }

    // ------------------------- BARSLIDER -------------------------

    component BarSlider: Item {
        id: bs

        property var root
        property real value: 0          
        property bool interactive: true
        property int holdMs: 0         
        property real dragFrac: -1
        readonly property real shown: bs.dragFrac >= 0 ? bs.dragFrac : Math.max(0, Math.min(1, bs.value))

        signal started()
        signal dragged(real frac)
        signal committed(real frac)
        signal scrolled(real direction)

        implicitHeight: 18

        function resetDrag() {
            holdTimer.stop()
            bs.dragFrac = -1
        }

        onInteractiveChanged: if (!bs.interactive) bs.resetDrag()

        Timer {
            id: holdTimer
            interval: bs.holdMs
            onTriggered: bs.dragFrac = -1
        }

        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 8
            radius: 4
            color: bs.root.bgTrack
            opacity: bs.interactive ? 1.0 : 0.4

            Rectangle {
                height: parent.height
                radius: 4
                width: track.width * bs.shown

                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: bs.root.accentSecondary }
                    GradientStop { position: 1.0; color: bs.root.accentPrimary }
                }

                Behavior on width {
                    enabled: !area.pressed
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }
            }
        }

        Rectangle {
            width: 14
            height: 14
            radius: 7
            color: bs.root.thumbColor
            opacity: bs.interactive ? 1.0 : 0.4
            scale: area.pressed ? 1.15 : 1.0
            y: track.y + track.height / 2 - height / 2
            x: Math.max(0, Math.min(track.width - width, track.width * bs.shown - width / 2))

            Behavior on x {
                enabled: !area.pressed
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
            }
        }

        MouseArea {
            id: area
            anchors.fill: parent
            anchors.margins: -4
            enabled: bs.interactive
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            function frac(x) {
                return track.width > 0 ? Math.max(0, Math.min(1, (x - 4) / track.width)) : 0
            }

            onPressed: (mouse) => {
                holdTimer.stop()
                bs.started()
                bs.dragFrac = area.frac(mouse.x)
                bs.dragged(bs.dragFrac)
            }
            onPositionChanged: (mouse) => {
                if (pressed && bs.dragFrac >= 0) {
                    bs.dragFrac = area.frac(mouse.x)
                    bs.dragged(bs.dragFrac)
                }
            }
            onReleased: {
                const fraction = bs.dragFrac
                if (fraction < 0)
                    return
                if (bs.holdMs > 0)
                    holdTimer.restart()
                else
                    bs.dragFrac = -1
                bs.committed(fraction)
            }
            onCanceled: bs.resetDrag()
            onWheel: (wheel) => bs.scrolled(wheel.angleDelta.y > 0 ? 1 : -1)
        }
    }

    // ------------------------- ICON -------------------------

    component IconButton: Rectangle {
        id: btn

        property var root
        property string icon: ""
        property int iconSize: 18
        property int size: 36
        property bool active: false
        property bool accent: false
        property bool available: true
        property string badge: ""
        readonly property bool highlighted: accent || active || btnArea.pressed

        signal clicked()

        implicitWidth: size
        implicitHeight: size
        radius: 8
        opacity: available ? 1.0 : 0.35
        scale: btnArea.pressed ? 0.93 : 1.0

        color: highlighted ? btn.root.accentPrimary
             : btnArea.containsMouse ? btn.root.bgTrack
             : Qt.darker(btn.root.bgTrack, 1.08)
        border.width: 1
        border.color: highlighted ? btn.root.accentPrimary : btn.root.separatorColor

        Behavior on color { ColorAnimation { duration: 100 } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

        Text {
            anchors.centerIn: parent
            text: btn.icon
            font.pixelSize: btn.iconSize
            color: btn.highlighted ? btn.root.bgPanel : btn.root.textMain
            Behavior on color { ColorAnimation { duration: 100 } }
        }

        Text {
            visible: btn.badge !== ""
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 4
            anchors.bottomMargin: 2
            text: btn.badge
            font.pixelSize: 9
            font.bold: true
            color: btn.highlighted ? btn.root.bgPanel : btn.root.accentPrimary
        }

        MouseArea {
            id: btnArea
            anchors.fill: parent
            enabled: btn.available
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    // ------------------------- BUTTON 1 -------------------------

    component TabButton: Rectangle {
        id: tab

        property var root
        property string label: ""
        property bool selected: false

        signal clicked()

        Layout.fillWidth: true
        height: 30
        radius: 6
        color: tab.selected ? tab.root.accentPrimary
             : tabArea.containsMouse ? tab.root.accentSecondary
             : tab.root.bgTrack
        scale: tabArea.pressed ? 0.95 : 1.0

        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

        Text {
            anchors.centerIn: parent
            text: tab.label
            font.pixelSize: 12
            font.bold: tab.selected
            color: tab.selected ? tab.root.bgPanel : tab.root.textDim
        }

        MouseArea {
            id: tabArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tab.clicked()
        }
    }

    // ------------------------- COVER -------------------------

    component Cover: Item {
        id: cover

        property var root
        property string source: ""
        property int cornerRadius: 12

        readonly property bool hasArt: cover.source !== "" && art.status === Image.Ready

        Rectangle {
            id: placeholder
            anchors.fill: parent
            radius: cover.cornerRadius
            color: cover.root.bgTrack
            visible: !cover.hasArt

            Text {
                anchors.centerIn: parent
                text: "\u{F0387}"
                font.pixelSize: parent.width * 0.4
                color: cover.root.textDim
            }
        }

        Image {
            id: art
            anchors.fill: parent
            source: cover.source
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            smooth: true
            mipmap: true
            sourceSize.width: 400
            sourceSize.height: 400
            visible: false
            layer.enabled: true
        }

        Rectangle {
            id: artMask
            anchors.fill: parent
            radius: cover.cornerRadius
            visible: false
            layer.enabled: true
        }

        MultiEffect {
            anchors.fill: parent
            source: art
            visible: cover.hasArt
            maskEnabled: true
            maskSource: artMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        Rectangle {
            anchors.fill: parent
            radius: cover.cornerRadius
            color: "transparent"
            border.width: 1
            border.color: cover.root.separatorColor
        }
    }

    // ------------------------- LYRICS PAGE -------------------------

    component LyricsPage: Item {
        id: page
        property var root

        readonly property bool synced: page.root.lyricsState === "synced"

        Text {
            anchors.centerIn: parent
            visible: ["idle", "loading", "none", "error"].indexOf(page.root.lyricsState) !== -1
            horizontalAlignment: Text.AlignHCenter
            color: page.root.textDim
            font.pixelSize: 13
            font.italic: true
            text: page.root.lyricsState === "loading" ? "Ищу текст…"
                : page.root.lyricsState === "none" ? "Текст не найден"
                : page.root.lyricsState === "error" ? "Не удалось загрузить текст · повторить"
                : "Нет трека"

            MouseArea {
                anchors.fill: parent
                enabled: page.root.lyricsState === "error"
                cursorShape: Qt.PointingHandCursor
                onClicked: page.root.fetchLyrics()
            }
        }

        ListView {
            id: lv
            anchors.fill: parent
            anchors.bottomMargin: sourceLabel.visible ? 16 : 0
            visible: page.synced
            clip: true
            spacing: 6
            model: page.synced ? page.root.lyricLines : []
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: 20000

            highlightRangeMode: ListView.NoHighlightRange
            highlightFollowsCurrentItem: false

            readonly property int activeLine: page.root.activeLine
            readonly property real anchorFrac: 0.4   
            property bool userHold: false            

            header: Item { width: lv.width; height: lv.height * 0.4 }
            footer: Item { width: lv.width; height: lv.height * 0.6 }

            NumberAnimation {
                id: scrollAnim
                target: lv
                property: "contentY"
                duration: 600
                easing.type: Easing.OutCubic
            }

            function scrollToActive(animated) {
                if (lv.userHold || !lv.visible || lv.height <= 0 || lv.count === 0)
                    return
                let target = lv.originY
                if (lv.activeLine >= 0) {
                    lv.forceLayout()
                    const item = lv.itemAtIndex(lv.activeLine)
                    if (!item) {
                        scrollAnim.stop()
                        lv.positionViewAtIndex(lv.activeLine, ListView.Center)
                        return
                    }
                    target = item.y + item.height / 2 - lv.height * lv.anchorFrac
                }
                const maxY = lv.originY + lv.contentHeight - lv.height
                target = Math.max(lv.originY, Math.min(maxY, target))
                scrollAnim.stop()
                if (animated && Math.abs(target - lv.contentY) > 0.5) {
                    scrollAnim.from = lv.contentY
                    scrollAnim.to = target
                    scrollAnim.start()
                } else {
                    lv.contentY = target
                }
            }

            onActiveLineChanged: lv.scrollToActive(true)
            onCountChanged: Qt.callLater(lv.scrollToActive, false)
            onHeightChanged: Qt.callLater(lv.scrollToActive, false)
            onVisibleChanged: if (visible) Qt.callLater(lv.scrollToActive, false)

            Connections {
                target: page.root
                function onExpandedChanged() {
                    if (page.root.expanded)
                        Qt.callLater(lv.scrollToActive, false)
                }
            }

            onMovementStarted: {
                scrollAnim.stop()
                resumeTimer.stop()
                lv.userHold = true
            }
            onMovementEnded: resumeTimer.restart()

            Timer {
                id: resumeTimer
                interval: 2500
                onTriggered: {
                    lv.userHold = false
                    lv.scrollToActive(true)
                }
            }

            delegate: Item {
                id: lineItem
                required property var modelData
                required property int index

                readonly property bool current: index === page.root.activeLine
                readonly property int distance: Math.abs(index - Math.max(0, page.root.activeLine))

                width: lv.width
                height: lineText.implicitHeight + 4

                Text {
                    id: lineText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: lineItem.modelData.text !== "" ? lineItem.modelData.text : "♪"
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                    renderType: Text.QtRendering
                    transformOrigin: Item.Center
                    scale: lineItem.current ? 1.0 : 0.84
                    color: lineItem.current ? page.root.textMain : page.root.textDim
                    opacity: lineItem.current ? 1.0 : Math.max(0.25, 0.75 - lineItem.distance * 0.13)

                    Behavior on scale { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 400; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: (page.root.player && page.root.player.canSeek) ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: page.root.seekTo(lineItem.modelData.t)
                }
            }
        }

        Flickable {
            id: plainFlick
            anchors.fill: parent
            anchors.bottomMargin: sourceLabel.visible ? 16 : 0
            visible: page.root.lyricsState === "plain"
            clip: true
            contentWidth: width
            contentHeight: plainText.implicitHeight + 16
            boundsBehavior: Flickable.StopAtBounds

            Text {
                id: plainText
                width: plainFlick.width - 12
                x: 6
                y: 4
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 1.15
                text: page.root.plainLyrics
                color: page.root.textMain
                font.pixelSize: 14
            }
        }

    }

    // ------------------------- SPECTRUM -------------------------

    component Spectrum: ColumnLayout {
        id: spectrum
        property var root
        spacing: 5

        RowLayout {
            Layout.fillWidth: true


            Item { Layout.fillWidth: true }

            Text {
                id: spectrumStatus
                readonly property bool retryable: spectrum.root.cavaWanted
                    && (spectrum.root.cavaState === "missing" || spectrum.root.cavaState === "error")
                text: !spectrum.root.cavaWanted ? "Пауза"
                    : spectrum.root.cavaState === "missing" ? "Установите cava · повторить"
                    : spectrum.root.cavaState === "error" ? "Недоступно · повторить"
                    : spectrum.root.cavaState === "starting" ? "Подключение…"
                    : ""
                color: retryable && retryArea.containsMouse ? spectrum.root.accentPrimary : spectrum.root.textDim
                font.pixelSize: 9

                MouseArea {
                    id: retryArea
                    anchors.fill: parent
                    anchors.margins: -3
                    enabled: spectrumStatus.retryable
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: spectrum.root.syncCava()
                }
            }
        }

        Item {
            id: spectrumBars
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            clip: true
            readonly property real gap: 3
            readonly property real barWidth: Math.max(1,
                (width - gap * (spectrum.root.cavaBarCount - 1)) / spectrum.root.cavaBarCount)

            Repeater {
                model: spectrum.root.cavaBarCount

                delegate: Rectangle {
                    required property int index
                    readonly property real level: spectrum.root.cavaLevels[index] || 0
                    x: index * (spectrumBars.barWidth + spectrumBars.gap)
                    anchors.bottom: parent.bottom
                    width: spectrumBars.barWidth
                    height: 2 + level * (spectrumBars.height - 2)
                    radius: 2
                    opacity: level > 0 ? 0.9 : 0.25
                    gradient: Gradient {
                        GradientStop { position: 0; color: spectrum.root.accentPrimary }
                        GradientStop { position: 1; color: spectrum.root.accentSecondary }
                    }

                    Behavior on height {
                        NumberAnimation { duration: 65; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }
            }
        }
    }

    // ------------------------- EQCURVE -------------------------

    component EqCurve: Item {
        id: curve
        property var root
        implicitHeight: 108

        Canvas {
            id: curveCanvas
            anchors.fill: parent
            anchors.margins: 6
            antialiasing: true
            property color accent: Theme.accentPrimary
            onAccentChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                if (width <= 0 || height <= 0)
                    return
                const mid = height / 2
                const inset = 4
                const span = Math.max(0, width - 2 * inset)
                const amplitude = Math.max(0, mid - inset)
                const gains = curve.root.eqGains

                ctx.strokeStyle = curve.root.separatorColor
                ctx.lineWidth = 1
                ctx.beginPath()
                ctx.moveTo(inset, mid)
                ctx.lineTo(width - inset, mid)
                ctx.stroke()
                if (!gains.length)
                    return

                const points = []
                for (let i = 0; i < gains.length; i++) {
                    points.push({
                        x: gains.length > 1 ? inset + span * i / (gains.length - 1) : width / 2,
                        y: mid - Math.max(-12, Math.min(12, gains[i])) / 12 * amplitude
                    })
                }
                ctx.strokeStyle = curve.root.accentPrimary
                ctx.lineWidth = 2
                ctx.lineJoin = "round"
                ctx.lineCap = "round"
                ctx.beginPath()
                ctx.moveTo(points[0].x, points[0].y)
                for (let i = 1; i < points.length; i++)
                    ctx.lineTo(points[i].x, points[i].y)
                ctx.stroke()
                ctx.fillStyle = curve.root.accentPrimary
                for (let i = 0; i < points.length; i++) {
                    ctx.beginPath()
                    ctx.arc(points[i].x, points[i].y, 2.5, 0, Math.PI * 2)
                    ctx.fill()
                }
            }

            Connections {
                target: curve.root
                function onEqGainsChanged() { curveCanvas.requestPaint() }
                function onAccentPrimaryChanged() { curveCanvas.requestPaint() }
                function onSeparatorColorChanged() { curveCanvas.requestPaint() }
            }
        }
    }

    // ------------------------- EQ PAGE -------------------------

    component EqPage: Item {
        id: eqPage
        property var root

        ColumnLayout {
            anchors.fill: parent
            spacing: 10
            visible: eqPage.root.eqAvailable

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Профиль"
                    color: eqPage.root.textDim
                    font.pixelSize: 12
                }

                Text {
                    Layout.fillWidth: true
                    text: eqPage.root.eqPresetName
                    color: eqPage.root.accentPrimary
                    font.pixelSize: 12
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    text: "±12 дБ"
                    color: eqPage.root.textDim
                    font.pixelSize: 10
                }
            }

            EqCurve {
                root: eqPage.root
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 60
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8

                Text {
                    text: eqPage.root.eqFreqs.length > 0 ? eqPage.root.freqLabel(eqPage.root.eqFreqs[0]) : ""
                    color: eqPage.root.textDim
                    font.pixelSize: 10
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "Частота, Гц"
                    color: eqPage.root.textDim
                    font.pixelSize: 10
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: eqPage.root.eqFreqs.length > 1
                        ? eqPage.root.freqLabel(eqPage.root.eqFreqs[eqPage.root.eqFreqs.length - 1]) : ""
                    color: eqPage.root.textDim
                    font.pixelSize: 10
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 32
                radius: 8
                color: openEqArea.pressed ? eqPage.root.accentPrimary
                    : openEqArea.containsMouse ? eqPage.root.bgTrack : Qt.darker(eqPage.root.bgTrack, 1.08)
                border.width: 1
                border.color: openEqArea.pressed ? eqPage.root.accentPrimary : eqPage.root.separatorColor
                scale: openEqArea.pressed ? 0.96 : 1.0

                Behavior on color { ColorAnimation { duration: 100 } }
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

                Text {
                    anchors.centerIn: parent
                    text: "Настроить эквалайзер"
                    font.pixelSize: 12
                    color: openEqArea.pressed ? eqPage.root.bgPanel : eqPage.root.textMain
                }

                MouseArea {
                    id: openEqArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: eqPage.root.openAudioModule()
                }
            }
        }

        Column {
            anchors.centerIn: parent
            width: parent.width
            visible: !eqPage.root.eqAvailable
            spacing: 10

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                text: "Профиль эквалайзера не найден"
                color: eqPage.root.textDim
                font.pixelSize: 13
                font.italic: true
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                width: eqPage.width - 40
                wrapMode: Text.WordWrap
                text: "Задайте полосы во вкладке «Эквалайзер» аудио-модуля — они появятся здесь"
                color: eqPage.root.textDim
                font.pixelSize: 11
                opacity: 0.8
            }
        }
    }

    // ------------------------- CARD -------------------------

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

        SequentialAnimation {
            id: openAnim

            ScriptAction {
                script: {
                    headerSection.opacity = 0
                    headerSectionTranslate.y = -12
                    contentSection.opacity = 0
                    contentSectionTranslate.y = -12
                }
            }

            ParallelAnimation {
                NumberAnimation { target: card; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
                NumberAnimation { target: card; property: "scale"; to: 1; duration: 190; easing.type: Easing.OutBack; easing.overshoot: 1.1 }

                SequentialAnimation {
                    PauseAnimation { duration: 35 }
                    ParallelAnimation {
                        NumberAnimation { target: headerSection; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
                        NumberAnimation { target: headerSectionTranslate; property: "y"; to: 0; duration: 170; easing.type: Easing.OutCubic }
                    }
                }

                SequentialAnimation {
                    PauseAnimation { duration: 70 }
                    ParallelAnimation {
                        NumberAnimation { target: contentSection; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
                        NumberAnimation { target: contentSectionTranslate; property: "y"; to: 0; duration: 170; easing.type: Easing.OutCubic }
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

        focus: true
        Keys.onEscapePressed: {
            if (root.sourceMenuOpen)
                root.sourceMenuOpen = false
            else
                root.hide()
        }
        Keys.onSpacePressed: root.playPause()
        Keys.onLeftPressed: root.seekTo(root.position - 5)
        Keys.onRightPressed: root.seekTo(root.position + 5)

        // ------------------------- EMPTY STATE -------------------------

        Column {
            anchors.centerIn: parent
            spacing: 12
            visible: root.player === null

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "\u{F0387}"
                font.pixelSize: 56
                color: root.textDim
                opacity: 0.6
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Ничего не запущено"
                font.pixelSize: 14
                font.italic: true
                color: root.textDim
            }
        }

        // ------------------------- MAIN -------------------------

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12
            visible: root.player !== null

            // ------------------------- HEADER -------------------------

            ColumnLayout {
                id: headerSection
                Layout.fillWidth: true
                spacing: 12
                opacity: 0

                transform: Translate {
                    id: headerSectionTranslate
                    y: -12
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    Cover {
                        Layout.preferredWidth: 124
                        Layout.preferredHeight: 124
                        root: root
                        source: root.trackArtUrl
                    }

                    ColumnLayout {
                        id: infoColumn
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 4

                        onYChanged: if (root.sourceMenuOpen) root.updateSourceMenuAnchor()
                        onWidthChanged: if (root.sourceMenuOpen) root.updateSourceMenuAnchor()

                        
                        Rectangle {
                            id: sourceHeader
                            Layout.fillWidth: true
                            implicitHeight: 30
                            topLeftRadius: 6
                            topRightRadius: 6
                            bottomLeftRadius: root.sourceMenuOpen ? 0 : 6
                            bottomRightRadius: root.sourceMenuOpen ? 0 : 6
                            color: root.bgTrack
                            border.width: (sourceHeaderArea.containsMouse && !root.sourceMenuOpen) ? 1 : 0
                            border.color: root.accentPrimary

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 6

                                Text {
                                    text: "\u{F0387}"
                                    color: root.accentPrimary
                                    font.pixelSize: 13
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.player ? root.playerName(root.player) : "Нет плееров"
                                    color: root.textMain
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: root.manualPlayer === null
                                    text: "авто"
                                    color: root.textDim
                                    font.pixelSize: 10
                                }

                                Text {
                                    text: root.sourceMenuOpen ? "▴" : "▾"
                                    color: root.textDim
                                    font.pixelSize: 10
                                }
                            }

                            MouseArea {
                                id: sourceHeaderArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleSourceMenu()
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            text: root.trackTitle !== "" ? root.trackTitle : "Без названия"
                            color: root.textMain
                            font.pixelSize: 17
                            font.bold: true
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: root.trackArtist !== ""
                            text: root.trackArtist
                            color: root.accentPrimary
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: root.trackAlbum !== ""
                            text: root.trackAlbum
                            color: root.textDim
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    BarSlider {
                        id: progressBar
                        property var dragPlayer: null
                        property int dragTrackId: -1
                        property real dragLength: 0
                        Layout.fillWidth: true
                        root: root
                        holdMs: 450
                        interactive: root.player !== null && root.player.canSeek
                            && root.player.positionSupported && root.trackLength > 0
                        value: root.trackLength > 0 ? root.position / root.trackLength : 0
                        onStarted: {
                            dragPlayer = root.player
                            dragTrackId = root.currentTrackId
                            dragLength = root.trackLength
                        }
                        onCommitted: (frac) => {
                            if (dragPlayer === root.player && dragTrackId === root.currentTrackId && dragLength > 0)
                                root.seekTo(frac * dragLength)
                        }
                        onScrolled: (dir) => root.seekTo(root.position + dir * 5)

                        Connections {
                            target: root
                            function onKnownPlayerChanged() { progressBar.resetDrag() }
                            function onCurrentTrackIdChanged() { progressBar.resetDrag() }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: root.formatTime(progressBar.dragFrac >= 0 ? progressBar.dragFrac * root.trackLength : root.position)
                            color: root.textDim
                            font.pixelSize: 11
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: root.trackLength > 0 ? root.formatTime(root.trackLength) : "--:--"
                            color: root.textDim
                            font.pixelSize: 11
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8

                    Item { Layout.fillWidth: true }

                    IconButton {
                        root: root
                        icon: "\u{F049D}"
                        iconSize: 18
                        size: 36
                        available: root.player !== null && root.player.shuffleSupported
                        active: root.player !== null && root.player.shuffle
                        onClicked: root.player.shuffle = !root.player.shuffle
                    }

                    IconButton {
                        root: root
                        icon: "\u{F04AE}"
                        iconSize: 20
                        size: 36
                        available: root.player !== null && root.player.canGoPrevious
                        onClicked: root.previous()
                    }

                    IconButton {
                        root: root
                        accent: true
                        icon: root.isPlaying ? "\u{F03E4}" : "\u{F040A}"
                        iconSize: 24
                        size: 44
                        available: root.player !== null && root.player.canTogglePlaying
                        onClicked: root.playPause()
                    }

                    IconButton {
                        root: root
                        icon: "\u{F04AD}"
                        iconSize: 20
                        size: 36
                        available: root.player !== null && root.player.canGoNext
                        onClicked: root.next()
                    }

                    IconButton {
                        root: root
                        icon: "\u{F0456}"
                        iconSize: 18
                        size: 36
                        available: root.player !== null && root.player.loopSupported
                        active: root.player !== null && root.player.loopState !== MprisLoopState.None
                        badge: (root.player !== null && root.player.loopState === MprisLoopState.Track) ? "1" : ""
                        onClicked: root.cycleLoop()
                    }

                    Item { Layout.fillWidth: true }
                }

                Spectrum {
                    root: root
                    Layout.fillWidth: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: root.separatorColor
                }


                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    TabButton {
                        root: root
                        label: "Текст"
                        selected: root.currentTab === "lyrics"
                        onClicked: root.currentTab = "lyrics"
                    }

                    TabButton {
                        root: root
                        label: "Эквалайзер"
                        selected: root.currentTab === "eq"
                        onClicked: root.currentTab = "eq"
                    }
                }
            }

            // ------------------------- PAGES -------------------------

            Item {
                id: contentSection
                Layout.fillWidth: true
                Layout.fillHeight: true
                opacity: 0

                transform: Translate {
                    id: contentSectionTranslate
                    y: -12
                }

                LyricsPage {
                    anchors.fill: parent
                    root: root
                    opacity: root.currentTab === "lyrics" ? 1 : 0
                    enabled: root.currentTab === "lyrics"
                    y: root.currentTab === "lyrics" ? 0 : -10

                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }

                EqPage {
                    anchors.fill: parent
                    root: root
                    opacity: root.currentTab === "eq" ? 1 : 0
                    enabled: root.currentTab === "eq"
                    y: root.currentTab === "eq" ? 0 : 10

                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
            }
        }

        // ------------------------- DROPDOWN -------------------------

        MouseArea {
            anchors.fill: parent
            z: 50
            enabled: root.sourceMenuOpen
            onPressed: (mouse) => {
                root.sourceMenuOpen = false
                mouse.accepted = true
            }
            onWheel: (wheel) => { wheel.accepted = true }
        }

        Rectangle {
            id: sourceDropdown
            z: 60
            x: root.sourceMenuAnchor.x
            y: root.sourceMenuAnchor.y + root.sourceMenuAnchor.height
            width: root.sourceMenuAnchor.width
            height: root.sourceMenuOpen ? Math.min(sourceList.contentHeight, 176) : 0
            topLeftRadius: 0
            topRightRadius: 0
            bottomLeftRadius: 6
            bottomRightRadius: 6
            color: root.bgTrack
            clip: true
            visible: height > 0

            Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

            ListView {
                id: sourceList
                anchors.fill: parent
                model: root.sourceMenuModel
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: sourceItem
                    required property var modelData
                    readonly property var itemPlayer: modelData.player
                    readonly property bool isAuto: itemPlayer === null
                    readonly property bool isCurrent: sourceItem.isAuto
                        ? root.manualPlayer === null
                        : root.manualPlayer === sourceItem.itemPlayer

                    width: sourceList.width
                    height: 40
                    color: sourceItemArea.containsMouse ? root.accentSecondary
                         : (sourceItem.isCurrent ? Qt.rgba(1, 1, 1, 0.06) : "transparent")

                    Behavior on color { ColorAnimation { duration: 120 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                Layout.fillWidth: true
                                text: sourceItem.isAuto ? "Автоматически" : root.playerName(sourceItem.itemPlayer)
                                color: sourceItem.isCurrent ? root.accentPrimary : root.textMain
                                font.pixelSize: 12
                                font.bold: sourceItem.isCurrent
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: sourceItem.isAuto
                                    ? "Играющий или последний активный"
                                    : root.playerTrackLine(sourceItem.itemPlayer)
                                color: root.textDim
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            visible: !sourceItem.isAuto
                            text: sourceItem.itemPlayer && sourceItem.itemPlayer.isPlaying ? "\u{F040A}" : "\u{F03E4}"
                            color: sourceItem.itemPlayer && sourceItem.itemPlayer.isPlaying
                                ? root.accentPrimary : root.textDim
                            font.pixelSize: 12
                        }
                    }

                    MouseArea {
                        id: sourceItemArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectSource(sourceItem.itemPlayer)
                    }
                }
            }
        }

        Rectangle {
            z: 61
            x: root.sourceMenuAnchor.x
            y: root.sourceMenuAnchor.y
            width: root.sourceMenuAnchor.width
            height: root.sourceMenuAnchor.height + sourceDropdown.height
            color: "transparent"
            radius: 6
            border.width: 1
            border.color: root.accentPrimary
            visible: root.sourceMenuOpen
        }
    }
}
