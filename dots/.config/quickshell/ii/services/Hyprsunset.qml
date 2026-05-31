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

    property string from: Config.options?.light?.night?.from ?? "19:00" 
    property string to: Config.options?.light?.night?.to ?? "06:30"
    property bool automatic: Config.options?.light?.night?.automatic && (Config?.ready ?? true)
    property int colorTemperature: Config.options?.light?.night?.colorTemperature ?? 5000
    property int defaultColorTemperature: 6000
    property int gamma: 100
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
        Quickshell.execDetached(["bash", "-c", `pidof hyprsunset || hyprsunset`]);
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

    readonly property string stateFile: "/tmp/hyprsunset_active"

    function enableTemperature() {
        root.temperatureActive = true;
        // console.log("[Hyprsunset] Enabling");
        root.startHyprsunset();
        Quickshell.execDetached(["bash", "-c", `hyprctl hyprsunset temperature ${root.colorTemperature}`]);
        Quickshell.execDetached(["bash", "-c", `echo ${root.colorTemperature} > ${root.stateFile}`]);
        reconcileTimer.restart();
    }

    function disableTemperature() {
        root.temperatureActive = false;
        // console.log("[Hyprsunset] Disabling");
        Quickshell.execDetached(["bash", "-c", `hyprctl hyprsunset temperature ${root.defaultColorTemperature}`]);
        Quickshell.execDetached(["bash", "-c", `echo ${root.defaultColorTemperature} > ${root.stateFile}`]);
        reconcileTimer.restart();
    }

    function setGamma(gamma) {
        root.gamma = Math.max(root.gammaLowerLimit, Math.min(100, gamma));

        root.gammaChangeAttempt();

        root.startHyprsunset();
        Quickshell.execDetached(["bash", "-c", `hyprctl hyprsunset gamma ${root.gamma}`]);
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
        // Query hyprsunset directly instead of reading the tmpfs state file:
        // /tmp is RAM-backed here and is wiped on every reboot, which produced
        // a phantom "on" state. hyprsunset reports the default temperature
        // (defaultColorTemperature, 6000) when no warming filter is applied.
        command: ["bash", "-c", `hyprctl hyprsunset temperature 2>/dev/null || echo ${root.defaultColorTemperature}`]
        stdout: StdioCollector {
            id: stateCollector
            onStreamFinished: {
                const output = stateCollector.text.trim();
                const temp = parseInt(output);
                if (isNaN(temp) || temp <= 0 || output.startsWith("Couldn't"))
                    root.temperatureActive = false;
                else
                    root.temperatureActive = (temp != root.defaultColorTemperature); // 6000 == off
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
            Hyprland.dispatch(`hyprctl hyprsunset temperature ${Config.options.light.night.colorTemperature}`);
            Quickshell.execDetached(["hyprctl", "hyprsunset", "temperature", `${Config.options.light.night.colorTemperature}`]);
        }
    }
}
