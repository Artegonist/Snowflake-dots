pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // ------------------------- SOURCE -------------------------
    readonly property string colorsPath: Quickshell.env("HOME") + "/.config/quickshell/snowflake/colors.json"

    function reload() {
        file.reload()
    }

    // ------------------------- COLORS -------------------------
    readonly property color accentPrimary: adapter.accent_primary
    readonly property color accentSecondary: adapter.accent_secondary
    readonly property color bgPanelWaybar: adapter.bg_panel_waybar
    readonly property color bgPanelBattery: adapter.bg_panel_battery
    readonly property color bgTrack: adapter.bg_track
    readonly property color bgInputWofi: adapter.bg_input_wofi
    readonly property color textMain: adapter.text_main
    readonly property color textDim: adapter.text_dim
    readonly property color textWaybar: adapter.text_waybar
    readonly property color workspaceActive: adapter.workspace_active
    readonly property color hoverLight: adapter.hover_light
    readonly property color hoverWofiSelect: adapter.hover_wofi_select
    readonly property color wofiInputText: adapter.wofi_input_text
    readonly property color wofiAccentText: adapter.wofi_accent_text
    readonly property color clockGlow: adapter.clock_glow

    readonly property var hex: ({
        accent_primary: adapter.accent_primary,
        accent_secondary: adapter.accent_secondary,
        bg_panel_waybar: adapter.bg_panel_waybar,
        bg_panel_battery: adapter.bg_panel_battery,
        bg_track: adapter.bg_track,
        bg_input_wofi: adapter.bg_input_wofi,
        text_main: adapter.text_main,
        text_dim: adapter.text_dim,
        text_waybar: adapter.text_waybar,
        workspace_active: adapter.workspace_active,
        hover_light: adapter.hover_light,
        hover_wofi_select: adapter.hover_wofi_select,
        wofi_input_text: adapter.wofi_input_text,
        wofi_accent_text: adapter.wofi_accent_text,
        clock_glow: adapter.clock_glow
    })

    // ------------------------- FILE -------------------------
    FileView {
        id: file
        path: root.colorsPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: adapter
            property string accent_primary: "#80deea"
            property string accent_secondary: "#006064"
            property string bg_panel_waybar: "#061012"
            property string bg_panel_battery: "#071113"
            property string bg_track: "#0f1e21"
            property string bg_input_wofi: "#0a1618"
            property string text_main: "#e0fbff"
            property string text_dim: "#5c9aa3"
            property string text_waybar: "#a7ffeb"
            property string workspace_active: "#80deea"
            property string hover_light: "#b2ebf2"
            property string hover_wofi_select: "#84ffff"
            property string wofi_input_text: "#eafffd"
            property string wofi_accent_text: "#80deea"
            property string clock_glow: "#18ffff"
        }
    }
}
