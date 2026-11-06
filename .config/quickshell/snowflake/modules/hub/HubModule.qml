import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "../../services"

PanelWindow {
    id: root

    // ------------------------- WINDOW -------------------------
    visible: false
    focusable: true
    WlrLayershell.keyboardFocus: root.expanded ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    property bool expanded: false
    property bool closing: false

    property int savedWorkspaceId: 0

    property bool settingsOpen: false
    property string settingsSection: "weather"

    function openSettings(section) {
        if (section)
            root.settingsSection = section
        root.activeDropdown = null
        root.settingsOpen = true
    }

    function closeSettings() {
        root.activeDropdown = null
        root.settingsOpen = false
        card.forceActiveFocus()
    }

    function toggleSettings() {
        if (root.settingsOpen)
            root.closeSettings()
        else
            root.openSettings("")
    }

    property Item activeDropdown: null

    screen: Quickshell.screens[0]

    // ------------------------- OPEN / CLOSE -------------------------
    function show() {
        root.closing = false
        root.reloadColors()
        if (!root.visible)
            root.visible = true
        const ws = Hyprland.focusedWorkspace
        root.savedWorkspaceId = ws ? ws.id : 0
        focusGrab.active = true
        root.mask = null
        root.expanded = true
        Qt.callLater(function() {
            if (root.expanded)
                card.forceActiveFocus()
        })
    }

    function hide() {
        if (!root.expanded || root.closing)
            return
        root.closing = true
        focusGrab.active = false
        root.mask = emptyRegion
        root.activeDropdown = null
        root.settingsOpen = false
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

    // ------------------------- GEOMETRY -------------------------
    anchors.top: true
    margins.top: 30

    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    readonly property int pad: 20
    readonly property int gap: 16
    readonly property int pageGap: 48
    // Hub рисуется в эталонном размере baseWidth x baseHeight и масштабируется целиком (см. services/UiScale.qml)
    readonly property int baseWidth: 1500
    readonly property int baseHeight: 800
    readonly property real uiScale: UiScale.scaleFor("hub", root.screen, root.baseWidth, root.baseHeight)
    readonly property int colWidth: Math.floor((root.baseWidth - 2 * root.pad - 4 * root.gap - 2) / 3)

    implicitWidth: Math.round(root.baseWidth * root.uiScale)
    implicitHeight: Math.round(root.baseHeight * root.uiScale)

    // ------------------------- PAGES -------------------------
    readonly property var pages: [
        { title: "Главная" },
        { title: "Активность" }
    ]
    property int currentPage: 0

    function goToPage(index) {
        const next = Math.max(0, Math.min(root.pages.length - 1, index))
        if (root.settingsOpen)
            root.closeSettings()
        if (next !== root.currentPage) {
            root.activeDropdown = null
            root.currentPage = next
        }
    }

    // ------------------------- COLORS -------------------------
    readonly property var themeColors: Theme.hex

    function themeColor(key, fallback) {
        const v = root.themeColors[key]
        return (typeof v === "string" && /^#[0-9a-fA-F]{6,8}$/.test(v)) ? v : fallback
    }

    property color accentPrimary:   root.themeColor("accent_primary",   "#5fa77c")
    property color accentSecondary: root.themeColor("accent_secondary", "#446b56")
    property color bgPanel:         root.themeColor("bg_panel_battery", "#1c211e")
    property color bgTrack:         root.themeColor("bg_track",         "#2a322d")
    property color bgInput:         root.themeColor("bg_input_wofi",    "#1e2d26")
    property color textMain:        root.themeColor("text_main",        "#eef3ef")
    property color textDim:         root.themeColor("text_dim",         "#8fa196")
    property color workspaceActive: root.themeColor("workspace_active", "#6e8f72")
    property color hoverLight:      root.themeColor("hover_light",      "#b7d3a8")
    property color inputTextColor:  root.themeColor("wofi_input_text",  "#e8f0ec")
    property color accentText:      root.themeColor("wofi_accent_text", "#cdd6f4")

    Behavior on accentPrimary   { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on accentSecondary { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on bgPanel         { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on bgTrack         { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on bgInput         { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on textMain        { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on textDim         { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on workspaceActive { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on hoverLight      { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }

    function luminance(c) {
        const f = x => x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4)
        return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b)
    }
    function contrast(a, b) {
        const la = root.luminance(a), lb = root.luminance(b)
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
    }

    readonly property color onWorkspaceActive: root.contrast(root.bgPanel, root.workspaceActive) >= 3
        ? root.bgPanel : root.textMain
    readonly property color weekendColor: root.contrast(root.hoverLight, root.bgPanel) >= 2.2
        ? root.hoverLight : root.accentSecondary

    readonly property color borderColor: accentPrimary
    readonly property color separatorColor: Qt.rgba(1, 1, 1, 0.08)
    readonly property color hoverColor: Qt.rgba(1, 1, 1, 0.06)
    readonly property color danger: "#c96a5a"

    readonly property var wallpaperTheme: wallpaperThemeItem
    readonly property string dataDir: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/snowflake/hub"

    WallpaperTheme {
        id: wallpaperThemeItem
        hub: root
    }

    function reloadColors() {
        Theme.reload()
    }

    // ------------------------- FONTS -------------------------
    readonly property string monoFont: "JetBrainsMono Nerd Font"
    readonly property string iconFont: "Symbols Nerd Font"

    // ------------------------- FOCUS -------------------------
    HyprlandFocusGrab {
        id: focusGrab
        windows: [root]
        onCleared: root.hide()
    }

    Connections {
        target: Hyprland
        enabled: root.expanded && !root.closing

        function onRawEvent(event) {
            const n = event.name
            if (n === "workspacev2") {
                if (parseInt(event.data) !== root.savedWorkspaceId)
                    root.hide()
            } else if (n === "focusedmonv2") {
                if (parseInt(event.data.split(",")[1]) !== root.savedWorkspaceId)
                    root.hide()
            } else if (n === "activespecial") {
                root.hide()
            }
        }

        function onFocusedWorkspaceChanged() {
            const ws = Hyprland.focusedWorkspace
            if (ws && ws.id !== root.savedWorkspaceId)
                root.hide()
        }
    }

    onVisibleChanged: {
        if (visible && !root.expanded)
            root.expanded = true
    }

    // ------------------------- CARD -------------------------
    Item {
        id: scaler
        width: root.baseWidth
        height: root.baseHeight
        scale: root.uiScale
        transformOrigin: Item.TopLeft
    }

    Rectangle {
        id: card
        parent: scaler
        anchors.fill: parent
        radius: 8
        color: root.bgPanel
        border.width: 3
        border.color: root.borderColor

        transformOrigin: Item.Top
        opacity: 0
        scale: 0.9

        focus: true

        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: {
                root.activeDropdown = null
                card.forceActiveFocus()
            }
        }

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                if (root.settingsOpen)
                    root.closeSettings()
                else
                    root.hide()
                event.accepted = true
            } else if (!card.activeFocus || root.settingsOpen) {
                return
            } else if (event.key === Qt.Key_Left) {
                root.goToPage(root.currentPage - 1)
                event.accepted = true
            } else if (event.key === Qt.Key_Right) {
                root.goToPage(root.currentPage + 1)
                event.accepted = true
            } else if (event.key >= Qt.Key_1 && event.key < Qt.Key_1 + root.pages.length) {
                root.goToPage(event.key - Qt.Key_1)
                event.accepted = true
            }
        }

        // ------------------------- ANIMATIONS -------------------------
        SequentialAnimation {
            id: openAnim

            ScriptAction {
                script: {
                    headerSection.opacity = 0
                    headerTranslate.y = -12
                    pager.opacity = 0
                    pagerTranslate.y = -12
                }
            }

            ParallelAnimation {
                NumberAnimation { target: card; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
                NumberAnimation { target: card; property: "scale"; to: 1; duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.1 }

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
                        NumberAnimation { target: pager; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
                        NumberAnimation { target: pagerTranslate; property: "y"; to: 0; duration: 170; easing.type: Easing.OutCubic }
                    }
                }
            }
        }

        SequentialAnimation {
            id: closeAnim
            ParallelAnimation {
                NumberAnimation { target: card; property: "opacity"; to: 0; duration: 110; easing.type: Easing.InCubic }
                NumberAnimation { target: card; property: "scale"; to: 0.9; duration: 110; easing.type: Easing.InCubic }
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

        // ------------------------- CONTENT -------------------------
        ColumnLayout {
            id: layout
            anchors.fill: parent
            anchors.margins: root.pad
            spacing: 0

            // ------------------------- HEADER -------------------------
            Item {
                id: headerSection
                Layout.fillWidth: true
                implicitHeight: Math.max(pageSwitch.implicitHeight, 40) + 8
                opacity: 0

                transform: Translate {
                    id: headerTranslate
                    y: -12
                }

                Row {
                    id: pageSwitch
                    anchors.centerIn: parent
                    spacing: 10

                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        hub: root
                        size: 32
                        glyph: ""
                        glyphColor: root.textDim
                        opacity: root.currentPage > 0 ? 1 : 0.3
                        onClicked: root.goToPage(root.currentPage - 1)

                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }

                    PageTabs {
                        id: pageTabs
                        anchors.verticalCenter: parent.verticalCenter
                        hub: root
                        pages: root.pages
                        currentIndex: root.currentPage
                        tabWidth: 150
                        onSelected: function(index) { root.goToPage(index) }
                    }

                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        hub: root
                        size: 32
                        glyph: ""
                        glyphColor: root.textDim
                        opacity: root.currentPage < root.pages.length - 1 ? 1 : 0.3
                        onClicked: root.goToPage(root.currentPage + 1)

                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }
                }

                IconButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    hub: root
                    size: 32
                    glyph: ""
                    glyphColor: root.settingsOpen ? root.accentPrimary : root.textMain
                    rotation: root.settingsOpen ? 90 : 0
                    onClicked: root.toggleSettings()

                    Behavior on rotation { Anim {} }
                }
            }

            Separator {}

            // ------------------------- PAGES -------------------------
            Item {
                id: pager
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.topMargin: 16
                clip: true
                opacity: 0

                transform: Translate {
                    id: pagerTranslate
                    y: -12
                }

                WheelHandler {
                    enabled: !root.settingsOpen
                    orientation: Qt.Horizontal
                    property real acc: 0
                    property double last: 0
                    onWheel: function(event) {
                        const now = Date.now()
                        if (now - last < 450)
                            return
                        acc += event.angleDelta.x
                        if (acc <= -120 || acc >= 120) {
                            root.goToPage(root.currentPage + (acc < 0 ? 1 : -1))
                            acc = 0
                            last = now
                        }
                    }
                }

                Item {
                    id: strip
                    width: pager.width * root.pages.length + root.pageGap * (root.pages.length - 1)
                    height: pager.height
                    x: -root.currentPage * (pager.width + root.pageGap)

                    Behavior on x { Anim {} }

                    // ------------------------- PAGE 1: HOME -------------------------
                    RowLayout {
                        id: homePage
                        x: 0
                        width: pager.width
                        height: pager.height
                        spacing: root.gap
                        enabled: root.currentPage === 0
                        opacity: root.currentPage === 0 ? 1 : 0

                        Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

                        // ------------------------- THEME + CALENDAR + PROFILE -------------------------
                        ColumnLayout {
                            Layout.preferredWidth: root.colWidth
                            Layout.minimumWidth: root.colWidth
                            Layout.maximumWidth: root.colWidth
                            Layout.fillHeight: true
                            spacing: 14

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                z: (themePicker.popupVisible || wallpaperPicker.popupVisible) ? 100 : 1

                                ThemePicker {
                                    id: themePicker
                                    hub: root
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                }

                                WallpaperPicker {
                                    id: wallpaperPicker
                                    hub: root
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                }
                            }

                            Separator {}

                            SectionHeader {
                                hub: root
                                title: "Календарь"
                            }

                            CalendarCard {
                                id: calendarCard
                                hub: root
                                Layout.fillWidth: true
                                z: calendarCard.popupOpen ? 100 : 1
                            }

                            Separator {}

                            ProfileCard {
                                hub: root
                                Layout.fillWidth: true
                            }

                            Item { Layout.fillHeight: true }
                        }

                        Separator { vertical: true }

                        // ------------------------- CLOCK + TIMER + WORLD CLOCK -------------------------
                        ColumnLayout {
                            Layout.preferredWidth: root.colWidth
                            Layout.minimumWidth: root.colWidth
                            Layout.maximumWidth: root.colWidth
                            Layout.fillHeight: true
                            spacing: 14

                            ClockCard {
                                hub: root
                                Layout.fillWidth: true
                                Layout.topMargin: 10
                            }

                            SectionHeader {
                                hub: root
                                Layout.topMargin: 6
                                title: timerCard.title
                                badge: timerCard.statusText
                                badgeAccent: timerCard.running
                            }

                            TimerCard {
                                id: timerCard
                                hub: root
                                Layout.fillWidth: true
                            }

                            Separator {}

                            SectionHeader {
                                hub: root
                                title: "Мировое время"
                            }

                            WorldClockCard {
                                id: worldClockCard
                                hub: root
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                            }
                        }

                        Separator { vertical: true }

                        // ------------------------- WEATHER -------------------------
                        ColumnLayout {
                            Layout.preferredWidth: root.colWidth
                            Layout.minimumWidth: root.colWidth
                            Layout.maximumWidth: root.colWidth
                            Layout.fillHeight: true
                            spacing: 14

                            WeatherCard {
                                id: weatherCard
                                hub: root
                                animate: root.expanded && root.currentPage === 0
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                            }
                        }
                    }

                    // ------------------------- PAGE 2: ACTIVITY -------------------------
                    RowLayout {
                        id: activityPage
                        x: pager.width + root.pageGap
                        width: pager.width
                        height: pager.height
                        spacing: root.gap
                        enabled: root.currentPage === 1
                        opacity: root.currentPage === 1 ? 1 : 0

                        Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

                        // ------------------------- UPTIME + TOP 3 -------------------------
                        ColumnLayout {
                            Layout.preferredWidth: root.colWidth
                            Layout.minimumWidth: root.colWidth
                            Layout.maximumWidth: root.colWidth
                            Layout.fillHeight: true
                            spacing: 14

                            SectionHeader {
                                hub: root
                                title: "Аптайм"
                            }

                            UptimeCard {
                                id: uptimeCard
                                hub: root
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                            }
                        }

                        Separator { vertical: true }

                        // ------------------------- APP USAGE -------------------------
                        ColumnLayout {
                            Layout.preferredWidth: root.colWidth
                            Layout.minimumWidth: root.colWidth
                            Layout.maximumWidth: root.colWidth
                            Layout.fillHeight: true
                            spacing: 14

                            SectionHeader {
                                hub: root
                                title: "Программы за сегодня"
                                badge: uptimeCard.allAppsSorted.length > 0 ? String(uptimeCard.allAppsSorted.length) : ""
                            }

                            AppUsageCard {
                                hub: root
                                usage: uptimeCard
                                apps: appsCard
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                            }
                        }

                        Separator { vertical: true }

                        // ------------------------- OPEN WINDOWS -------------------------
                        ColumnLayout {
                            Layout.preferredWidth: root.colWidth
                            Layout.minimumWidth: root.colWidth
                            Layout.maximumWidth: root.colWidth
                            Layout.fillHeight: true
                            spacing: 14

                            SectionHeader {
                                hub: root
                                title: "Открытые окна"
                                badge: appsCard.count > 0 ? String(appsCard.count) : ""
                            }

                            AppsCard {
                                id: appsCard
                                hub: root
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                            }
                        }
                    }
                }

                // ------------------------- SETTINGS -------------------------
                SettingsWindow {
                    anchors.fill: parent
                    z: 50
                    hub: root
                    weather: weatherCard
                    worldClock: worldClockCard
                    timer: timerCard
                    open: root.settingsOpen
                    section: root.settingsSection
                    onCloseRequested: root.closeSettings()
                    onSectionRequested: function(id) { root.settingsSection = id }
                }
            }
        }
    }
}
