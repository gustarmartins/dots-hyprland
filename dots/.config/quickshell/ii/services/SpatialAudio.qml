pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    readonly property string helper: Quickshell.env("HOME") + "/.local/bin/mpv-spatial"
    readonly property string configPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/mpv/spatial.json"
    property bool enabled: false
    property bool automatic: true
    property string profile: "atmos-7.1"
    property string profileLabel: "Dolby Atmos 7.1 HRIR"
    property var profiles: [
        { id: "atmos-7.1", label: "Dolby Atmos 7.1 HRIR", detail: "14-channel HeSuVi binaural convolution (48 kHz)", available: true },
        { id: "sofa-kemar", label: "PipeWire SOFA 3D (KEMAR)", detail: "Native libmysofa spherical HRTF spatializer", available: true }
    ]
    property bool passthrough: false
    property bool hdmiDolby: false
    property string hdmiSummary: ""
    property bool running: false
    property string message: "Checking spatial audio…"
    property string error: ""
    readonly property bool busy: action.running
    function refresh() { if (!read.running && !action.running) read.running = true; }
    function run(args) { if (busy) return; error = ""; action.command = [helper].concat(args); action.running = true; }
    function setEnabled(value) { run([value ? "enable" : "disable"]); }
    function setAutomatic(value) { run(["automatic", value ? "true" : "false"]); }
    function setProfile(profileId) { run(["profile", profileId]); }
    function setPassthrough(value) { run(["passthrough", value ? "true" : "false"]); }
    FileView { path: root.configPath; watchChanges: true; onFileChanged: root.refresh() }
    Process {
        id: read
        running: true
        command: [root.helper, "status"]
        stdout: StdioCollector { id: result }
        onExited: (code, status) => {
            if (code !== 0) { root.error = "Could not read spatial audio status"; return; }
            try {
                const s = JSON.parse(result.text);
                root.enabled = !!s.enabled;
                root.automatic = s.automatic !== false;
                root.profile = s.profile || "atmos-7.1";
                root.profileLabel = s.profile_label || root.profile;
                if (Array.isArray(s.profiles) && s.profiles.length > 0) root.profiles = s.profiles;
                root.passthrough = !!s.passthrough;
                root.hdmiDolby = !!s.hdmi_dolby;
                root.hdmiSummary = s.hdmi_summary || "";
                root.running = !!s.running;
                root.message = s.message || "";
            } catch (e) { root.error = "Invalid spatial audio status"; }
        }
    }
    Process {
        id: action
        stderr: StdioCollector { id: errors }
        onExited: (code, status) => { root.error = code === 0 ? "" : errors.text.trim(); root.refresh(); }
    }
}
