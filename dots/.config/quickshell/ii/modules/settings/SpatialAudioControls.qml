import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    spacing: 10
    Component.onCompleted: SpatialAudio.refresh()

    readonly property string activeProfile: SpatialAudio.profile ?? "atmos-7.1"
    readonly property var profileList: (SpatialAudio.profiles && SpatialAudio.profiles.length)
        ? SpatialAudio.profiles
        : [
            { id: "atmos-7.1", label: "Dolby Atmos 7.1 HRIR", available: true },
            { id: "sofa-kemar", label: "PipeWire SOFA 3D (KEMAR)", available: true }
        ]
    readonly property bool passthroughOn: SpatialAudio.passthrough ?? false
    readonly property string hdmiSummaryText: SpatialAudio.hdmiSummary ?? ""

    RowLayout {
        Layout.fillWidth: true
        StyledText { Layout.fillWidth: true; text: "Spatial audio & Dolby for mpv"; font.pixelSize: 20; font.weight: Font.Medium }
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
        spacing: 8
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
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            StyledText { text: "Binaural engine:"; color: Appearance.m3colors.m3onSurfaceVariant }
            Repeater {
                model: root.profileList
                delegate: SettingsButton {
                    required property var modelData
                    objectName: "mpvSpatialProfile-" + modelData.id
                    text: (root.activeProfile === modelData.id ? "✓ " : "") + modelData.label
                    enabled: !SpatialAudio.busy && modelData.available !== false
                    onClicked: {
                        if (typeof SpatialAudio.setProfile === "function")
                            SpatialAudio.setProfile(modelData.id);
                    }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                text: "True Dolby HDMI bitstream passthrough (when Dolby AVR is active)"
                wrapMode: Text.WordWrap
            }
            SettingsSwitch {
                objectName: "mpvSpatialPassthrough"
                checked: root.passthroughOn
                enabled: !SpatialAudio.busy
                Accessible.name: "True Dolby HDMI bitstream passthrough"
                onToggled: {
                    if (typeof SpatialAudio.setPassthrough === "function")
                        SpatialAudio.setPassthrough(checked);
                }
            }
        }
        StyledText {
            visible: root.hdmiSummaryText.length > 0
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: root.hdmiSummaryText
            color: Appearance.m3colors.m3onSurfaceVariant
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "Headphone surround for multichannel music and films in mpv (Dolby Atmos 7.1 HRIR convolution or PipeWire native libmysofa SOFA 3D). Press F8 to toggle for that player. When a Dolby HDMI receiver is selected and passthrough is on, raw E-AC-3/TrueHD bitstreams bypass binaural processing. Stereo tracks always stay untouched."
            color: Appearance.m3colors.m3onSurfaceVariant
        }
        SettingsButton { text: "Refresh spatial audio status"; enabled: !SpatialAudio.busy; onClicked: SpatialAudio.refresh() }
    }
    StyledText { Layout.fillWidth: true; text: SpatialAudio.error; visible: text.length > 0; wrapMode: Text.WordWrap; color: Appearance.m3colors.m3error }
}
