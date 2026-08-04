import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    id: root
    name: Translation.tr("Triple buffer")
    toggled: toggled
    icon: "filter_3"

    // Disabled locally: enabling new render scheduling reproducibly causes a
    // DP-1 KMS modeset storm and stalls both outputs on this RX 6600 setup.
    mainAction: () => {}
    Process {
        id: fetchActiveState
        running: true
        command: ["bash", "-c", `test "$(hyprctl getoption render:new_render_scheduling -j | jq -r ".bool")" = true`]
        onExited: (exitCode, exitStatus) => {
            root.toggled = exitCode === 0
        }
    }
    tooltipText: Translation.tr("Disabled: freezes both displays on this system")
}
