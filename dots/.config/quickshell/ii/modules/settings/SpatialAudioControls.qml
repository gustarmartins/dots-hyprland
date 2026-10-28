import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    spacing: 10
    Component.onCompleted: SpatialAudio.refresh()
    RowLayout {
        Layout.fillWidth: true
        StyledText { Layout.fillWidth: true; text: "Spatial audio for mpv"; font.pixelSize: 20; font.weight: Font.Medium }
        SettingsSwitch {
            objectName: "mpvSpatialMaster"
            checked: SpatialAudio.enabled
            enabled: !SpatialAudio.busy
            Accessible.name: "Spatial audio for mpv"
            onToggled: SpatialAudio.setEnabled(checked)
        }
    }
    StyledText { Layout.fillWidth: true; text: SpatialAudio.message; wrapMode: Text.WordWrap; color: Appearance.m3colors.m3onSurfaceVariant }
    ColumnLayout {
        objectName: "mpvSpatialFeatures"
        visible: SpatialAudio.enabled
        Layout.fillWidth: true
        RowLayout {
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: "Automatic for multichannel tracks"; wrapMode: Text.WordWrap }
            SettingsSwitch {
                objectName: "mpvSpatialAutomatic"
                checked: SpatialAudio.automatic
                enabled: !SpatialAudio.busy
                Accessible.name: "Automatic spatial audio for multichannel tracks"
                onToggled: SpatialAudio.setAutomatic(checked)
            }
        }
        StyledText { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Headphone surround for multichannel music and films in mpv. Press F8 to turn it on or off for that player. Stereo tracks keep their normal output." }
        SettingsButton { text: "Refresh spatial audio status"; enabled: !SpatialAudio.busy; onClicked: SpatialAudio.refresh() }
    }
    StyledText { Layout.fillWidth: true; text: SpatialAudio.error; visible: text.length > 0; wrapMode: Text.WordWrap; color: Appearance.m3colors.m3error }
}
