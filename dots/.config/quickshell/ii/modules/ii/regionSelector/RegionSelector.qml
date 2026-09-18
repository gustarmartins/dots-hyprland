pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Scope {
    id: root

    property var action: RegionSelection.SnipAction.Copy
    property var selectionMode: RegionSelection.SelectionMode.RectCorners
    property var panels: []
    property bool busy: false
    property bool hidePanels: false
    property var recordingPanel: null
    property string sessionId: ""
    readonly property bool allPrepared: panels.length > 0 && panels.length === Quickshell.screens.length && panels.every(p => p.preparationDone)

    function dismiss() {
        focusGrab.active = false;
        GlobalStates.regionSelectorOpen = false;
    }
    function syncGrab() {
        focusGrab.active = GlobalStates.regionSelectorOpen && root.allPrepared && !root.hidePanels && !root.recordingPanel;
    }
    function addPanel(panel) { root.panels = [...root.panels, panel]; }
    function removePanel(panel) {
        root.panels = root.panels.filter(p => p !== panel);
        // A disappearing output invalidates a frozen multi-monitor session.
        if (GlobalStates.regionSelectorOpen && panel.sessionId === root.sessionId) root.dismiss();
    }
    function start(action, mode) {
        if (GlobalStates.regionSelectorOpen) return; // Repeated chords cannot reset a gesture.
        root.panels = [];
        root.busy = false;
        root.hidePanels = false;
        root.recordingPanel = null;
        root.action = action;
        root.selectionMode = mode;
        root.sessionId = Date.now().toString(36) + "-" + Math.random().toString(36).slice(2);
        HyprlandData.updateAll();
        GlobalStates.regionSelectorOpen = true;
    }
    onAllPreparedChanged: Qt.callLater(root.syncGrab)
    onHidePanelsChanged: Qt.callLater(root.syncGrab)
    onRecordingPanelChanged: Qt.callLater(root.syncGrab)

    HyprlandFocusGrab {
        id: focusGrab
        windows: root.panels.filter(p => p.visible && p.phase === RegionSelection.Phase.Select)
        onWindowsChanged: Qt.callLater(root.syncGrab)
        onCleared: {
            if (!GlobalStates.regionSelectorOpen || root.hidePanels || root.recordingPanel) return;
            for (const panel of root.panels) panel.cancelGesture();
            // Focus interruption cancels a gesture, never the selection session.
            Qt.callLater(root.syncGrab);
        }
    }
    Variants {
        model: Quickshell.screens
        delegate: Loader {
            id: regionSelectorLoader
            required property var modelData
            active: GlobalStates.regionSelectorOpen
            sourceComponent: RegionSelection {
                id: panel
                screen: regionSelectorLoader.modelData
                sessionId: root.sessionId
                sessionReady: root.allPrepared
                sessionBusy: root.busy
                sessionHidden: root.hidePanels || (root.recordingPanel !== null && root.recordingPanel !== panel)
                inputReady: focusGrab.active
                action: root.action
                selectionMode: root.selectionMode
                Component.onCompleted: {
                    panel.sessionId = root.sessionId; // Keep snapshot identity immutable through deferred destruction.
                    root.addPanel(panel);
                }
                Component.onDestruction: root.removePanel(panel)
                onDismiss: root.dismiss()
                onProcessing: (running, hide) => { root.busy = running; root.hidePanels = hide; }
                onRecordingStarted: root.recordingPanel = panel
                onPreparationFailed: message => {
                    Quickshell.execDetached(["notify-send", "Screenshot unavailable", message]);
                    root.dismiss();
                }
            }
        }
    }
    function screenshot() { root.start(RegionSelection.SnipAction.Copy, RegionSelection.SelectionMode.RectCorners); }
    function search() { root.start(RegionSelection.SnipAction.Search, Config.options.search.imageSearch.useCircleSelection ? RegionSelection.SelectionMode.Circle : RegionSelection.SelectionMode.RectCorners); }
    function ocr() { root.start(RegionSelection.SnipAction.CharRecognition, RegionSelection.SelectionMode.RectCorners); }
    property bool recordWithAudio: false
    Process {
        id: recordingCheck
        command: ["pidof", "wf-recorder"]
        onExited: (code, status) => {
            if (code === 0) {
                Quickshell.execDetached([Directories.recordScriptPath]);
                if (GlobalStates.regionSelectorOpen) root.dismiss();
            } else root.start(root.recordWithAudio ? RegionSelection.SnipAction.RecordWithSound : RegionSelection.SnipAction.Record,
                RegionSelection.SelectionMode.RectCorners);
        }
    }
    function beginRecord(withSound) {
        if (recordingCheck.running || root.busy || (GlobalStates.regionSelectorOpen && !root.recordingPanel)) return;
        root.recordWithAudio = withSound;
        recordingCheck.running = true;
    }
    function record() { root.beginRecord(false); }
    function recordWithSound() { root.beginRecord(true); }

    IpcHandler {
        target: "region"

        function status(): string {
            return JSON.stringify({open: GlobalStates.regionSelectorOpen, busy: root.busy,
                ready: root.allPrepared, grabbed: focusGrab.active,
                panels: root.panels.map(p => ({screen: p.screen.name, ready: p.preparationDone,
                    visible: p.visible, dragging: p.dragging, phase: p.phase}))});
        }

        function screenshot() {
            root.screenshot()
        }
        function search() {
            root.search()
        }
        function ocr() {
            root.ocr()
        }
        function record() {
            root.record()
        }
        function recordWithSound() {
            root.recordWithSound()
        }
    }

    GlobalShortcut {
        name: "regionScreenshot"
        description: "Takes a screenshot of the selected region"
        onPressed: root.screenshot()
    }
    GlobalShortcut {
        name: "regionSearch"
        description: "Searches the selected region"
        onPressed: root.search()
    }
    GlobalShortcut {
        name: "regionOcr"
        description: "Recognizes text in the selected region"
        onPressed: root.ocr()
    }
    GlobalShortcut {
        name: "regionRecord"
        description: "Records the selected region"
        onPressed: root.record()
    }
    GlobalShortcut {
        name: "regionRecordWithSound"
        description: "Records the selected region with sound"
        onPressed: root.recordWithSound()
    }
}
