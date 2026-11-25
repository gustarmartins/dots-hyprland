import QtQuick
import QtQuick.Layouts
import qs.modules.common
import "SettingsCatalog.js" as Catalog

ColumnLayout {
    id: root
    property var paths: []
    property var groups: []
    property bool flatRows: true
    signal edited(string path)
    readonly property var items: {
        if (root.paths.length > 0) {
            return root.paths
                .map(path => Catalog.entries.find(e => e.path === path))
                .filter(e => !!e);
        }
        return Catalog.entries.filter(e => e.page === "design" && root.groups.includes(e.section));
    }
    Layout.fillWidth: true
    spacing: flatRows ? 2 : 2
    Repeater {
        model: root.items
        delegate: SettingRow {
            required property var modelData
            required property int index
            Layout.fillWidth: true
            setting: modelData
            flatRow: root.flatRows
            groupPosition: root.items.length === 1 ? "single"
                : index === 0 ? "first"
                : index === root.items.length - 1 ? "last" : "middle"
            writable: !Config.writesPaused
            onEdited: path => root.edited(path)
        }
    }
}
