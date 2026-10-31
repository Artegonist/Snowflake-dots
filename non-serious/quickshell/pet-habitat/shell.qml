import Quickshell
import Quickshell.Io

ShellRoot {
    PetModule {
        id: petModule
    }

    IpcHandler {
        target: "petModule"

        function toggle(): void {
            petModule.toggle()
        }

        function show(): void {
            petModule.show()
        }

        function hide(): void {
            petModule.hide()
        }
    }
}
