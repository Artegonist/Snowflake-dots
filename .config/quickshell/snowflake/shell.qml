import QtQuick
import Quickshell
import Quickshell.Io
import "services"
import "modules/audio"
import "modules/battery"
import "modules/bluetooth"
import "modules/clipboard"
import "modules/hub"
import "modules/macrobar"
import "modules/osd"
import "modules/pet"
import "modules/player"
import "modules/powermenu"
import "modules/sysinfo"
import "modules/wifi"

ShellRoot {
    id: shellRoot

    // ------------------------- PANELS -------------------------
    AudioPanel {
        id: audioPanel
    }

    BatteryPanel {
        id: batteryPanel
    }

    BluetoothPanel {
        id: bluetoothPanel
    }

    HubModule {
        id: hubModule
    }

    MacroPanel {
        id: macroPanel
    }

    OsdModule {
        targetScreen: Quickshell.screens[0]
    }

    PetModule {
        id: petModule
    }

    PlayerPanel {
        id: playerPanel
        audioModule: audioPanel
    }

    PowerMenu {}

    SystemInfo {
        id: systemInfo
    }

    WifiPanel {
        id: wifiPanel
    }

    // ------------------------- CLIPBOARD -------------------------
    ClipboardService {
        id: clipboardService
    }

    ClipboardPanel {
        id: clipboardPanel
        service: clipboardService
    }

    // ------------------------- LINKS -------------------------
    Connections {
        target: hubModule

        function onExpandedChanged() {
            if (hubModule.expanded)
                clipboardPanel.hide()
        }
    }

    // ------------------------- IPC -------------------------
    IpcHandler {
        target: "audio"

        function toggle(): void { audioPanel.toggle() }
        function show(): void { audioPanel.show() }
        function hide(): void { audioPanel.hide() }
        function openEqualizer(): void { audioPanel.openEqualizer() }
    }

    IpcHandler {
        target: "batteryPanel"

        function toggle(): void { batteryPanel.toggle() }
        function show(): void { batteryPanel.show() }
        function hide(): void { batteryPanel.hide() }
    }

    IpcHandler {
        target: "bluetooth"

        function toggle(): void { bluetoothPanel.toggle() }
        function show(): void { bluetoothPanel.show() }
        function hide(): void { bluetoothPanel.hide() }
    }

    IpcHandler {
        target: "clipboardPanel"

        function toggle(): void { clipboardPanel.toggle() }
        function show(): void { clipboardPanel.show() }
        function hide(): void { clipboardPanel.hide() }
    }

    IpcHandler {
        target: "hub"

        function toggle(): void { hubModule.toggle() }
        function show(): void { hubModule.show() }
        function hide(): void { hubModule.hide() }
        function wallpaperTheme(): void { hubModule.wallpaperTheme.enable() }
        function wallpaperRefresh(): void { hubModule.wallpaperTheme.refresh() }
    }

    IpcHandler {
        target: "macroPanel"

        function toggle(): void { macroPanel.toggle() }
        function show(): void { macroPanel.show() }
        function hide(): void { macroPanel.hide() }
    }

    IpcHandler {
        target: "petModule"

        function toggle(): void { petModule.toggle() }
        function show(): void { petModule.show() }
        function hide(): void { petModule.hide() }
    }

    IpcHandler {
        target: "player"

        function toggle(): void { playerPanel.toggle() }
        function show(): void { playerPanel.show() }
        function hide(): void { playerPanel.hide() }
        function playPause(): void { playerPanel.playPause() }
        function next(): void { playerPanel.next() }
        function previous(): void { playerPanel.previous() }
    }

    IpcHandler {
        target: "sysinfo"

        function toggle(): void { systemInfo.toggle() }
        function show(): void { systemInfo.show() }
        function hide(): void { systemInfo.hide() }
    }

    IpcHandler {
        target: "wifi"

        function toggle(): void { wifiPanel.toggle() }
        function show(): void { wifiPanel.show() }
        function hide(): void { wifiPanel.hide() }
    }

    IpcHandler {
        target: "theme"

        function reload(): void { Theme.reload() }
    }
}
