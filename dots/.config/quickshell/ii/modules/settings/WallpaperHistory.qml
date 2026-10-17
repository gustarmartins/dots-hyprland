import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ColumnLayout {
    id: root
    spacing: 10
    readonly property var entries: (WallpaperDiscovery.library.entries || []).filter(entry =>
        (!keptOnly.checked || entry.favorite) && (!readyOnly.checked || entry.queued) && (!search.text.trim() ||
        [entry.label, entry.theme, entry.provider, entry.id].join(" ").toLowerCase().includes(search.text.trim().toLowerCase())))
    function amount(bytes) { return (bytes / 1048576).toFixed(bytes < 104857600 ? 1 : 0) + " MiB"; }
    function imageUrl(path) { return "file://" + encodeURIComponent(path).replace(/%2F/g, "/"); }
    RowLayout {
        Layout.fillWidth: true
        StyledText { Layout.fillWidth: true; text: "Saved wallpapers"; font.pixelSize: 18; font.weight: Font.Medium }
        SettingsButton { objectName: "wallpaperHistoryRefresh"; text: "Refresh"; enabled: !WallpaperDiscovery.busy; onClicked: WallpaperDiscovery.refreshLibrary() }
        SettingsButton { text: "Open folder"; onClicked: Qt.openUrlExternally(root.imageUrl(WallpaperDiscovery.library.directory || FileUtils.trimFileProtocol(Directories.pictures) + "/Wallpapers/Discovery")) }
    }
    StyledText {
        objectName: "wallpaperHistoryUsage"
        Layout.fillWidth: true
        text: (WallpaperDiscovery.library.count || 0) + " saved · " + root.amount(WallpaperDiscovery.library.totalBytes || 0)
            + " of " + Config.options.background.discovery.storageLimitMiB + " MiB · " + (WallpaperDiscovery.library.queuedCount || 0) + " ready · " + (WallpaperDiscovery.library.keptCount || 0) + " kept"
        font.pixelSize: 12
        wrapMode: Text.WordWrap
        color: Appearance.m3colors.m3onSurfaceVariant
    }
    ProgressBar {
        id: storageProgress
        Layout.fillWidth: true
        value: Math.min(1, (WallpaperDiscovery.library.totalBytes || 0) / (Config.options.background.discovery.storageLimitMiB * 1048576))
        implicitHeight: 5
        background: Rectangle { radius: 3; color: Appearance.m3colors.m3surfaceContainerHighest }
        contentItem: Rectangle { width: storageProgress.availableWidth * storageProgress.visualPosition; radius: 3; color: Appearance.m3colors.m3primary }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        SettingsField { id: search; objectName: "wallpaperHistorySearch"; Layout.fillWidth: true; placeholderText: "Search saved wallpapers"; onTextChanged: Qt.callLater(() => history.positionViewAtBeginning()) }
        StyledText { text: "Ready"; font.pixelSize: 12 }
        SettingsSwitch { id: readyOnly; objectName: "wallpaperHistoryReadyOnly"; onCheckedChanged: Qt.callLater(() => history.positionViewAtBeginning()) }
        StyledText { text: "Kept only"; font.pixelSize: 12 }
        SettingsSwitch { id: keptOnly; objectName: "wallpaperHistoryKeptOnly"; onCheckedChanged: Qt.callLater(() => history.positionViewAtBeginning()) }
    }
    GridView {
        id: history
        objectName: "wallpaperHistoryGrid"
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(460, Math.max(180, Math.ceil(count / columns) * cellHeight))
        readonly property int columns: Math.max(1, Math.floor(width / 190))
        cellWidth: width / columns
        cellHeight: cellWidth * 9 / 16 + 78
        model: ScriptModel { values: root.entries; objectProp: "id" }
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: StyledScrollBar {}
        delegate: Rectangle {
            id: card
            required property var modelData
            width: history.cellWidth - 8
            height: history.cellHeight - 8
            radius: 12
            color: Appearance.m3colors.m3surfaceContainerHigh
            border.width: modelData.current ? 2 : 1
            border.color: modelData.current ? Appearance.m3colors.m3primary : Appearance.m3colors.m3outlineVariant
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 5
                Image {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    source: root.imageUrl(card.modelData.thumbnail || card.modelData.path)
                    sourceSize.width: 360
                    sourceSize.height: 220
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    clip: true
                    Accessible.name: card.modelData.label + " wallpaper preview"
                }
                StyledText {
                    Layout.fillWidth: true
                    text: card.modelData.label || card.modelData.theme
                    font.pixelSize: 11
                    color: Appearance.m3colors.m3onSurfaceVariant
                    elide: Text.ElideRight
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 5
                    SettingsButton {
                        objectName: "wallpaperRestore-" + card.modelData.id
                        Layout.fillWidth: true
                        implicitHeight: 30
                        padding: 5
                        text: card.modelData.current ? "Current" : card.modelData.queued ? "Apply" : "Restore"
                        enabled: !WallpaperDiscovery.busy && !card.modelData.current
                        onClicked: WallpaperDiscovery.restore(card.modelData.id)
                        Accessible.name: "Restore " + card.modelData.label
                    }
                    SettingsButton {
                        objectName: "wallpaperKeep-" + card.modelData.id
                        implicitHeight: 30
                        padding: 5
                        text: card.modelData.favorite ? "★ Kept" : "☆ Keep"
                        enabled: !WallpaperDiscovery.busy
                        onClicked: WallpaperDiscovery.keep(card.modelData.id, !card.modelData.favorite)
                        Accessible.name: card.modelData.favorite ? "Unkeep wallpaper" : "Keep wallpaper from automatic cleanup"
                    }
                }
            }
        }
        StyledText {
            anchors.centerIn: parent
            visible: history.count === 0
            text: WallpaperDiscovery.libraryBusy ? "Loading saved wallpapers…" : search.text || keptOnly.checked || readyOnly.checked ? "No saved wallpapers match." : "Discovered wallpapers will appear here automatically."
            width: parent.width - 24
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.pixelSize: 13
            color: Appearance.m3colors.m3onSurfaceVariant
        }
    }
    StyledText {
        Layout.fillWidth: true
        text: WallpaperDiscovery.libraryError || (WallpaperDiscovery.library.overBudget || WallpaperDiscovery.library.lowSpace
            ? "Storage is full. Current and kept wallpapers stay protected. Increase the limit or unkeep an older image to make room."
            : "Restore any saved image. Keep protects favorites from automatic cleanup. Storage limits are below.")
        font.pixelSize: 12
        wrapMode: Text.WordWrap
        color: WallpaperDiscovery.libraryError ? Appearance.m3colors.m3error : Appearance.m3colors.m3onSurfaceVariant
    }
}
