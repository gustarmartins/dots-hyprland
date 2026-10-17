import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    spacing: 12
    Component.onCompleted: Mail.refresh()
    component MailSwitch: RowLayout {
        property string text
        property alias checked: toggle.checked
        signal toggled()
        Layout.fillWidth: true
        StyledText { Layout.fillWidth: true; text: parent.text; wrapMode: Text.WordWrap; font.pixelSize: 14 }
        SettingsSwitch { id: toggle; objectName: parent.objectName + ":switch"; Accessible.name: parent.text; onToggled: parent.toggled() }
    }
    MailSwitch {
        objectName: "mailMaster"
        text: "Mail integration"
        checked: Mail.enabled
        enabled: !Mail.busy
        onToggled: Mail.setFeature("enabled", checked)
    }
    StyledText {
        Layout.fillWidth: true
        text: Mail.enabled ? (Mail.state.connected ? Mail.state.status || "Connected to Thunderbird" : "Waiting for Thunderbird. If it is already open, use its Quickshell Mail toolbar button to reconnect.") : "Off. Background mail checking is stopped."
        wrapMode: Text.WordWrap
        font.pixelSize: 13
        color: Appearance.m3colors.m3onSurfaceVariant
    }
    ColumnLayout {
        visible: Mail.enabled
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: [
                {key:"notifications", title:"New mail notifications"},
                {key:"preview", title:"Show message previews"},
                {key:"codes", title:"Copy verification codes"},
                {key:"links", title:"Show link actions"}
            ]
            delegate: MailSwitch {
                required property var modelData
                objectName: "mail_" + modelData.key
                text: modelData.title
                checked: Mail.config[modelData.key] === true
                enabled: !Mail.busy
                onToggled: Mail.setFeature(modelData.key, checked)
            }
        }
        StyledText {
            Layout.fillWidth: true
            text: "Codes and links are found on this device. Mail previews stay in memory until you close the shell."
            wrapMode: Text.WordWrap
            font.pixelSize: 12
            color: Appearance.m3colors.m3onSurfaceVariant
        }
        StyledText { text: "Accounts"; font.pixelSize: 20; Layout.topMargin: 12 }
        Repeater {
            model: Mail.accounts
            delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                MailSwitch {
                    text: modelData.email || modelData.name
                    checked: (Mail.config.accounts || []).includes(modelData.id)
                    enabled: !Mail.busy
                    onToggled: Mail.setAccount(modelData.id, checked)
                }
                StyledText {
                    Layout.fillWidth: true
                    text: modelData.type === "ews" ? "Exchange EWS · add this Microsoft 365 account with Graph in Thunderbird." : "Notifications for this account"
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
                    color: Appearance.m3colors.m3onSurfaceVariant
                }
            }
        }
        StyledText { visible: Mail.accounts.length === 0; text: "Add an account in Thunderbird to get started."; font.pixelSize: 13 }
        Flow {
            Layout.fillWidth: true
            spacing: 8
            SettingsButton { text: "Open mail"; enabled: !Mail.busy; onClicked: Mail.run(["open"]) }
            SettingsButton { text: "Add / manage accounts"; enabled: !Mail.busy; onClicked: Mail.run(["accounts"]) }
            SettingsButton { text: "Preview unread mail"; enabled: !Mail.busy && Mail.state.connected && Mail.config.notifications; onClicked: Mail.run(["preview"]) }
            SettingsButton { text: "Refresh"; enabled: !Mail.busy; onClicked: Mail.refresh() }
            SettingsButton { text: "Start checking"; visible: !Mail.state.connected; enabled: !Mail.busy; onClicked: Mail.setFeature("enabled", true) }
        }
        StyledText {
            Layout.fillWidth: true
            text: "Turning Mail off closes the Thunderbird instance started by this integration. A separately opened Thunderbird remains under your control. Account sign-in and sync settings live in Thunderbird."
            wrapMode: Text.WordWrap
            font.pixelSize: 12
            color: Appearance.m3colors.m3onSurfaceVariant
        }
    }
    StyledText { Layout.fillWidth: true; visible: Mail.error.length > 0; text: Mail.error; wrapMode: Text.WordWrap; color: Appearance.m3colors.m3error; font.pixelSize: 13 }
}
