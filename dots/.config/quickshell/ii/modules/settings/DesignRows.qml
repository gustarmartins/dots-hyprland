import QtQuick
import QtQuick.Layouts
import qs.modules.common
import "SettingsCatalog.js" as Catalog

ColumnLayout {
    id: root
    property var paths: []
    property var groups: []
    signal edited(string path)
    Layout.fillWidth: true
    spacing: 8
    Repeater {
        model: Catalog.entries.filter(e => root.paths.includes(e.path) || (e.page === "design" && root.groups.includes(e.section)))
        delegate: SettingRow {
            required property var modelData
            Layout.fillWidth: true
            setting: modelData
            writable: !Config.writesPaused
            onEdited: path => root.edited(path)
        }
    }
}
