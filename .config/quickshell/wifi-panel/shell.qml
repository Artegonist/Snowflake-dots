import Quickshell
import Quickshell.Io

ShellRoot {
    id: shellRoot

    WifiPanel {
        id: wifiPanel
    }

    IpcHandler {
        target: "wifi"

        function toggle(): void {
            wifiPanel.toggle()
        }

        function show(): void {
            wifiPanel.show()
        }

        function hide(): void {
            wifiPanel.hide()
        }
    }
}
