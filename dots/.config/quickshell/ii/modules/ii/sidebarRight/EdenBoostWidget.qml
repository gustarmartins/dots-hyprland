import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    visible: EdenAudioBoost.enabled
    spacing: 4
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 42
        radius: 12
        color: EdenAudioBoost.active ? Appearance.m3colors.m3errorContainer : Appearance.m3colors.m3surfaceContainerHigh
        StyledText {
            anchors.centerIn: parent
            text: EdenAudioBoost.busy ? "Updating Eden boost…" : EdenAudioBoost.active ? "Eden +12 dB · Click to reset" : "Eden +12 dB · Double-click to boost"
            font.pixelSize: 12
            color: EdenAudioBoost.active ? Appearance.m3colors.m3onErrorContainer : Appearance.m3colors.m3onSurface
        }
        Accessible.name: "Eden audio boost; double-click to activate, click to reset"
        MouseArea {
            anchors.fill: parent
            property real suppressBoostUntil: 0
            enabled: !EdenAudioBoost.busy
            onClicked: { if (EdenAudioBoost.active) { suppressBoostUntil = Date.now() + 700; EdenAudioBoost.reset(); } }
            onDoubleClicked: { if (!EdenAudioBoost.active && Date.now() >= suppressBoostUntil) EdenAudioBoost.boost(); }
        }
    }
    StyledText {
        Layout.fillWidth: true
        text: EdenAudioBoost.error || (EdenAudioBoost.streams ? "Only Eden · Uses your current effects" : "Start Eden audio first")
        font.pixelSize: 11
        wrapMode: Text.WordWrap
        color: Appearance.m3colors.m3onSurfaceVariant
    }
}
