import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray

Scope {
    id: root

    // Initialize the host before the monitor checks this process's registration.
    readonly property var trayModel: SystemTray.items
    property string state: "starting"
    property string reason: ""

    PersistentProperties {
        id: retained
        reloadableId: "sessionBusGeneration"
        property string generation: Quickshell.env("QS_SESSION_BUS_ID") || ""
    }

    function consume(line) {
        let event;
        try { event = JSON.parse(line); } catch (error) { return; }
        if (event.event === "connected") {
            const replaced = retained.generation !== "" && retained.generation !== event.generation;
            if (replaced || !event.shellRegistered) {
                reason = replaced ? "session bus replaced" : "shell absent from current session bus";
                state = "recovering";
                console.warn("[SessionBusRecovery] " + reason + "; restarting this shell's Qt services");
                recover.start();
            } else {
                retained.generation = event.generation;
                state = "connected";
                retry.interval = 1000;
            }
        } else if (event.event === "disconnected" || event.event === "unavailable") {
            state = "waiting-for-bus";
        }
    }

    Process {
        id: monitor
        command: ["/usr/bin/python3", Quickshell.shellPath("scripts/session_bus.py"), "--pid", String(Quickshell.processId)]
        running: true
        stdout: SplitParser { onRead: line => root.consume(line) }
        onExited: {
            if (root.state !== "recovering") {
                root.state = "monitor-stopped";
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
        onTriggered: Qt.exit(75)
    }

    IpcHandler {
        target: "sessionBus"
        function status(): string {
            return JSON.stringify({state: root.state, generation: retained.generation,
                reason: root.reason, pid: Quickshell.processId, monitorPid: monitor.processId});
        }
    }
}
