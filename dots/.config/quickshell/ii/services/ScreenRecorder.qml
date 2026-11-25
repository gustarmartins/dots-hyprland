pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * OS-like hardware-accelerated screen recorder service backed by recordctl.
 */
Singleton {
    id: root

    property string preset: "gaming"
    property string backend: "gsr"
    property string codec: "hevc"
    property string quality: "high"
    property int fps: 60
    property string tune: "performance"
    property string frameRateMode: "vfr"
    property string bitrateMode: "qp"
    property bool lowPower: true
    property string pixfmt: "yuv420"
    property string colorRange: "limited"
    property string audioMode: "system"
    property string audioCodec: "opus"
    property string container: "mp4"
    property bool showCursor: true
    property string saveDir: ""

    property bool recording: false
    property int pid: 0
    property string activeBackend: ""
    property string activeOutput: ""
    property int elapsedSeconds: 0

    property bool hasGsr: false
    property bool hasKms: false
    property bool hasWfRecorder: false
    property var vaapiCodecs: []
    property string vaapiDriver: ""

    property bool ready: false
    property bool busy: false
    property string error: ""
    property int watchers: 0

    readonly property var presetModes: [
        { value: "gaming", label: "Gaming · Lowest FPS impact" },
        { value: "balanced", label: "Balanced · Crisp & light" },
        { value: "quality", label: "Archival · Max quality (10-bit)" },
        { value: "editing", label: "Editing · Fixed CFR H.264" },
        { value: "custom", label: "Custom" }
    ]

    readonly property var backendModes: [
        { value: "gsr", label: "GPU Screen Recorder (KMS zero-copy)" },
        { value: "wf-vaapi", label: "wf-recorder (Wayland VAAPI)" },
        { value: "wf-cpu", label: "wf-recorder (CPU x264)" }
    ]

    readonly property var codecModes: [
        { value: "hevc", label: "HEVC (H.265)" },
        { value: "hevc_10bit", label: "HEVC 10-bit" },
        { value: "h264", label: "H.264 (AVC)" },
        { value: "av1", label: "AV1" }
    ]

    readonly property var qualityModes: [
        { value: "medium", label: "Medium" },
        { value: "high", label: "High" },
        { value: "very_high", label: "Very high" },
        { value: "ultra", label: "Ultra" }
    ]

    readonly property var fpsModes: [
        { value: 30, label: "30 fps" },
        { value: 60, label: "60 fps" },
        { value: 120, label: "120 fps" },
        { value: 144, label: "144 fps" },
        { value: 0, label: "Monitor native" }
    ]

    readonly property var tuneModes: [
        { value: "performance", label: "Performance" },
        { value: "quality", label: "Quality" }
    ]

    readonly property var frameRateModes: [
        { value: "vfr", label: "VFR (Games/VRR)" },
        { value: "cfr", label: "CFR (Editors)" },
        { value: "content", label: "Content FPS" }
    ]

    readonly property var bitrateModes: [
        { value: "qp", label: "QP (Const. quality)" },
        { value: "vbr", label: "VBR" },
        { value: "cbr", label: "CBR" }
    ]

    readonly property var audioModes: [
        { value: "system", label: "System audio" },
        { value: "system_mic", label: "System + Mic" },
        { value: "mic", label: "Microphone" },
        { value: "none", label: "Muted" }
    ]

    readonly property var audioCodecModes: [
        { value: "opus", label: "Opus" },
        { value: "aac", label: "AAC" },
        { value: "flac", label: "FLAC" }
    ]

    readonly property var containerModes: [
        { value: "mp4", label: "MP4" },
        { value: "mkv", label: "MKV" }
    ]

    readonly property var pixfmtModes: [
        { value: "yuv420", label: "YUV 4:2:0" },
        { value: "yuv444", label: "YUV 4:4:4" }
    ]

    readonly property var colorRangeModes: [
        { value: "limited", label: "Limited" },
        { value: "full", label: "Full" }
    ]

    function formatElapsed(sec) {
        const s = Math.max(0, sec | 0);
        const mins = Math.floor(s / 60);
        const rem = s % 60;
        return (mins < 10 ? "0" : "") + mins + ":" + (rem < 10 ? "0" : "") + rem;
    }

    function accept(text) {
        try {
            const v = JSON.parse(text);
            if (v.error) {
                root.error = v.error;
                return;
            }
            if (typeof v.preset === "string") root.preset = v.preset;
            if (typeof v.backend === "string") root.backend = v.backend;
            if (typeof v.codec === "string") root.codec = v.codec;
            if (typeof v.quality === "string") root.quality = v.quality;
            if (typeof v.fps === "number") root.fps = v.fps;
            if (typeof v.tune === "string") root.tune = v.tune;
            if (typeof v.frameRateMode === "string") root.frameRateMode = v.frameRateMode;
            if (typeof v.bitrateMode === "string") root.bitrateMode = v.bitrateMode;
            if (typeof v.lowPower === "boolean") root.lowPower = v.lowPower;
            if (typeof v.pixfmt === "string") root.pixfmt = v.pixfmt;
            if (typeof v.colorRange === "string") root.colorRange = v.colorRange;
            if (typeof v.audioMode === "string") root.audioMode = v.audioMode;
            if (typeof v.audioCodec === "string") root.audioCodec = v.audioCodec;
            if (typeof v.container === "string") root.container = v.container;
            if (typeof v.showCursor === "boolean") root.showCursor = v.showCursor;
            if (typeof v.saveDir === "string") root.saveDir = v.saveDir;

            if (typeof v.recording === "boolean") root.recording = v.recording;
            if (typeof v.pid === "number") root.pid = v.pid;
            if (typeof v.activeBackend === "string") root.activeBackend = v.activeBackend;
            if (typeof v.activeOutput === "string") root.activeOutput = v.activeOutput;
            if (typeof v.elapsedSeconds === "number") root.elapsedSeconds = v.elapsedSeconds;

            if (v.hardware) {
                root.hasGsr = Boolean(v.hardware.hasGsr);
                root.hasKms = Boolean(v.hardware.hasKms);
                root.hasWfRecorder = Boolean(v.hardware.hasWfRecorder);
                root.vaapiCodecs = v.hardware.vaapiCodecs || [];
                root.vaapiDriver = v.hardware.vaapiDriver || "";
            }
            root.ready = true;
            root.error = "";
        } catch (e) {
            root.error = "Could not read recorder state";
        }
    }

    function refresh() {
        if (!readProc.running && !root.busy)
            readProc.running = true;
    }

    function runMutation(args) {
        if (root.busy) return;
        root.busy = true;
        root.error = "";
        writeProc.command = [Quickshell.env("HOME") + "/.local/bin/recordctl"].concat(args);
        writeProc.running = true;
    }

    function applyPreset(name) {
        if (name === "custom") return;
        runMutation(["preset", name]);
    }

    function setFlag(flag, value) {
        runMutation(["set", flag, String(value)]);
    }

    function toggleFullscreen(withSound) {
        const args = ["toggle", "--fullscreen"];
        if (withSound !== undefined)
            args.push(withSound ? "--sound" : "--no-sound");
        runMutation(args);
    }

    function stop() {
        runMutation(["stop"]);
    }

    Process {
        id: readProc
        command: [Quickshell.env("HOME") + "/.local/bin/recordctl", "status"]
        stdout: StdioCollector { onStreamFinished: root.accept(text) }
    }

    Process {
        id: writeProc
        stdout: StdioCollector { onStreamFinished: root.accept(text) }
        onExited: {
            root.busy = false;
            root.refresh();
        }
    }

    Timer {
        interval: root.recording ? 1000 : 3000
        repeat: true
        running: root.watchers > 0 || root.recording
        onTriggered: root.refresh()
    }

    onWatchersChanged: if (watchers > 0) refresh()
    Component.onCompleted: refresh()
}
