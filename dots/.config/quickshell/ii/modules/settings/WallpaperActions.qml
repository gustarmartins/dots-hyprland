import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    property bool libraryOpen: false
    spacing: 12
    StyledText { text: root.libraryOpen ? "Saved wallpapers" : "Wallpaper actions"; font.pixelSize: 22; font.weight: Font.Medium }
    StyledText { Layout.fillWidth: true; text: "Choose or fetch an image. Prefetch prepares offline choices without changing your colors."; wrapMode: Text.WordWrap; font.pixelSize: 13; color: Appearance.m3colors.m3onSurfaceVariant }
    Flow {
        Layout.fillWidth: true
        spacing: 8
        SettingsButton { text: "Choose wallpaper"; onClicked: Quickshell.execDetached([Directories.wallpaperSwitchScriptPath]) }
        SettingsButton { objectName: "wallpaperPrefetch"; text: WallpaperDiscovery.busy ? "Working…" : "Prefetch " + Config.options.background.discovery.prefetchCount; enabled: !WallpaperDiscovery.busy; onClicked: WallpaperDiscovery.prefetch() }
        SettingsButton { text: WallpaperDiscovery.busy ? "Discovering…" : "Discover wallpaper"; enabled: !WallpaperDiscovery.busy; onClicked: WallpaperDiscovery.fetch() }
        SettingsButton { text: "Wallpaper source"; visible: !!WallpaperDiscovery.current.url; onClicked: Qt.openUrlExternally(WallpaperDiscovery.current.url) }
    }
    StyledText { Layout.fillWidth: true; text: WallpaperDiscovery.status || "Every discovered and rotation wallpaper is saved below."; wrapMode: Text.WordWrap; font.pixelSize: 12; color: Appearance.m3colors.m3onSurfaceVariant }
    SettingsButton {
        objectName: "wallpaperLibraryToggle"
        Layout.fillWidth: true
        text: root.libraryOpen ? "←  Back to wallpaper controls" : "Open saved wallpapers & previews  →"
        onClicked: root.libraryOpen = !root.libraryOpen
    }
    Loader { Layout.fillWidth: true; active: root.libraryOpen; sourceComponent: Component { WallpaperHistory { } } }
}
