import Quickshell
import Quickshell.Io

ShellRoot {
    id: shellRoot

    // Сама панель — это PanelWindow, определённый в BluetoothPanel.qml
    // (implicit import: файл лежит в той же папке, поэтому доступен по имени типа)
    BluetoothPanel {
        id: bluetoothPanel
    }

    // Управление извне: из Hyprland-бинда, Waybar on-click и т.п.
    //   qs -c bluetooth ipc call bluetooth toggle
    //   qs -c bluetooth ipc call bluetooth show
    //   qs -c bluetooth ipc call bluetooth hide
    IpcHandler {
        target: "bluetooth"

        function toggle(): void { bluetoothPanel.toggle() }
        function show(): void { bluetoothPanel.show() }
        function hide(): void { bluetoothPanel.hide() }
    }
}
