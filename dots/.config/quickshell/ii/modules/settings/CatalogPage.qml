import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "SettingsCatalog.js" as Catalog
import qs.modules.ii.sidebarRight.quickToggles

ScrollView {
    id: root
    property string pageId: "control"
    property string query: ""
    property bool writable: true
    property var effectsEditor: null
    signal edited(string path)
    signal navigate(string page)
    readonly property bool searching: query.trim().length > 0
    readonly property var groups: searching ? Catalog.searchGroups(query) : Catalog.sections(pageId, "")
    function showMemoryReview() {
        if (pageId === "memory" && extra.item) {
            extra.item.showReview();
            contentItem.contentY = 0;
        }
    }
    onPageIdChanged: Qt.callLater(() => { if (contentItem) contentItem.contentY = 0; })
    onQueryChanged: Qt.callLater(() => { if (contentItem) contentItem.contentY = 0; })
    contentWidth: availableWidth
    clip: true
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
    ColumnLayout {
        width: root.availableWidth
        spacing: 22
        Loader {
            active: !root.query.trim() && root.pageId === "launcher"
            visible: active
            Layout.fillWidth: true
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            sourceComponent: EmergencyTerminalSettings { writable: root.writable && !Config.writesPaused }
        }
        Loader {
            id: extra
            visible: active
            Layout.fillWidth: true
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            active: !root.query.trim() && ["control", "agents", "fonts", "wallpaper", "audio", "mail", "memory", "company", "cryod", "storage"].includes(root.pageId)
            sourceComponent: root.pageId === "control" ? vrrPage : root.pageId === "agents" ? agentPage : root.pageId === "storage" ? storagePage : root.pageId === "cryod" ? cryodPage : root.pageId === "company" ? companyPage : root.pageId === "memory" ? memoryPage : root.pageId === "mail" ? mailPage : root.pageId === "fonts" ? fontPage : root.pageId === "audio" ? audioPage : wallpaperPage
        }
        Repeater {
            model: extra.item?.libraryOpen ? [] : root.groups
            delegate: ColumnLayout {
                required property var modelData
                objectName: root.searching ? "searchGroup:" + modelData.page : ""
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                spacing: 8
                StyledText {
                    Layout.fillWidth: true
                    text: modelData.title
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
                Repeater {
                    model: modelData.timings || []
                    delegate: TimingSettingRow {
                        required property var modelData
                        Layout.fillWidth: true
                        setting: modelData
                        effectsEditor: root.effectsEditor
                        writable: root.writable && !Config.writesPaused
                    }
                }
                Repeater {
                    model: modelData.links || []
                    delegate: SettingRow {
                        required property var modelData
                        Layout.fillWidth: true
                        setting: ({kind:"destination", path:"destination." + modelData.title, title:modelData.title, page:modelData.page})
                        onNavigate: page => root.navigate(page)
                    }
                }
            }
        }
        StyledText { Layout.fillWidth: true; Layout.margins: 24; visible: root.groups.length === 0 && !extra.active; text: "No settings match your search. Try a feature, application, or setting name."; wrapMode: Text.WordWrap }
        Item { Layout.preferredHeight: 24 }
    }
    Timer { id: colorTimer; interval: 500; onTriggered: { Config.flushPendingWrites(); Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch"]); } }
    Component { id: agentPage; AgentSessions {} }
    Component { id: vrrPage; VrrPanel { implicitHeight: 226 } }
    Component { id: storagePage; StorageActions {} }
    Component { id: cryodPage; CryoDSettings {} }
    Component { id: companyPage; CompanyTools {} }
    Component { id: memoryPage; MemoryLocks {} }
    Component { id: mailPage; MailSettings {} }
    Component { id: audioPage; AudioActions {} }
    Component { id: fontPage; FontProfiles {} }
    Component { id: wallpaperPage; WallpaperActions {} }
}
