import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    spacing: 10
    Component.onCompleted: EasyEffects.fetchActiveState()
    StyledText { text: "EasyEffects"; font.pixelSize: 22; font.weight: Font.Medium }
    StyledText { Layout.fillWidth: true; text: !EasyEffects.available ? "EasyEffects is not available on this machine." : EasyEffects.busy ? "Updating audio effects…" : "Current preset: " + (EasyEffects.preset || "None"); font.pixelSize: 13; wrapMode: Text.WordWrap; color: Appearance.m3colors.m3onSurfaceVariant }
    RowLayout {
        Layout.fillWidth: true
        SettingsComboBox { id: presets; Layout.fillWidth: true; model: EasyEffects.presets; currentIndex: EasyEffects.presets.indexOf(EasyEffects.preset); enabled: EasyEffects.available && !EasyEffects.busy; Accessible.name: "Audio preset" }
        SettingsButton { text: "Apply preset"; enabled: EasyEffects.available && !EasyEffects.busy && presets.currentIndex >= 0; onClicked: EasyEffects.selectPreset(presets.currentText) }
        SettingsButton { text: "Open EasyEffects"; enabled: EasyEffects.available; onClicked: EasyEffects.show() }
    }
    StyledText { Layout.fillWidth: true; text: EasyEffects.error; visible: text.length > 0; wrapMode: Text.WordWrap; color: Appearance.m3colors.m3error; font.pixelSize: 12 }
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
