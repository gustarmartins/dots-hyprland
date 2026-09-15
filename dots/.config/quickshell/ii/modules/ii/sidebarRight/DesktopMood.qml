import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
Rectangle {
    id: root
    color: Appearance.m3colors.m3surfaceContainerHigh
    radius: 24
    implicitHeight: content.implicitHeight + 24
    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8
        StyledText {
            text: "Desktop mood"
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.m3colors.m3onSurface
        }
        ConfigSelectionArray {
            enabled: !apply.running
            currentValue: DesktopEffects.settings.preset
            options: [
                {displayName: "Light", value: "light"},
                {displayName: "Balanced", value: "balanced"},
                {displayName: "Cinema", value: "cinematic"},
                {displayName: "Aurora", value: "aurora"}
            ]
            onSelected: value => {
                apply.command = [Quickshell.env("HOME") + "/.local/bin/desktop-effects", "preset", value];
                apply.running = true;
            }
        }
        StyledText { id: errorLabel; visible: text.length > 0; Layout.fillWidth: true; wrapMode: Text.WordWrap }
    }
    Process {
        id: apply
        stderr: StdioCollector { id: errors }
        onExited: (code, status) => errorLabel.text = code === 0 ? "" : errors.text
    }
}
