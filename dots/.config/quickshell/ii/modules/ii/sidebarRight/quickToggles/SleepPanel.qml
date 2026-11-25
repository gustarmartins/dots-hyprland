import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    objectName: "sleepPanel"
    implicitWidth: 440
    implicitHeight: Idle.hasBattery ? 286 : 232
    property bool watching: false
    readonly property bool pollingVisible: visible && (Window.window?.visible ?? false)

    function watch() {
        if (watching === pollingVisible) return;
        watching = pollingVisible;
        Idle.watchers += watching ? 1 : -1;
    }

    onPollingVisibleChanged: watch()
    Component.onCompleted: watch()
    Component.onDestruction: if (watching) Idle.watchers--

    ColumnLayout {
        anchors.fill: parent
        spacing: 9

        RowLayout {
            Layout.fillWidth: true
            MaterialSymbol {
                text: "coffee"
                iconSize: 23
                color: Appearance.m3colors.m3primary
            }
            StyledText {
                text: "Sleep & Keep awake"
                font.pixelSize: 17
                font.weight: Font.Medium
                Layout.fillWidth: true
            }
            StyledText {
                text: Idle.busy ? "Applying…" : Idle.inhibit ? "Awake" : (Idle.onAc ? "Plugged in" : "Battery")
                color: Idle.inhibit ? Appearance.m3colors.m3primary : Appearance.m3colors.m3onSurfaceVariant
                font.pixelSize: 11
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            StyledText {
                text: "Keep awake"
                font.pixelSize: 12
                Layout.fillWidth: true
            }
            StyledSwitch {
                id: keepAwakeSwitch
                objectName: "sleepKeepAwakeSwitch"
                checked: Idle.inhibit
                enabled: Idle.ready && !Idle.busy
                onToggled: Idle.toggleInhibit(checked)
                Accessible.name: "Keep awake"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            StyledText {
                text: "Plugged in"
                Layout.preferredWidth: 74
                font.pixelSize: 12
            }
            StyledComboBox {
                id: acSleepPicker
                objectName: "sleepAcPicker"
                Layout.fillWidth: true
                enabled: Idle.ready && !Idle.busy
                model: Idle.timeoutModes
                textRole: "label"
                valueRole: "value"
                currentIndex: Math.max(0, Idle.timeoutModes.findIndex(m => m.value === Idle.acSleepMinutes))
                onActivated: index => Idle.setAcSleep(Idle.timeoutModes[index].value)
                Accessible.name: "Auto-sleep when plugged in"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            StyledText {
                text: "On battery"
                Layout.preferredWidth: 74
                font.pixelSize: 12
            }
            StyledComboBox {
                id: batterySleepPicker
                objectName: "sleepBatteryPicker"
                Layout.fillWidth: true
                enabled: Idle.ready && !Idle.busy
                model: Idle.timeoutModes
                textRole: "label"
                valueRole: "value"
                currentIndex: Math.max(0, Idle.timeoutModes.findIndex(m => m.value === Idle.batterySleepMinutes))
                onActivated: index => Idle.setBatterySleep(Idle.timeoutModes[index].value)
                Accessible.name: "Auto-sleep on battery"
            }
        }

        RowLayout {
            visible: Idle.hasBattery
            Layout.fillWidth: true
            spacing: 10
            StyledText {
                text: "Lid close"
                Layout.preferredWidth: 74
                font.pixelSize: 12
            }
            StyledComboBox {
                id: lidAcPicker
                objectName: "sleepLidAcPicker"
                Layout.fillWidth: true
                enabled: Idle.ready && !Idle.busy
                model: [
                    { value: "ignore", label: "AC: Stay awake" },
                    { value: "suspend", label: "AC: Sleep" }
                ]
                textRole: "label"
                valueRole: "value"
                currentIndex: Idle.lidOnAc === "suspend" ? 1 : 0
                onActivated: index => Idle.setLidOnAc(index === 1 ? "suspend" : "ignore")
                Accessible.name: "Lid close action when plugged in"
            }
            StyledComboBox {
                id: lidBatteryPicker
                objectName: "sleepLidBatteryPicker"
                Layout.fillWidth: true
                enabled: Idle.ready && !Idle.busy
                model: [
                    { value: "ignore", label: "Bat: Stay awake" },
                    { value: "suspend", label: "Bat: Sleep" }
                ]
                textRole: "label"
                valueRole: "value"
                currentIndex: Idle.lidOnBattery === "suspend" ? 1 : 0
                onActivated: index => Idle.setLidOnBattery(index === 1 ? "suspend" : "ignore")
                Accessible.name: "Lid close action on battery"
            }
        }

        StyledText {
            objectName: "sleepActualState"
            Layout.fillWidth: true
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            color: Idle.error ? Appearance.m3colors.m3error : Appearance.m3colors.m3onSurfaceVariant
            text: Idle.error || (!Idle.ready ? "Reading sleep policy…"
                : Idle.inhibit
                    ? "Keep awake active · blocking idle, sleep" + (Idle.hasBattery ? " & lid switch" : "")
                    : (Idle.onAc ? "Plugged in" : "On battery")
                        + " · Auto-sleep: " + Idle.formatMinutes(Idle.effectiveSleepMinutes)
                        + (Idle.hasBattery ? " · Lid: " + (Idle.effectiveLidAction === "ignore" ? "Stay awake" : "Sleep") : ""))
        }

        StyledText {
            Layout.fillWidth: true
            font.pixelSize: 10
            color: Appearance.m3colors.m3onSurfaceVariant
            text: "Changes save immediately and sync logind + hypridle."
        }

        Item { Layout.fillHeight: true }
    }
}
