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
    readonly property bool isLight: Appearance.m3colors.darkmode === false
    readonly property color extraCardBg: isLight ? Appearance.m3colors.m3surfaceContainerLowest : Appearance.m3colors.m3surfaceContainerLow

    function showMemoryReview() {
        if (pageId === "memory" && extra.item) {
            extra.item.showReview();
            contentItem.contentY = 0;
        }
    }
    function segmentPos(index, total) {
        if (total <= 1) return "single";
        if (index === 0) return "first";
        if (index === total - 1) return "last";
        return "middle";
    }
    onPageIdChanged: Qt.callLater(() => { if (contentItem) contentItem.contentY = 0; })
    onQueryChanged: Qt.callLater(() => { if (contentItem) contentItem.contentY = 0; })
    contentWidth: availableWidth
    topPadding: 14
    clip: true
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

    ColumnLayout {
        width: Math.min(root.availableWidth - 40, 840)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 22

        Rectangle {
            visible: emergencyLoader.active
            Layout.fillWidth: true
            implicitHeight: emergencyLoader.implicitHeight + 28
            radius: 20
            color: root.extraCardBg
            Loader {
                id: emergencyLoader
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                active: !root.query.trim() && root.pageId === "launcher"
                sourceComponent: EmergencyTerminalSettings { writable: root.writable && !Config.writesPaused }
            }
        }

        Rectangle {
            visible: extra.active
            Layout.fillWidth: true
            implicitHeight: extra.implicitHeight + 28
            radius: 20
            color: root.extraCardBg
            Loader {
                id: extra
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                active: !root.query.trim() && ["control", "session", "capture", "agents", "fonts", "wallpaper", "audio", "mail", "memory", "company", "cryod", "storage"].includes(root.pageId)
                sourceComponent: root.pageId === "control" ? vrrPage
                    : root.pageId === "session" ? sleepPage
                    : root.pageId === "capture" ? recorderPage
                    : root.pageId === "agents" ? agentPage
                    : root.pageId === "storage" ? storagePage
                    : root.pageId === "cryod" ? cryodPage
                    : root.pageId === "company" ? companyPage
                    : root.pageId === "memory" ? memoryPage
                    : root.pageId === "mail" ? mailPage
                    : root.pageId === "fonts" ? fontPage
                    : root.pageId === "audio" ? audioPage : wallpaperPage
            }
        }

        Repeater {
            model: extra.item?.libraryOpen ? [] : root.groups
            delegate: ColumnLayout {
                id: groupCol
                required property var modelData
                readonly property int entriesCount: (modelData.entries || []).length
                readonly property int timingsCount: (modelData.timings || []).length
                readonly property int linksCount: (modelData.links || []).length
                readonly property int totalRows: entriesCount + timingsCount + linksCount

                objectName: root.searching ? "searchGroup:" + modelData.page : ""
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.bottomMargin: 6
                    text: modelData.title
                    textFormat: Text.PlainText
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Appearance.m3colors.m3primary
                    wrapMode: Text.WordWrap
                }

                Repeater {
                    model: groupCol.modelData.entries
                    delegate: SettingRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        setting: modelData
                        groupPosition: root.segmentPos(index, groupCol.totalRows)
                        writable: root.writable && !Config.writesPaused
                        onEdited: path => { root.edited(path); if (setting.apply === "colors") colorTimer.restart(); }
                    }
                }
                Repeater {
                    model: groupCol.modelData.timings || []
                    delegate: TimingSettingRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        setting: modelData
                        groupPosition: root.segmentPos(groupCol.entriesCount + index, groupCol.totalRows)
                        effectsEditor: root.effectsEditor
                        writable: root.writable && !Config.writesPaused
                    }
                }
                Repeater {
                    model: groupCol.modelData.links || []
                    delegate: SettingRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        setting: ({kind:"destination", path:"destination." + modelData.title, title:modelData.title, page:modelData.page})
                        groupPosition: root.segmentPos(groupCol.entriesCount + groupCol.timingsCount + index, groupCol.totalRows)
                        onNavigate: page => root.navigate(page)
                    }
                }
            }
        }

        Rectangle {
            visible: root.groups.length === 0 && !extra.active
            Layout.fillWidth: true
            implicitHeight: emptyLabel.implicitHeight + 48
            radius: 20
            color: root.extraCardBg
            StyledText {
                id: emptyLabel
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 24 }
                horizontalAlignment: Text.AlignHCenter
                text: "No settings match your search. Try a feature, application, or setting name."
                wrapMode: Text.WordWrap
                color: Appearance.m3colors.m3onSurfaceVariant
            }
        }

        Item { Layout.preferredHeight: 24 }
    }

    Timer { id: colorTimer; interval: 500; onTriggered: { Config.flushPendingWrites(); Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch"]); } }
    Component { id: agentPage; AgentSessions {} }
    Component { id: vrrPage; VrrPanel { implicitHeight: 186 } }
    Component { id: sleepPage; SleepPanel {} }
    Component { id: recorderPage; RecorderPanel {} }
    Component { id: storagePage; StorageActions {} }
    Component { id: cryodPage; CryoDSettings {} }
    Component { id: companyPage; CompanyTools {} }
    Component { id: memoryPage; MemoryLocks {} }
    Component { id: mailPage; MailSettings {} }
    Component { id: audioPage; AudioActions {} }
    Component { id: fontPage; FontProfiles {} }
    Component { id: wallpaperPage; WallpaperActions {} }
}
