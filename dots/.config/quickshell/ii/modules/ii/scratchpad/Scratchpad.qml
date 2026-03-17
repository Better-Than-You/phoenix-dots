import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs
import qs.modules.common

Scope {
    id: root

    Variants {
        model: Quickshell.screens

        delegate: Loader {
            id: scratchpadLoader
            required property var modelData

            active: GlobalStates.scratchpadOpen

            sourceComponent: ScratchpadSurface {
                screen: scratchpadLoader.modelData
                onDismiss: GlobalStates.scratchpadOpen = false
            }
        }
    }

    IpcHandler {
        target: "scratchpad"

        function toggle(): void {
            GlobalStates.scratchpadOpen = !GlobalStates.scratchpadOpen;
        }

        function open(): void {
            GlobalStates.scratchpadOpen = true;
        }

        function close(): void {
            GlobalStates.scratchpadOpen = false;
        }
    }

    GlobalShortcut {
        name: "scratchpadToggle"
        description: "Toggles screen annotation scratchpad"

        onPressed: {
            GlobalStates.scratchpadOpen = !GlobalStates.scratchpadOpen;
        }
    }
}
