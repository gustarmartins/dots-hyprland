import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    spacing: 12
    StyledText { text: "A fresh backdrop"; font.pixelSize: 22; font.weight: Font.Medium }
    StyledText { Layout.fillWidth: true; text: "Choose a local image or discover wide, SFW wallpapers. Your discovery mood and rotation schedule are below."; wrapMode: Text.WordWrap; font.pixelSize: 13; color: Appearance.m3colors.m3onSurfaceVariant }
    Flow {
        Layout.fillWidth: true
        spacing: 8
        SettingsButton { text: "Choose wallpaper"; onClicked: Quickshell.execDetached([Directories.wallpaperSwitchScriptPath]) }
        SettingsButton { text: WallpaperDiscovery.busy ? "Discovering…" : "Discover wallpaper"; enabled: !WallpaperDiscovery.busy; onClicked: WallpaperDiscovery.fetch() }
        SettingsButton { text: "Light palette"; onClicked: Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "light", "--noswitch"]) }
        SettingsButton { text: "Dark palette"; onClicked: Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "dark", "--noswitch"]) }
        SettingsButton { text: "Wallpaper source"; visible: !!WallpaperDiscovery.current.url; onClicked: Qt.openUrlExternally(WallpaperDiscovery.current.url) }
    }
    StyledText { Layout.fillWidth: true; text: WallpaperDiscovery.status || "Downloads stay in your wallpaper folder."; wrapMode: Text.WordWrap; font.pixelSize: 12; color: Appearance.m3colors.m3onSurfaceVariant }
}
