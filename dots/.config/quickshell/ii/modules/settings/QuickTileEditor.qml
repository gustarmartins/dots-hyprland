import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    required property var tiles
    signal edited(var value)
    property bool expanded: false
    // Matches AndroidQuickPanel.availableToggleTypes; checked by the catalog audit.
    readonly property var available: ["network", "bluetooth", "idleInhibitor", "easyEffects", "nightLight", "darkMode", "cloudflareWarp", "gameMode", "tearing", "vrr", "lsfg", "directScanout", "tripleBuffer", "screenSnip", "colorPicker", "onScreenKeyboard", "mic", "audio", "notifications", "powerProfile", "musicRecognition", "antiFlashbang", "memoryMode", "buildCache", "zramRecompress", "zramWriteback", "dropCaches", "memoryCompact", "gpuMemory"]
    function label(type) { return type.replace(/([a-z])([A-Z])/g, "$1 $2").replace(/^./, c => c.toUpperCase()); }
    function change(index, action) {
        let next = Array.from(tiles).map(t => Object.assign({}, t));
        if (action === "remove") next.splice(index, 1);
        else if (action === "size") next[index].size = next[index].size === 2 ? 1 : 2;
        else { let target = index + action; if (target < 0 || target >= next.length) return; [next[index], next[target]] = [next[target], next[index]]; }
        root.edited(next);
    }
    SettingsButton {
        objectName: "quickTileExpand"
        text: root.expanded ? "Hide tile editor" : "Edit " + root.tiles.length + " tiles"
        onClicked: root.expanded = !root.expanded
    }
    Repeater {
        model: root.expanded ? root.tiles : []
        delegate: RowLayout {
            required property var modelData
            required property int index
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: root.label(modelData.type); wrapMode: Text.WordWrap; font.pixelSize: 13 }
            SettingsButton { text: modelData.size === 2 ? "Wide" : "Icon"; onClicked: root.change(index, "size"); Accessible.name: "Change size of " + root.label(modelData.type) }
            ToolButton { text: "↑"; enabled: index > 0; onClicked: root.change(index, -1); Accessible.name: "Move tile up" }
            ToolButton { text: "↓"; enabled: index < root.tiles.length - 1; onClicked: root.change(index, 1); Accessible.name: "Move tile down" }
            ToolButton { text: "×"; onClicked: root.change(index, "remove"); Accessible.name: "Remove " + root.label(modelData.type) }
        }
    }
    RowLayout {
        visible: root.expanded
        Layout.fillWidth: true
        SettingsComboBox { id: picker; Layout.fillWidth: true; model: root.available.map(t => ({label:root.label(t), value:t})); textRole: "label"; Accessible.name: "Tile to add" }
        SettingsButton { objectName: "quickTileAdd"; text: "Add tile"; onClicked: root.edited(Array.from(root.tiles).concat([{type:root.available[picker.currentIndex],size:2}])) }
    }
}
