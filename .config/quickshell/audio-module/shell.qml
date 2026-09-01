//   qs -c audio-module ipc call audio toggle
import Quickshell
import Quickshell.Io

ShellRoot {
    AudioPanel {
        id: audioPanel
    }

    IpcHandler {
        target: "audio"

        function toggle(): void {
            audioPanel.toggle()
        }

        function show(): void {
            audioPanel.show()
        }

        function hide(): void {
            audioPanel.hide()
        }
    }
}
