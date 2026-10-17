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
    property var library: ({entries: [], count: 0, totalBytes: 0})
    property string libraryError: ""
    property bool maintenancePending: false
    property bool libraryLoaded: false
    property bool currentLoaded: false
    property bool progressLoaded: false
    property bool prefetchLoaded: false
    property var prefetchState: ({})
    property double localPrefetchAttemptAt: 0
    readonly property bool libraryBusy: libraryProcess.running
    property double clockNow: Date.now()
    readonly property double initializedAt: Date.now()
    property double localAttemptAt: 0
    readonly property bool sharedBusy: progress.busy === true && clockNow - (progress.startedAt || 0) * 1000 < 190000
    readonly property bool busy: fetchProcess.running || libraryProcess.running || sharedBusy
    readonly property string status: progress.busy === true && !busy
        ? "The last wallpaper fetch was interrupted. You can try again."
        : (progress.message || "")
    readonly property double intervalMs: Math.max(15, Config.options.background.discovery.intervalMinutes) * 60000
    readonly property double nextRotationAt: Math.max(
        (current.appliedAt || current.fetchedAt || 0) * 1000 || initializedAt,
        progress.busy === false && progress.operation !== "prefetch" ? (progress.updatedAt || 0) * 1000 : 0,
        localAttemptAt) + intervalMs
    readonly property string script: FileUtils.trimFileProtocol(Directories.scriptPath) + "/colors/random/discover_wallpaper.py"
    readonly property string stateDirectory: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/wallpaper-discovery"

    readonly property string libraryScript: FileUtils.trimFileProtocol(Directories.scriptPath) + "/colors/random/wallpaper_library.py"
    function libraryAction(args) {
        if (busy) return;
        root.libraryError = "";
        libraryProcess.command = ["python3", "-B", root.libraryScript].concat(args);
        libraryProcess.running = true;
    }
    function refreshLibrary() { root.libraryAction(["list"]); }
    function restore(identity) { root.libraryAction(["restore", identity]); }
    function keep(identity, value) { root.libraryAction(["keep", identity, "--value", value ? "true" : "false"]); }
    function scheduleMaintenance() { if (Config.ready) root.maintenancePending = true; }
    Component.onCompleted: Qt.callLater(root.refreshLibrary)
    Connections {
        target: Config.options.background.discovery
        function onStorageLimitMiBChanged() { root.scheduleMaintenance(); }
        function onMinFreeMiBChanged() { root.scheduleMaintenance(); }
    }
    Connections {
        target: Config.options.background
        function onWallpaperPathChanged() {
            if (fetchProcess.running || libraryProcess.running) return;
            if ((root.library.entries || []).some(entry => entry.current && entry.path === Config.options.background.wallpaperPath)) return;
            refreshTimer.restart();
        }
    }
    Timer {
        id: refreshTimer
        interval: 500
        onTriggered: if (!root.busy) root.refreshLibrary()
    }
    Timer {
        interval: 1000
        running: root.maintenancePending && !root.busy
        onTriggered: {
            Config.flushPendingWrites();
            root.maintenancePending = false;
            root.libraryAction(["prune"]);
        }
    }
    FileView {
        path: root.stateDirectory + "/library.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.library = JSON.parse(text()); root.libraryLoaded = true; }
            catch (error) { root.libraryError = "Saved wallpapers could not be read. Try Refresh."; }
        }
    }
    Process {
        id: libraryProcess
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    if (result.library) { root.library = result.library; root.libraryLoaded = true; }
                    root.libraryError = result.error || "";
                } catch (error) { root.libraryError = "The wallpaper history could not be updated. Try Refresh."; }
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && !root.libraryError) root.libraryError = "Wallpaper operation did not finish. Try Refresh.";
        }
    }

    function prefetch(count = Config.options.background.discovery.prefetchCount) {
        if (busy) return;
        root.localPrefetchAttemptAt = Date.now();
        root.progress = {message: "Prefetching wallpapers for preview…", busy: true, operation: "prefetch", startedAt: root.localPrefetchAttemptAt / 1000};
        fetchProcess.command = ["python3", "-B", root.script, "--theme", Config.options.background.discovery.theme, "--prefetch", String(count)];
        fetchProcess.running = true;
    }
    FileView {
        path: root.stateDirectory + "/prefetch.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.prefetchState = JSON.parse(text()); root.prefetchLoaded = true; } catch (error) {} }
        onLoadFailed: error => { if (error === FileViewError.FileNotFound) root.prefetchLoaded = true; }
    }
    function fetch(theme = Config.options.background.discovery.theme) {
        if (busy) return;
        localAttemptAt = Date.now();
        progress = {message: "Finding your next wallpaper…", busy: true, startedAt: localAttemptAt / 1000};
        fetchProcess.command = ["python3", "-B", root.script, "--theme", theme];
        fetchProcess.running = true;
    }

    FileView {
        id: currentFile
        path: root.stateDirectory + "/current.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.current = JSON.parse(text()); root.currentLoaded = true; } catch (error) { root.current = ({}); }
        }
        onLoadFailed: error => { if (error === FileViewError.FileNotFound) root.currentLoaded = true; }
    }
    // Settings and the desktop shell share progress, including automatic fetches.
    FileView {
        path: root.stateDirectory + "/status.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.progress = JSON.parse(text()); root.progressLoaded = true; } catch (error) { console.warn("Wallpaper status:", error); }
        }
        onLoadFailed: error => { if (error === FileViewError.FileNotFound) root.progressLoaded = true; }
    }

    Process {
        id: fetchProcess
        stdout: SplitParser {
            onRead: data => {
                try {
                    const update = JSON.parse(data);
                    root.progress = Object.assign({}, root.progress, update, {updatedAt: Date.now() / 1000});
                    if (update.path && update.operation !== "prefetch" && update.appliedAt) root.current = update;
                } catch (error) { console.warn("Wallpaper discovery:", data); }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: { if (text.trim()) console.log("Wallpaper discovery:", text.trim()); }
        }
        onExited: (exitCode, exitStatus) => {
            if (root.progress.busy !== false) root.progress = {
                message: "Wallpaper operation stopped. Try again shortly.", busy: false, operation: root.progress.operation, updatedAt: Date.now() / 1000
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
            // FileView is asynchronous. Do not refill an apparently empty queue
            // before its saved entries and cooldown have finished loading.
            if (!root.libraryLoaded || !root.currentLoaded || !root.progressLoaded || !root.prefetchLoaded) return;
            if (root.rotationOwner && Config.ready && Config.options.background.discovery.rotate
                && !root.busy && root.clockNow >= root.nextRotationAt) root.fetch();
            else if (root.rotationOwner && Config.ready && Config.options.background.discovery.rotate
                && Config.options.background.discovery.prefetchAhead && !root.busy
                && (root.library.entries || []).filter(entry => entry.queued && (Config.options.background.discovery.theme === "mix" || entry.theme === Config.options.background.discovery.theme)).length < Math.min(2, Config.options.background.discovery.prefetchCount)
                && root.clockNow > Math.max(root.localPrefetchAttemptAt, (root.prefetchState.attemptedAt || 0) * 1000) + 300000) {
                const ready = (root.library.entries || []).filter(entry => entry.queued && (Config.options.background.discovery.theme === "mix" || entry.theme === Config.options.background.discovery.theme)).length;
                root.prefetch(Math.max(1, Config.options.background.discovery.prefetchCount - ready));
            }
        }
    }

    IpcHandler {
        target: "wallpaperDiscovery"
        function next(): void { root.fetch(); }
        function themed(theme: string): void { root.fetch(theme); }
        function status(): string { return JSON.stringify({busy: root.busy, message: root.status, current: root.current,
            rotationEnabled: Config.options.background.discovery.rotate, rotationOwner: root.rotationOwner,
            intervalMinutes: Config.options.background.discovery.intervalMinutes, nextRotationAt: root.nextRotationAt,
            queuedCount: root.library.queuedCount, libraryCount: root.library.count, libraryBytes: root.library.totalBytes, libraryError: root.libraryError}); }
        function refreshHistory(): void { root.refreshLibrary(); }
    }
}
