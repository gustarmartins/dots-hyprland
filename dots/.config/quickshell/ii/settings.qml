//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings
import "modules/settings/SettingsCatalog.js" as Catalog

ApplicationWindow {
    id: root
    property string currentPage: "home"
    property string query: ""
    property string feedback: "Changes save when you use a control. Text lists have a Save button."
    readonly property bool searching: query.trim().length > 0
    readonly property var page: Catalog.page(currentPage)
    readonly property bool wide: width >= 1000
    property bool effectsVisited: false
    property bool aboutVisited: false
    visible: true
    title: "illogical-impulse Settings"
    width: 1180
    height: 800
    minimumWidth: 680
    minimumHeight: 480
    font.family: Appearance.font.family.main
    font.pixelSize: 13
    palette {
        window: Appearance.m3colors.m3background
        windowText: Appearance.m3colors.m3onSurface
        base: Appearance.m3colors.m3surfaceContainerHigh
        alternateBase: Appearance.m3colors.m3surfaceContainerLow
        text: Appearance.m3colors.m3onSurface
        button: Appearance.m3colors.m3surfaceContainerHigh
        buttonText: Appearance.m3colors.m3onSurface
        highlight: Appearance.m3colors.m3primary
        highlightedText: Appearance.m3colors.m3onPrimary
        mid: Appearance.m3colors.m3outlineVariant
    }
    color: Appearance.m3colors.m3background
    onClosing: event => { if (Config.writesPaused) event.accepted = false; else Qt.quit(); }
    Component.onCompleted: MaterialThemeLoader.reapplyTheme()

    function navigate(id) {
        if (Config.writesPaused) return;
        if (id === "effects") effectsVisited = true;
        if (id === "about") aboutVisited = true;
        currentPage = id;
        query = ""; searchField.text = "";
    }
    Shortcut { sequence: "Ctrl+F"; enabled: !Config.writesPaused; onActivated: { searchField.forceActiveFocus(); searchField.selectAll(); } }
    Shortcut { sequence: "Ctrl+PageDown"; enabled: !Config.writesPaused; onActivated: root.navigate(Catalog.pages[(Catalog.pages.findIndex(p => p.id === root.currentPage) + 1) % Catalog.pages.length].id) }
    Shortcut { sequence: "Ctrl+PageUp"; enabled: !Config.writesPaused; onActivated: root.navigate(Catalog.pages[(Catalog.pages.findIndex(p => p.id === root.currentPage) + Catalog.pages.length - 1) % Catalog.pages.length].id) }
    ColumnLayout {
        anchors { fill: parent; margins: 16 }
        spacing: 16
        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            MaterialSymbol { text: "tune"; iconSize: 26; color: Appearance.m3colors.m3primary }
            StyledText { text: "Desktop settings"; font.pixelSize: 21; font.weight: Font.Medium }
            Item { Layout.fillWidth: true }
            SettingsField {
                id: searchField
                objectName: "settingsSearch"
                Layout.preferredWidth: Math.min(380, root.width * 0.37)
                placeholderText: "Search settings…  Ctrl+F"
                Accessible.name: "Search all settings"
                selectByMouse: true
                enabled: !Config.writesPaused
                onTextEdited: root.query = text
                Keys.onEscapePressed: { text = ""; root.query = ""; }
            }
            ToolButton { text: "×"; Accessible.name: "Close settings"; enabled: !Config.writesPaused; onClicked: root.close() }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 18
            ColumnLayout {
                Layout.preferredWidth: root.wide ? 206 : 56
                Layout.fillHeight: true
                spacing: 12
                ListView {
                    id: navigation
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: Catalog.pages
                    spacing: 4
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    delegate: Button {
                        required property var modelData
                        width: navigation.width
                        height: 43
                        padding: 10
                        enabled: !Config.writesPaused
                        highlighted: !root.searching && root.currentPage === modelData.id
                        Accessible.name: modelData.title
                        ToolTip.visible: hovered && !root.wide
                        ToolTip.text: modelData.title
                        onClicked: root.navigate(modelData.id)
                        background: Rectangle { radius: 14; color: parent.highlighted ? Appearance.m3colors.m3secondaryContainer : parent.hovered ? Appearance.m3colors.m3surfaceContainerHigh : "transparent" }
                        contentItem: RowLayout {
                            spacing: 10
                            MaterialSymbol { text: modelData.icon; iconSize: 22; color: Appearance.m3colors.m3onSurface }
                            StyledText { visible: root.wide; Layout.fillWidth: true; text: modelData.title; font.pixelSize: 13; elide: Text.ElideRight }
                        }
                    }
                }
                SettingsButton {
                    Layout.fillWidth: true
                    text: root.wide ? "Open config file" : "{ }"
                    Accessible.name: "Open configuration file"
                    enabled: !Config.writesPaused
                    onClicked: Qt.openUrlExternally(Directories.shellConfigPath)
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    StyledText { Layout.fillWidth: true; text: root.searching ? "Search results" : root.page.title; font.pixelSize: 27; font.weight: Font.Medium; wrapMode: Text.WordWrap }
                    StyledText { Layout.fillWidth: true; text: root.searching ? "Matches across the whole desktop. Changes use the same controls as their own pages." : root.page.description; font.pixelSize: 13; wrapMode: Text.WordWrap; color: Appearance.m3colors.m3onSurfaceVariant }
                }
                StackLayout {
                    id: stack
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: !Config.ready ? 4 : root.searching ? 2 : root.currentPage === "home" ? 0 : root.currentPage === "effects" ? 1 : root.currentPage === "about" ? 3 : 2
                    SettingsHome { onNavigate: id => root.navigate(id) }
                    Loader { id: effects; active: root.effectsVisited; source: "modules/settings/DesktopEffectsConfig.qml" }
                    CatalogPage {
                        id: catalogPage
                        pageId: root.currentPage
                        query: root.query
                        writable: !Config.writesPaused
                        onNavigate: id => root.navigate(id)
                        onEdited: path => { root.feedback = "Updated · " + (Catalog.entries.find(e => e.path === path)?.title ?? "Setting"); }
                    }
                    Loader { id: about; active: root.aboutVisited; source: "modules/settings/About.qml" }
                    BusyIndicator { running: !Config.ready }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Config.writeError ? Config.writeError : Config.writesPaused ? "Applying desktop fonts…" : root.currentPage === "effects" && !root.searching ? "Desktop effects keep their own Apply and Save controls." : root.feedback
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
                    color: Appearance.m3colors.m3onSurfaceVariant
                }
            }
        }
    }
    IpcHandler {
        target: "settings"
        function open(page: string): void { if (Catalog.pages.some(p => p.id === page)) root.navigate(page); }
        function search(text: string): void { if (!Config.writesPaused) { searchField.text = text; root.query = text; } }
        function status(): string { return JSON.stringify({page:root.currentPage,search:root.query,ready:Config.ready,loading:Config.writesPaused,pages:Catalog.pages.map(p=>p.id),settings:Catalog.entries.length}); }
    }
}
