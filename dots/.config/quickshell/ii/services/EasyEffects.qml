pragma Singleton
pragma ComponentBehavior: Bound

import qs
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string helper: Quickshell.env("HOME") + "/.local/bin/easyeffects-qs"
    property bool available: false
    property bool active: false
    property bool bypassed: false
    property string preset: ""
    property list<string> presets: []
    property string error: ""
    readonly property bool busy: actionProc.running

    function fetchAvailability() { fetchActiveState() }
    function fetchActiveState() {
        if (!stateProc.running && !root.busy) stateProc.running = true
    }
    function runAction(args) {
        if (root.busy) return
        root.error = ""
        actionProc.command = [root.helper].concat(args)
        actionProc.running = true
    }
    function disable() { runAction(["effects-off"]) }
    function enable() { runAction(["effects-on"]) }
    function show() { runAction(["show"]) }
    function toggle() { root.active && !root.bypassed ? disable() : enable() }
    function selectPreset(name) { runAction(["preset", name]) }

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (GlobalStates.sidebarRightOpen) root.fetchActiveState()
        }
    }
    Timer {
        id: reconcileTimer
        interval: 100
        onTriggered: root.fetchActiveState()
    }
    Timer {
        interval: 2000
        running: GlobalStates.sidebarRightOpen
        repeat: true
        onTriggered: root.fetchActiveState()
    }
    Process {
        id: stateProc
        running: true
        command: [root.helper, "state"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const state = JSON.parse(text)
                    root.available = state.available
                    root.active = state.active
                    root.bypassed = state.bypassed
                    root.preset = state.preset
                    root.presets = state.presets
                } catch (error) {
                    root.error = "Could not read EasyEffects status"
                }
            }
        }
    }
    Process {
        id: actionProc
        stderr: StdioCollector { id: actionErrors }
        onExited: (code, status) => {
            root.error = code === 0 ? "" : actionErrors.text.trim()
            reconcileTimer.restart()
        }
    }
    IpcHandler {
        target: "easyeffects"
        function status(): string {
            return JSON.stringify({active: root.active, bypassed: root.bypassed, preset: root.preset,
                presets: root.presets, busy: root.busy, error: root.error})
        }
        function refresh(): void { root.fetchActiveState() }
        function toggle(): void { root.toggle() }
        function show(): void { root.show() }
        function selectPreset(name: string): void { root.selectPreset(name) }
    }
}
