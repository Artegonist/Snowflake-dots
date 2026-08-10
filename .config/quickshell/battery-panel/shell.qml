//   qs -c battery-panel ipc call batteryPanel toggle
import Quickshell
import Quickshell.Io

ShellRoot {
    BatteryPanel {
        id: batteryPanel
    }

    IpcHandler {
        target: "batteryPanel"

        function toggle(): void {
            batteryPanel.toggle()
        }

        function show(): void {
            batteryPanel.show()
        }

        function hide(): void {
            batteryPanel.hide()
        }
    }
}
