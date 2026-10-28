import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    spacing: 10
    Component.onCompleted: { EasyEffects.fetchActiveState(); MusicEq.refresh(); }
    StyledText { text: "EasyEffects"; font.pixelSize: 22; font.weight: Font.Medium }
    StyledText { Layout.fillWidth: true; text: !EasyEffects.available ? "EasyEffects is not available on this machine." : EasyEffects.busy ? "Updating audio effects…" : "Current preset: " + (EasyEffects.preset || "None"); font.pixelSize: 13; wrapMode: Text.WordWrap; color: Appearance.m3colors.m3onSurfaceVariant }
    RowLayout {
        Layout.fillWidth: true
        SettingsComboBox { id: presets; Layout.fillWidth: true; model: EasyEffects.presets; currentIndex: EasyEffects.presets.indexOf(EasyEffects.preset); enabled: EasyEffects.available && !EasyEffects.busy; Accessible.name: "Audio preset" }
        SettingsButton { text: "Apply preset"; enabled: EasyEffects.available && !EasyEffects.busy && presets.currentIndex >= 0; onClicked: EasyEffects.selectPreset(presets.currentText) }
        SettingsButton { text: "Open EasyEffects"; enabled: EasyEffects.available; onClicked: EasyEffects.show() }
    }
    StyledText { Layout.fillWidth: true; text: EasyEffects.error; visible: text.length > 0; wrapMode: Text.WordWrap; color: Appearance.m3colors.m3error; font.pixelSize: 12 }
    SpatialAudioControls { Layout.fillWidth: true }
    StyledText { text: "Automatic music EQ"; font.pixelSize: 20; font.weight: Font.Medium }
    SettingsButton {
        text: MusicEq.enabled ? "Automatic music EQ: On — disable" : "Automatic music EQ: Off — enable"
        enabled: !MusicEq.busy
        onClicked: MusicEq.setEnabled(!MusicEq.enabled)
    }
    ColumnLayout {
        visible: MusicEq.enabled
        Layout.fillWidth: true
        StyledText { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: MusicEq.active ? MusicEq.message : "Service stopped — enable again to resume" }
        Repeater {
            model: [{key:"spotify", label:"Spotify"}, {key:"jukebox", label:"Jukebox"}, {key:"artists", label:"Artist fallbacks"}, {key:"genres", label:"Genre fallbacks"}]
            delegate: SettingsButton {
                required property var modelData
                text: modelData.label + (MusicEq.config[modelData.key] ? ": On" : ": Off")
                enabled: !MusicEq.busy
                onClicked: MusicEq.setFeature(modelData.key, !MusicEq.config[modelData.key])
            }
        }
        SettingsButton { text: "Refresh music EQ status"; onClicked: MusicEq.refresh() }
        StyledText { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Song rules take priority. Artist and genre fallbacks are approximate. Unknown songs use your baseline. Manual preset changes last until the next song. Disabling stops the watcher and restores the prior preset if still owned." }
    }
    StyledText { Layout.fillWidth: true; text: MusicEq.error; visible: text.length > 0; wrapMode: Text.WordWrap; color: Appearance.m3colors.m3error }
    StyledText { text: "Eden audio boost"; font.pixelSize: 20; font.weight: Font.Medium }
    SettingsButton {
        text: EdenAudioBoost.enabled ? "Eden boost widget: On — disable and reset" : "Eden boost widget: Off — enable"
        enabled: !EdenAudioBoost.busy
        onClicked: EdenAudioBoost.setEnabled(!EdenAudioBoost.enabled)
    }
    ColumnLayout {
        visible: EdenAudioBoost.enabled
        Layout.fillWidth: true
        StyledText { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Double-click the control-center widget for +12 dB on Eden only. Single-click resets it. Your current EasyEffects preset stays selected. The boost ends when Eden audio stops." }
        SettingsButton { text: "Reset Eden boost"; enabled: !EdenAudioBoost.busy; onClicked: EdenAudioBoost.reset() }
        StyledText { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: EdenAudioBoost.error; visible: text.length > 0 }
    }
}
