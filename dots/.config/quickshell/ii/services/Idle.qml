pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

/**
 * OS-like sleep, auto-sleep (AC / Battery), lid and Keep awake service backed by sleepctl.
 */
Singleton {
    id: root

    property bool inhibit: false
    property int acSleepMinutes: 0
    property int batterySleepMinutes: 15
    property string lidOnAc: "ignore"
    property string lidOnBattery: "suspend"
    property bool hasBattery: false
    property bool onAc: true
    property string powerSource: "ac"
    property int effectiveSleepMinutes: 0
    property string effectiveLidAction: "ignore"
    property bool inhibitorActive: false
    property string inhibitorWhat: ""
    property bool hypridleActive: false
    property bool ready: false
    property bool busy: false
    property string error: ""
    property int watchers: 0

    readonly property var timeoutModes: [
        { value: 0, label: "Never" },
        { value: 5, label: "5 minutes" },
        { value: 10, label: "10 minutes" },
        { value: 15, label: "15 minutes" },
        { value: 30, label: "30 minutes" },
        { value: 60, label: "1 hour" },
        { value: 120, label: "2 hours" }
    ]

    readonly property var lidModes: [
        { value: "ignore", label: "Stay awake" },
        { value: "suspend", label: "Sleep" }
    ]

    function formatMinutes(minutes) {
        if (minutes <= 0) return "Never";
        if (minutes === 60) return "1 hour";
        if (minutes % 60 === 0) return (minutes / 60) + " hours";
        return minutes + " min";
    }

    function accept(text) {
        try {
            const value = JSON.parse(text);
            if (value.error) {
                root.error = value.error;
                return;
            }
            if (typeof value.keepAwake === "boolean") {
                root.inhibit = value.keepAwake;
                if (Persistent.ready)
                    Persistent.states.idle.inhibit = value.keepAwake;
            }
            if (typeof value.acSleepMinutes === "number")
                root.acSleepMinutes = value.acSleepMinutes;
            if (typeof value.batterySleepMinutes === "number")
                root.batterySleepMinutes = value.batterySleepMinutes;
            if (typeof value.lidOnAc === "string")
                root.lidOnAc = value.lidOnAc;
            if (typeof value.lidOnBattery === "string")
                root.lidOnBattery = value.lidOnBattery;
            if (typeof value.hasBattery === "boolean")
                root.hasBattery = value.hasBattery;
            if (typeof value.onAc === "boolean")
                root.onAc = value.onAc;
            if (typeof value.powerSource === "string")
                root.powerSource = value.powerSource;
            if (typeof value.effectiveSleepMinutes === "number")
                root.effectiveSleepMinutes = value.effectiveSleepMinutes;
            if (typeof value.effectiveLidAction === "string")
                root.effectiveLidAction = value.effectiveLidAction;
            if (typeof value.inhibitorActive === "boolean")
                root.inhibitorActive = value.inhibitorActive;
            if (typeof value.inhibitorWhat === "string")
                root.inhibitorWhat = value.inhibitorWhat;
            if (typeof value.hypridleActive === "boolean")
                root.hypridleActive = value.hypridleActive;
            root.ready = true;
            root.error = "";
        } catch (e) {
            root.error = "Could not read sleep policy";
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
        writeProc.command = [Quickshell.env("HOME") + "/.local/bin/sleepctl"].concat(args);
        writeProc.running = true;
    }

    function sync() {
        runMutation(["sync"]);
    }

    function toggleInhibit(active = null) {
        const next = active !== null ? Boolean(active) : !root.inhibit;
        runMutation(["set", "--keep-awake", next ? "on" : "off"]);
    }

    function setAcSleep(minutes) {
        runMutation(["set", "--ac", String(minutes)]);
    }

    function setBatterySleep(minutes) {
        runMutation(["set", "--battery", String(minutes)]);
    }

    function setLidOnAc(action) {
        runMutation(["set", "--lid-ac", String(action)]);
    }

    function setLidOnBattery(action) {
        runMutation(["set", "--lid-battery", String(action)]);
    }

    Process {
        id: readProc
        command: [Quickshell.env("HOME") + "/.local/bin/sleepctl", "status"]
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
        interval: 4000
        repeat: true
        running: root.watchers > 0
        onTriggered: root.refresh()
    }

    onWatchersChanged: if (watchers > 0) refresh()

    // Re-apply policy immediately whenever AC power is plugged in or unplugged.
    Connections {
        target: UPower
        function onOnBatteryChanged() {
            powerSyncTimer.restart();
        }
    }

    Timer {
        id: powerSyncTimer
        interval: 350
        repeat: false
        onTriggered: root.sync()
    }

    Component.onCompleted: root.sync()
}
