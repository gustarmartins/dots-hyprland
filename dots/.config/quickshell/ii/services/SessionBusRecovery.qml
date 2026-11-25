import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray

Scope {
    id: root

    // Initialize the host before the monitor checks this process's registration.
    readonly property var trayModel: SystemTray.items
    // Defer destructive exit-75 restarts while a Wayland session lock is active;
    // exiting while holding WlSessionLock triggers the compositor's crashed-lockscreen fallback.
    property bool deferRestart: false
    property int deferredRestartDelayMs: 300
    property bool restartPending: false
    property string state: "starting"
    property string reason: ""

    PersistentProperties {
        id: retained
        reloadableId: "sessionBusGeneration"
        property string generation: Quickshell.env("QS_SESSION_BUS_ID") || ""
    }

    function scheduleRecovery(delayMs) {
        if (root.deferRestart) {
            root.restartPending = true;
            root.state = "deferred";
            recover.stop();
            return;
        }
        root.restartPending = false;
        root.state = "recovering";
        recover.interval = delayMs;
        recover.restart();
    }

    onDeferRestartChanged: {
        if (root.deferRestart) {
            if (recover.running || root.state === "recovering") {
                recover.stop();
                root.restartPending = true;
                root.state = "deferred";
            }
        } else if (root.restartPending) {
            console.warn("[SessionBusRecovery] screen unlocked; resuming deferred restart (" + root.reason + ")");
            root.scheduleRecovery(root.deferredRestartDelayMs);
        }
    }

    function consume(line) {
        let event;
        try { event = JSON.parse(line); } catch (error) { return; }
        if (event.event === "connected") {
            const replaced = retained.generation !== "" && retained.generation !== event.generation;
            if (replaced || !event.shellRegistered) {
                reason = replaced ? "session bus replaced" : "shell absent from current session bus";
                if (root.deferRestart) {
                    console.warn("[SessionBusRecovery] " + reason + "; deferring shell restart while screen is locked");
                    root.scheduleRecovery(root.deferredRestartDelayMs);
                } else {
                    console.warn("[SessionBusRecovery] " + reason + "; restarting this shell's Qt services");
                    root.scheduleRecovery(1);
                }
            } else {
                retained.generation = event.generation;
                restartPending = false;
                state = "connected";
                retry.interval = 1000;
            }
        } else if (event.event === "disconnected" || event.event === "unavailable") {
            if (!root.restartPending) {
                state = "waiting-for-bus";
            }
        }
    }

    Process {
        id: monitor
        command: ["/usr/bin/python3", Quickshell.shellPath("scripts/session_bus.py"), "--pid", String(Quickshell.processId)]
        running: true
        stdout: SplitParser { onRead: line => root.consume(line) }
        onExited: {
            if (root.state !== "recovering") {
                if (!root.restartPending) {
                    root.state = "monitor-stopped";
                }
                retry.restart();
            }
        }
    }

    Timer {
        id: retry
        interval: 1000
        onTriggered: {
            monitor.running = true;
            interval = Math.min(interval * 2, 30000);
        }
    }

    Timer {
        id: recover
        interval: 1
        // A QML reload retains Qt's dead process-wide connection. Exit through
        // normal destruction so saved state/children are flushed; the existing
        // shell supervisor recognizes this temporary failure and relaunches.
        onTriggered: {
            if (root.deferRestart) {
                root.restartPending = true;
                root.state = "deferred";
                return;
            }
            Qt.exit(75);
        }
    }

    IpcHandler {
        target: "sessionBus"
        function status(): string {
            return JSON.stringify({state: root.state, generation: retained.generation,
                reason: root.reason, deferred: root.restartPending,
                pid: Quickshell.processId, monitorPid: monitor.processId});
        }
    }
}
