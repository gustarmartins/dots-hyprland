pragma Singleton

import QtQuick
import qs.modules.common
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Simple hyprsunset service with automatic mode.
 * In theory we don't need this because hyprsunset has a config file, but it somehow doesn't work.
 * It should also be possible to control it via hyprctl, but it doesn't work consistently either so we're just killing and launching.
 */
Singleton {
    id: root
    signal gammaChangeAttempt()

    readonly property real gammaLowerLimit: 25
    readonly property string controlPath: `${Quickshell.env("HOME")}/.local/bin/hyprsunsetctl`

    property string from: Config.options?.light?.night?.from ?? "19:00" 
    property string to: Config.options?.light?.night?.to ?? "06:30"
    property bool automatic: Config.options?.light?.night?.automatic && (Config?.ready ?? true)
    property int colorTemperature: Config.options?.light?.night?.colorTemperature ?? 5000
    property int gamma: 100
    property int pendingGamma: 100
    property int gammaInFlight: 100
    property int pendingColorTemperature: colorTemperature
    property int colorTemperatureInFlight: colorTemperature
    property bool shouldBeOn
    property bool firstEvaluation: true
    property bool temperatureActive: false

    property int fromHour: Number(from.split(":")[0])
    property int fromMinute: Number(from.split(":")[1])
    property int toHour: Number(to.split(":")[0])
    property int toMinute: Number(to.split(":")[1])

    property int clockHour: DateTime.clock.hours
    property int clockMinute: DateTime.clock.minutes

    property var manualActive
    property int manualActiveHour
    property int manualActiveMinute

    onClockMinuteChanged: reEvaluate()
    onAutomaticChanged: {
        root.manualActive = undefined;
        root.firstEvaluation = true;
        reEvaluate();
    }

    function inBetween(t, from, to) {
        if (from < to) {
            return (t >= from && t <= to);
        } else {
            // Wrapped around midnight
            return (t >= from || t <= to);
        }
    }

    function reEvaluate() {
        const t = clockHour * 60 + clockMinute;
        const from = fromHour * 60 + fromMinute;
        const to = toHour * 60 + toMinute;
        const manualActive = manualActiveHour * 60 + manualActiveMinute;

        if (root.manualActive !== undefined && (inBetween(from, manualActive, t) || inBetween(to, manualActive, t))) {
            root.manualActive = undefined;
        }
        root.shouldBeOn = inBetween(t, from, to);
        if (firstEvaluation) {
            firstEvaluation = false;
            root.ensureState();
        }
    }

    onShouldBeOnChanged: ensureState()
    function ensureState() {
        // console.log("[Hyprsunset] Ensuring state:", root.shouldBeOn, "Automatic mode:", root.automatic);
        if (!root.automatic || root.manualActive !== undefined)
            return;
        if (root.shouldBeOn) {
            root.enableTemperature();
        } else {
            root.disableTemperature();
        }
    }

    function startHyprsunset() {
        Quickshell.execDetached([root.controlPath, "ensure"]);
    }

    function load() {
        root.startHyprsunset();
        root.ensureState();
    }

    Timer {
        id: updateHyprsunset
        interval: 100
        repeat: false
        onTriggered: {
            root.ensureState();
            root.setGamma(root.gamma);
        }
    }

    function enableTemperature() {
        root.temperatureActive = true;
        // console.log("[Hyprsunset] Enabling");
        Quickshell.execDetached([root.controlPath, "temperature", `${root.colorTemperature}`]);
        reconcileTimer.restart();
    }

    function disableTemperature() {
        root.temperatureActive = false;
        // console.log("[Hyprsunset] Disabling");
        // A temperature such as 6000 K is still a non-neutral color matrix.
        // Identity is the actual Hyprland/default color state; gamma remains
        // independently applied.
        Quickshell.execDetached([root.controlPath, "identity", "true"]);
        reconcileTimer.restart();
    }

    function setGamma(gamma) {
        root.gamma = Math.round(Math.max(root.gammaLowerLimit, Math.min(100, gamma)));
        root.pendingGamma = root.gamma;

        root.gammaChangeAttempt();

        root.startHyprsunset();
        gammaApplyTimer.restart();
    }

    // Slider drags can emit many values in a few milliseconds. Launching each
    // hyprctl command detached lets an older value finish after the final one,
    // leaving the UI at 100 while hyprsunset is still dimmed. Keep only the
    // newest request, apply one command at a time, then read the real state back.
    function applyPendingGamma() {
        if (gammaSetProc.running) {
            gammaApplyTimer.restart();
            return;
        }

        root.gammaInFlight = root.pendingGamma;
        gammaSetProc.command = [root.controlPath, "gamma", `${root.gammaInFlight}`];
        gammaSetProc.running = true;
    }

    function fetchGammaState() {
        if (gammaSetProc.running || gammaApplyTimer.running)
            return;
        gammaFetchProc.running = false;
        gammaFetchProc.running = true;
    }

    Timer {
        id: gammaApplyTimer
        // CTM updates damage every output.  Wait until the drag has settled
        // instead of committing a new full-display matrix every few ms.
        interval: 180
        repeat: false
        onTriggered: root.applyPendingGamma()
    }

    Timer {
        id: gammaReconcileTimer
        interval: 150
        repeat: false
        onTriggered: root.fetchGammaState()
    }

    Process {
        id: gammaSetProc
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 || root.pendingGamma !== root.gammaInFlight)
                gammaApplyTimer.restart();
            else
                gammaReconcileTimer.restart();
        }
    }

    Process {
        id: gammaFetchProc
        running: true
        command: [root.controlPath, "gamma"]
        stdout: StdioCollector {
            id: gammaCollector
            onStreamFinished: {
                const actualGamma = parseInt(gammaCollector.text.trim());
                if (!isNaN(actualGamma) && !gammaSetProc.running && !gammaApplyTimer.running) {
                    root.gamma = actualGamma;
                    root.pendingGamma = actualGamma;
                }
            }
        }
    }

    function fetchState() {
        fetchProc.running = true;
    }

    // After any enable/disable, re-query the real hyprsunset state so the UI
    // toggle can never get stuck showing the wrong value if the command
    // raced, failed, or hyprsunset wasn't up yet.
    Timer {
        id: reconcileTimer
        interval: 300
        repeat: false
        onTriggered: root.fetchState()
    }

    Process {
        id: fetchProc
        running: true
        // Identity is the only unambiguous neutral state.
        command: [root.controlPath, "identity", "get"]
        stdout: StdioCollector {
            id: stateCollector
            onStreamFinished: {
                const output = stateCollector.text.trim();
                root.temperatureActive = (output === "false");
                // console.log("[Hyprsunset] Fetched state:", output, "->", root.temperatureActive);
            }
        }
    }

    function toggleTemperature(active = undefined) {
        if (root.manualActive === undefined) {
            root.manualActive = root.temperatureActive;
            root.manualActiveHour = root.clockHour;
            root.manualActiveMinute = root.clockMinute;
        }

        root.manualActive = active !== undefined ? active : !root.manualActive;
        if (root.manualActive) {
            root.enableTemperature();
        } else {
            root.disableTemperature();
        }
    }

    // Change temp
    Connections {
        target: Config.options.light.night
        function onColorTemperatureChanged() {
            if (!root.temperatureActive) return;
            root.pendingColorTemperature = Config.options.light.night.colorTemperature;
            temperatureApplyTimer.restart();
        }
    }

    Timer {
        id: temperatureApplyTimer
        interval: 180
        repeat: false
        onTriggered: {
            if (temperatureSetProc.running) {
                restart();
                return;
            }
            root.colorTemperatureInFlight = root.pendingColorTemperature;
            temperatureSetProc.command = [root.controlPath, "temperature", `${root.colorTemperatureInFlight}`];
            temperatureSetProc.running = true;
        }
    }

    Process {
        id: temperatureSetProc
        onExited: {
            if (root.pendingColorTemperature !== root.colorTemperatureInFlight)
                temperatureApplyTimer.restart();
            else
                reconcileTimer.restart();
        }
    }

    // hyprsunset v0.4.0 applies one global CTM to every wl_output.  Reconcile
    // after hotplug only once the DRM connector has had time to settle.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (["monitoradded", "monitoraddedv2"].includes(event.name))
                monitorReconcileTimer.restart();
        }
    }

    Timer {
        id: monitorReconcileTimer
        interval: 2000
        repeat: false
        onTriggered: {
            if (root.temperatureActive)
                Quickshell.execDetached([root.controlPath, "temperature", `${root.colorTemperature}`]);
            else
                Quickshell.execDetached([root.controlPath, "identity", "true"]);
            root.setGamma(root.gamma);
        }
    }
}
