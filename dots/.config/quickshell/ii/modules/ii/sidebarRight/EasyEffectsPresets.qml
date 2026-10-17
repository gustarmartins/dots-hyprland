import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    spacing: 5
    function label(name) {
        const labels = {"astra-music": "Music", "astra-rock": "Rock", "astra-osu": "osu!", "astra-mk8dx": "MK8DX"};
        return labels[name] ?? name.replace(/^astra-/, "");
    }
    StyledText {
        text: EasyEffects.busy ? "EasyEffects · Applying…" : "EasyEffects"
        font.pixelSize: 11
        color: Appearance.m3colors.m3onSurfaceVariant
    }
    StyledComboBox {
        id: picker
        objectName: "controlPresetPicker"
        Layout.fillWidth: true
        implicitHeight: 38
        buttonRadius: 12
        buttonIcon: "graphic_eq"
        colBackground: Appearance.m3colors.m3surfaceContainerHigh
        enabled: !EasyEffects.busy
        model: EasyEffects.presets.map(name => ({label:root.label(name), value:name}))
        textRole: "label"
        valueRole: "value"
        currentIndex: EasyEffects.presets.indexOf(EasyEffects.preset)
        displayText: currentIndex >= 0 ? root.label(EasyEffects.preset) : !EasyEffects.active ? "Off · Select a preset" : "Select a preset"
        onActivated: EasyEffects.selectPreset(currentValue)
        Accessible.name: "EasyEffects preset"
        StyledToolTip { text: EasyEffects.error || EasyEffects.preset }
    }
    StyledText {
        visible: EasyEffects.error.length > 0
        Layout.fillWidth: true
        text: EasyEffects.error
        font.pixelSize: 11
        wrapMode: Text.WordWrap
        color: Appearance.m3colors.m3error
    }
}
