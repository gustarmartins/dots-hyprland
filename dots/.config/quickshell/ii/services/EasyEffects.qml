pragma Singleton
pragma ComponentBehavior: Bound

import qs
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Singleton {
    id: root

    readonly property string helper: Quickshell.env("HOME") + "/.local/bin/easyeffects-qs"
    property bool available: false
    property bool active: false
    property bool bypassed: false
    property bool stateKnown: false
    readonly property bool processing: stateKnown && active && !bypassed
    property string preset: ""
    property list<string> presets: []
    property string error: ""
    readonly property bool busy: actionProc.running
    property int stateGeneration: 0

    function fetchAvailability() { fetchActiveState() }
    function fetchActiveState() {
        if (!stateProc.running && !root.busy) {
            stateProc.generation = root.stateGeneration
            stateProc.running = true
        }
    }
    function runAction(args) {
        if (root.busy) return
        root.stateGeneration++
        root.error = ""
        actionProc.command = [root.helper].concat(args)
        actionProc.running = true
    }
    function disable() { runAction(["effects-off"]) }
    function enable() { runAction(["effects-on"]) }
    function show() { runAction(["show"]) }
    function toggle() { runAction(["effects-toggle"]) }
    function selectPreset(name) { runAction(["preset", name]) }

    function applyState(text) {
        try {
            const state = JSON.parse(text)
            root.available = state.available
            root.presets = state.presets
            root.stateKnown = state.known !== false
            if (!root.stateKnown) {
                root.error = state.error !== undefined ? state.error : "Could not read EasyEffects status"
                return
            }
            root.active = state.active
            root.bypassed = state.bypassed
            root.preset = state.preset
            if (state.error !== undefined) root.error = state.error
        } catch (error) {
            root.stateKnown = false
            root.error = "Could not read EasyEffects status"
        }
    }

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (GlobalStates.sidebarRightOpen) root.fetchActiveState()
        }
    }
    Connections {
        target: Pipewire
        function onDefaultAudioSinkChanged() { reconcileTimer.restart() }
        function onDefaultAudioSourceChanged() { reconcileTimer.restart() }
    }
    Connections {
        target: Pipewire.nodes
        function onValuesChanged() { reconcileTimer.restart() }
    }
    Timer {
        id: reconcileTimer
        interval: 100
        onTriggered: {
            root.fetchActiveState()
            if (!root.active) lateReconcileTimer.restart()
        }
    }
    Timer {
        id: lateReconcileTimer
        interval: 600
        onTriggered: root.fetchActiveState()
    }
    Timer {
        interval: 2000
        running: GlobalStates.sidebarRightOpen || !root.stateKnown
        repeat: true
        onTriggered: root.fetchActiveState()
    }
    Process {
        id: stateProc
        property int generation: 0
        running: true
        command: [root.helper, "state"]
        stdout: StdioCollector {
            onStreamFinished: {
                // A status request started before an action must not overwrite it.
                if (stateProc.generation === root.stateGeneration && !root.busy)
                    root.applyState(text)
            }
        }
    }
    Process {
        id: actionProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0) root.applyState(text)
            }
        }
        stderr: StdioCollector { id: actionErrors }
        onExited: (code, status) => {
            if (code !== 0) root.error = actionErrors.text.trim() || "EasyEffects action failed"
            else if (root.stateKnown) root.error = ""
            reconcileTimer.restart()
        }
    }
    IpcHandler {
        target: "easyeffects"
        function status(): string {
            return JSON.stringify({available: root.available, active: root.active, bypassed: root.bypassed,
                stateKnown: root.stateKnown,
                processing: root.processing, preset: root.preset,
                presets: root.presets, busy: root.busy, error: root.error})
        }
        function refresh(): void { root.fetchActiveState() }
        function toggle(): void { root.toggle() }
        function show(): void { root.show() }
        function selectPreset(name: string): void { root.selectPreset(name) }
    }
}
