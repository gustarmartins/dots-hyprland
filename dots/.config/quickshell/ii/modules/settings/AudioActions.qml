import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    spacing: 10
    StyledText { text: "EasyEffects"; font.pixelSize: 22; font.weight: Font.Medium }
    StyledText { Layout.fillWidth: true; text: !EasyEffects.available ? "EasyEffects is not available on this machine." : EasyEffects.busy ? "Updating audio effects…" : "Current preset: " + (EasyEffects.preset || "None"); font.pixelSize: 13; wrapMode: Text.WordWrap; color: Appearance.m3colors.m3onSurfaceVariant }
    RowLayout {
        Layout.fillWidth: true
        SettingsComboBox { id: presets; Layout.fillWidth: true; model: EasyEffects.presets; currentIndex: EasyEffects.presets.indexOf(EasyEffects.preset); enabled: EasyEffects.available && !EasyEffects.busy; Accessible.name: "Audio preset" }
        SettingsButton { text: "Apply preset"; enabled: EasyEffects.available && !EasyEffects.busy && presets.currentIndex >= 0; onClicked: EasyEffects.selectPreset(presets.currentText) }
        SettingsButton { text: "Open EasyEffects"; enabled: EasyEffects.available; onClicked: EasyEffects.show() }
    }
    StyledText { Layout.fillWidth: true; text: EasyEffects.error; visible: text.length > 0; wrapMode: Text.WordWrap; color: Appearance.m3colors.m3error; font.pixelSize: 12 }
}
