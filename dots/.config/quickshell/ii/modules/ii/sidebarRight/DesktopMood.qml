import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    spacing: 5
    StyledText {
        text: "Desktop mood"
        font.pixelSize: 11
        color: Appearance.m3colors.m3onSurfaceVariant
    }
    StyledComboBox {
        id: picker
        objectName: "controlMoodPicker"
        Layout.fillWidth: true
        implicitHeight: 38
        buttonRadius: 12
        buttonIcon: "auto_awesome"
        colBackground: Appearance.m3colors.m3surfaceContainerHigh
        enabled: !apply.running
        model: [
            {label: "Light", value: "light"},
            {label: "Balanced", value: "balanced"},
            {label: "Cinema", value: "cinematic"},
            {label: "Aurora", value: "aurora"}
        ]
        textRole: "label"
        valueRole: "value"
        currentIndex: model.findIndex(option => option.value === DesktopEffects.settings.preset)
        onActivated: {
            apply.command = [Quickshell.env("HOME") + "/.local/bin/desktop-effects", "preset", currentValue];
            apply.running = true;
        }
        Accessible.name: "Desktop mood"
    }
    StyledText { id: errorLabel; visible: text.length > 0; Layout.fillWidth: true; font.pixelSize: 11; wrapMode: Text.WordWrap; color: Appearance.m3colors.m3error }
    Process {
        id: apply
        stderr: StdioCollector { id: errors }
        onExited: (code, status) => errorLabel.text = code === 0 ? "" : errors.text
    }
}
