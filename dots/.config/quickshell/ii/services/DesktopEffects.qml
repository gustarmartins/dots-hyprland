pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
Singleton {
    id: root
    property var settings: ({})
    readonly property var palettes: ({aurora: ["#b8a1ff", "#7bdfff", "#f4b8dc"], sunset: ["#ffb86c", "#ff6b9d", "#c792ea"], ocean: ["#59d8ff", "#6b8bff", "#a5f3fc"], emerald: ["#65e6b4", "#c5f57c", "#60c9d9"]})
    readonly property var colors: palettes[settings.palette ?? "aurora"]
    FileView {
        id: state
        path: Quickshell.env("HOME") + "/.local/state/desktop-effects/state.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.settings = JSON.parse(text()); }
            catch (e) { console.warn("Desktop effects: invalid state", e); }
        }
    }
}
