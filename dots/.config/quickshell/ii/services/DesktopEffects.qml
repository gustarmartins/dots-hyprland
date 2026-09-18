pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
Singleton {
    id: root
    property var settings: ({})
    property var storedPresets: []
    readonly property var savedPresets: storedPresets.map(entry => Object.assign({}, entry, {settings: root.normalized(entry.settings)}))
    property var animationProfiles: []
    Process {
        command: [Quickshell.env("HOME") + "/.local/bin/desktop-effects", "animations"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.animationProfiles = JSON.parse(text); }
                catch (e) { console.warn("Desktop effects: could not list animation profiles", e); }
            }
        }
    }
    function normalized(settings) {
        return Object.assign({motion_source: "custom", animation_profile: root.settings.animation_profile ?? "", profile_tempo: 100, profile_travel: -1, profile_bounce: 0, profile_workspace_style: "preset", profile_window_style: "preset"}, settings);
    }
    function reloadPresets() { presets.reload(); }
    FileView {
        id: presets
        path: Quickshell.env("HOME") + "/.config/desktop-effects/presets.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const entries = JSON.parse(text());
                if (!Array.isArray(entries)) throw new Error("Expected a preset list");
                root.storedPresets = entries;
            } catch (e) { console.warn("Desktop effects: invalid saved presets", e); }
        }
    }
    readonly property var palettes: ({aurora: ["#b8a1ff", "#7bdfff", "#f4b8dc"], sunset: ["#ffb86c", "#ff6b9d", "#c792ea"], ocean: ["#59d8ff", "#6b8bff", "#a5f3fc"], emerald: ["#65e6b4", "#c5f57c", "#60c9d9"]})
    readonly property var colors: palettes[settings.palette ?? "aurora"]
    FileView {
        id: state
        path: Quickshell.env("HOME") + "/.local/state/desktop-effects/state.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.settings = root.normalized(JSON.parse(text())); }
            catch (e) { console.warn("Desktop effects: invalid state", e); }
        }
    }
}
