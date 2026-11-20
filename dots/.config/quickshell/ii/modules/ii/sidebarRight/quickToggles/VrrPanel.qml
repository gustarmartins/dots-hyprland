import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    objectName: "vrrPanel"
    implicitWidth: 440
    implicitHeight: 206
    property string selectedOutput: ""
    property bool watching: false
    property bool selectionInitialized: false
    readonly property bool pollingVisible: visible && (Window.window?.visible ?? false)
    readonly property var choices: [{name: "global", label: "Global default"}].concat(Vrr.monitors)
    readonly property var selected: Vrr.monitors.find(m => m.name === selectedOutput) ?? null
    readonly property int policy: selectedOutput === "global" ? Vrr.globalPolicy : (selected?.policy ?? -1)
    readonly property var modes: selectedOutput === "global" ? Vrr.modes
        : [{value: -1, label: "Follow global · " + (Vrr.modes.find(m => m.value === Vrr.globalPolicy)?.label ?? "")}].concat(Vrr.modes)
    function ensureSelection() {
        if (!selectionInitialized && Vrr.monitors.length > 0) {
            selectedOutput = Vrr.monitors.find(m => m.focused)?.name ?? Vrr.monitors[0].name;
            selectionInitialized = true;
        }
        if (!choices.some(m => m.name === selectedOutput))
            selectedOutput = Vrr.monitors.find(m => m.focused)?.name ?? Vrr.monitors[0]?.name ?? "global";
    }
    function watch() {
        if (watching === pollingVisible) return;
        watching = pollingVisible;
        Vrr.watchers += watching ? 1 : -1;
    }
    onPollingVisibleChanged: watch()
    Component.onCompleted: { ensureSelection(); watch(); }
    Component.onDestruction: if (watching) Vrr.watchers--
    Connections { target: Vrr; function onMonitorsChanged() { root.ensureSelection(); } }

    ColumnLayout {
        anchors.fill: parent
        spacing: 9
        RowLayout {
            Layout.fillWidth: true
            MaterialSymbol { text: "sync"; iconSize: 23; color: Appearance.m3colors.m3primary }
            StyledText { text: "Variable refresh rate"; font.pixelSize: 17; font.weight: Font.Medium; Layout.fillWidth: true }
            StyledText { text: Vrr.busy ? "Applying…" : "VRR"; color: Appearance.m3colors.m3onSurfaceVariant; font.pixelSize: 11 }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            StyledText { text: "Display"; Layout.preferredWidth: 48; font.pixelSize: 12 }
            StyledComboBox {
                id: monitorPicker
                objectName: "vrrMonitorPicker"
                Layout.fillWidth: true
                model: root.choices
                enabled: Vrr.ready && !Vrr.busy
                textRole: "label"
                valueRole: "name"
                currentIndex: Math.max(0, root.choices.findIndex(m => m.name === root.selectedOutput))
                onActivated: index => root.selectedOutput = root.choices[index].name
                Accessible.name: "VRR display"
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            StyledText { text: "Mode"; Layout.preferredWidth: 48; font.pixelSize: 12 }
            StyledComboBox {
                objectName: "vrrModePicker"
                Layout.fillWidth: true
                enabled: Vrr.ready && !Vrr.busy
                model: root.modes
                textRole: "label"
                valueRole: "value"
                currentIndex: Math.max(0, root.modes.findIndex(m => m.value === root.policy))
                onActivated: index => Vrr.setPolicy(root.selectedOutput, root.modes[index].value)
                Accessible.name: "VRR mode"
            }
        }
        StyledText {
            objectName: "vrrActualState"
            Layout.fillWidth: true
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            color: Vrr.error || root.selected?.mismatch ? Appearance.m3colors.m3error : Appearance.m3colors.m3onSurfaceVariant
            text: Vrr.error || (!Vrr.ready ? "Reading displays…" : root.selectedOutput === "global"
                ? "Default for displays set to Follow global."
                : root.selected ? (root.selected.mismatch ? "Requested Off · GPU still enabled"
                    : "GPU VRR " + (root.selected.gpu === null ? "unknown" : root.selected.gpu ? "enabled" : "off"))
                    + " · " + root.selected.width + "×" + root.selected.height + " @ " + root.selected.hz.toFixed(0) + " Hz"
                : "Display disconnected")
        }
        StyledText {
            Layout.fillWidth: true
            font.pixelSize: 10
            color: Appearance.m3colors.m3onSurfaceVariant
            text: "Changes save immediately. Refresh rate stays unchanged."
        }
        Item { Layout.fillHeight: true }
    }
}
