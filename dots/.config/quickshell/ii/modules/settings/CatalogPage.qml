import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "SettingsCatalog.js" as Catalog

ScrollView {
    id: root
    property string pageId: "control"
    property string query: ""
    property bool writable: true
    signal edited(string path)
    signal navigate(string page)
    readonly property var groups: Catalog.sections(query.trim() ? "" : pageId, query)
    onPageIdChanged: Qt.callLater(() => { if (contentItem) contentItem.contentY = 0; })
    onQueryChanged: Qt.callLater(() => { if (contentItem) contentItem.contentY = 0; })
    contentWidth: availableWidth
    clip: true
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
    ColumnLayout {
        width: root.availableWidth
        spacing: 22
        Loader {
            id: extra
            visible: active
            Layout.fillWidth: true
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            active: !root.query.trim() && ["fonts", "wallpaper", "audio"].includes(root.pageId)
            sourceComponent: root.pageId === "fonts" ? fontPage : root.pageId === "audio" ? audioPage : wallpaperPage
        }
        Repeater {
            model: root.query.trim() ? Catalog.destinations.filter(e => Catalog.matches(e, root.query)) : []
            delegate: SettingsButton {
                required property var modelData
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                text: "Open " + modelData.title + " →"
                onClicked: root.navigate(modelData.page)
            }
        }
        Repeater {
            model: root.groups
            delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                spacing: 8
                StyledText {
                    Layout.fillWidth: true
                    text: (root.query.trim() ? Catalog.page(modelData.page).title + " / " : "") + modelData.title
                    font.pixelSize: 18
                    font.weight: Font.Medium
                    wrapMode: Text.WordWrap
                }
                Repeater {
                    model: modelData.entries
                    delegate: SettingRow {
                        required property var modelData
                        Layout.fillWidth: true
                        setting: modelData
                        writable: root.writable && !Config.writesPaused
                        onEdited: path => { root.edited(path); if (setting.apply === "colors") colorTimer.restart(); }
                    }
                }
            }
        }
        StyledText { Layout.fillWidth: true; Layout.margins: 24; visible: root.groups.length === 0; text: "No settings match your search. Try a feature, application, or setting name."; wrapMode: Text.WordWrap }
        Item { Layout.preferredHeight: 24 }
    }
    Timer { id: colorTimer; interval: 500; onTriggered: { Config.flushPendingWrites(); Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch"]); } }
    Component { id: audioPage; AudioActions {} }
    Component { id: fontPage; FontProfiles {} }
    Component { id: wallpaperPage; WallpaperActions {} }
}
