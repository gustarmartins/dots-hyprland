import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root
    color: Appearance.m3colors.m3surfaceContainerHigh
    radius: 24
    implicitHeight: content.implicitHeight + 24

    function label(name) {
        const labels = {"astra-music": "Music", "astra-rock": "Rock",
                        "astra-osu": "osu!", "astra-mk8dx": "MK8DX"}
        return labels[name] ?? name.replace(/^astra-/, "")
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                text: "EasyEffects"
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.m3colors.m3onSurface
            }
            StyledText {
                text: EasyEffects.busy ? "Applying…" : !EasyEffects.active ? "Off"
                    : EasyEffects.bypassed ? "Bypassed" : root.label(EasyEffects.preset)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.m3colors.m3onSurfaceVariant
            }
        }
        ConfigSelectionArray {
            enabled: !EasyEffects.busy
            currentValue: EasyEffects.active ? EasyEffects.preset : ""
            options: EasyEffects.presets.map(name => ({displayName: root.label(name), value: name}))
            onSelected: value => EasyEffects.selectPreset(value)
        }
        StyledText {
            visible: EasyEffects.error.length > 0
            Layout.fillWidth: true
            text: EasyEffects.error
            wrapMode: Text.WordWrap
            color: Appearance.m3colors.m3error
        }
    }
}
