pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root
    property bool rotationOwner: false
    property var current: ({})
    property var progress: ({})
    property double clockNow: Date.now()
    readonly property double initializedAt: Date.now()
    property double localAttemptAt: 0
    readonly property bool sharedBusy: progress.busy === true && clockNow - (progress.startedAt || 0) * 1000 < 190000
    readonly property bool busy: fetchProcess.running || sharedBusy
    readonly property string status: progress.busy === true && !busy
        ? "The last wallpaper fetch was interrupted. You can try again."
        : (progress.message || "")
    readonly property double intervalMs: Math.max(15, Config.options.background.discovery.intervalMinutes) * 60000
    readonly property double nextRotationAt: Math.max(
        (current.appliedAt || current.fetchedAt || 0) * 1000 || initializedAt,
        progress.busy === false ? (progress.updatedAt || 0) * 1000 : 0,
        localAttemptAt) + intervalMs
    readonly property string script: FileUtils.trimFileProtocol(Directories.scriptPath) + "/colors/random/discover_wallpaper.py"
    readonly property string stateDirectory: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/wallpaper-discovery"

    function fetch(theme = Config.options.background.discovery.theme) {
        if (busy) return;
        localAttemptAt = Date.now();
        progress = {message: "Finding your next wallpaper…", busy: true, startedAt: localAttemptAt / 1000};
        fetchProcess.command = ["python3", root.script, "--theme", theme];
        fetchProcess.running = true;
    }

    FileView {
        id: currentFile
        path: root.stateDirectory + "/current.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.current = JSON.parse(text()); } catch (error) { root.current = ({}); }
        }
    }
    // Settings and the desktop shell share progress, including automatic fetches.
    FileView {
        path: root.stateDirectory + "/status.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.progress = JSON.parse(text()); } catch (error) { console.warn("Wallpaper status:", error); }
        }
    }

    Process {
        id: fetchProcess
        stdout: SplitParser {
            onRead: data => {
                try {
                    const update = JSON.parse(data);
                    root.progress = Object.assign({}, root.progress, update, {updatedAt: Date.now() / 1000});
                    if (update.path) root.current = update;
                } catch (error) { console.warn("Wallpaper discovery:", data); }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: { if (text.trim()) console.log("Wallpaper discovery:", text.trim()); }
        }
        onExited: (exitCode, exitStatus) => {
            if (root.progress.busy !== false) root.progress = {
                message: "Wallpaper fetch stopped. Try again shortly.", busy: false, updatedAt: Date.now() / 1000
            };
        }
    }

    // Check a persisted deadline instead of resetting an hour-long timer on each
    // shell reload. Only the desktop owns rotation; Settings observes its state.
    Timer {
        interval: 15000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.clockNow = Date.now();
            if (root.rotationOwner && Config.ready && Config.options.background.discovery.rotate
                && !root.busy && root.clockNow >= root.nextRotationAt) root.fetch();
        }
    }

    IpcHandler {
        target: "wallpaperDiscovery"
        function next(): void { root.fetch(); }
        function themed(theme: string): void { root.fetch(theme); }
        function status(): string { return JSON.stringify({busy: root.busy, message: root.status, current: root.current,
            rotationEnabled: Config.options.background.discovery.rotate, rotationOwner: root.rotationOwner,
            intervalMinutes: Config.options.background.discovery.intervalMinutes, nextRotationAt: root.nextRotationAt}); }
    }
}
