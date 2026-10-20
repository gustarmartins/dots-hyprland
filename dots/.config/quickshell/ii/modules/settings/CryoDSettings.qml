import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    spacing: 14
    property string appFilter: ""
    property int appPage: 0
    readonly property int appPageSize: 12
    readonly property var matchingApps: CryoDConsent.available ? CryoDConsent.apps.filter(app =>
        (CryoDConsent.appName(app.app_id) + " " + app.app_id).toLowerCase().includes(appFilter.trim().toLowerCase())) : []
    onAppFilterChanged: appPage = 0
    Connections {
        target: CryoDConsent
        function onAppsChanged() { root.appPage = 0; }
    }
    onVisibleChanged: CryoDConsent.viewActive = visible
    Component.onCompleted: CryoDConsent.viewActive = visible
    Component.onDestruction: CryoDConsent.viewActive = false
    StyledText { text: "CryoD desktop integration"; font.pixelSize: 22; font.weight: Font.Medium }
    RowLayout {
        Layout.fillWidth: true
        StyledText { Layout.fillWidth: true; text: "Enable desktop integration" }
        SettingsSwitch {
            objectName: "cryodMaster"
            checked: Config.options.cryod.enabled
            enabled: Config.ready && !Config.writesPaused
            onToggled: Config.setNestedValue("cryod.enabled", checked)
        }
    }
    StyledText {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: "Shares window focus with CryoD. Turning this off stops the session bridge; the memory daemon continues running."
    }
    ColumnLayout {
        objectName: "cryodFeatures"
        visible: Config.options.cryod.enabled
        Layout.fillWidth: true
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: "Protect the focused app tree" }
            SettingsSwitch {
                objectName: "cryodFocused"
                checked: Config.options.cryod.protectForeground
                enabled: Config.ready && !Config.writesPaused
                onToggled: Config.setNestedValue("cryod.protectForeground", checked)
            }
        }
        RowLayout {
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: "Protect other visible windows on every monitor" }
            SettingsSwitch {
                objectName: "cryodVisible"
                checked: Config.options.cryod.protectVisible
                enabled: Config.ready && !Config.writesPaused
                onToggled: Config.setNestedValue("cryod.protectVisible", checked)
            }
        }
        StyledText {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: !CryoDSession.wanted ? "No window protections selected."
                : CryoDSession.fresh ? "Window protection is active." : "Waiting for the CryoD session connection."
        }
        StyledText {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: "Protects verified window processes and their descendants from ordinary termination. Shared terminal jobs retain their explicit policies. Emergency runaway protection follows its separate policy. No window titles or keyboard input are recorded."
        }
        RowLayout {
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: "Focus Mode CPU boost" }
            SettingsSwitch {
                checked: FocusMode.enabled
                enabled: !FocusMode.busy && (FocusMode.available || FocusMode.enabled)
                onToggled: FocusMode.setEnabled(checked)
            }
        }
        StyledText {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: FocusMode.statusText + ". Prioritizes an isolated app group while focused. Shared terminal jobs and build quotas keep their own settings."
        }
        RowLayout {
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: "Group new launcher apps" }
            SettingsSwitch {
                objectName: "cryodGroupLaunches"
                checked: Config.options.cryod.groupLaunches
                enabled: Config.ready && !Config.writesPaused
                onToggled: Config.setNestedValue("cryod.groupLaunches", checked)
            }
        }
        StyledText {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: "Keeps each new launcher app in its own group for Focus Mode. Already running apps and terminal launches keep their current groups. This does not enable app freezing."
        }
        RowLayout {
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: "App freezing preferences"; font.weight: Font.Medium }
            RippleButtonWithIcon {
                objectName: "cryodRefreshApps"
                materialIcon: "refresh"; mainText: "Refresh"
                enabled: !CryoDConsent.busy
                onClicked: CryoDConsent.refresh()
            }
        }
        RowLayout {
            Layout.fillWidth: true
            StyledText { Layout.fillWidth: true; text: "Suggest apps to freeze" }
            SettingsSwitch {
                objectName: "cryodFreezeSuggestions"
                checked: Config.options.cryod.freezeSuggestions
                enabled: Config.ready && !Config.writesPaused
                onToggled: Config.setNestedValue("cryod.freezeSuggestions", checked)
            }
        }
        StyledText {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: Config.options.cryod.freezeSuggestions && (!Config.options.cryod.protectForeground || !Config.options.cryod.protectVisible)
                ? "Both window protections must be enabled for suggestions."
                : "Asks with Yes or No when an unapproved app keeps using CPU in the background."
        }
        StyledText {
            visible: CryoDConsent.available && CryoDConsent.apps.length === 0
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: "No installed apps or saved preferences are available."
        }
        MaterialTextField {
            objectName: "cryodAppSearch"
            visible: CryoDConsent.available && CryoDConsent.apps.length > 0
            Layout.fillWidth: true
            placeholderText: "Search apps"
            onTextChanged: root.appFilter = text
        }
        Repeater {
            model: root.matchingApps.slice(root.appPage * root.appPageSize, (root.appPage + 1) * root.appPageSize)
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.fillWidth: true
                    StyledText { text: CryoDConsent.appName(modelData.app_id); textFormat: Text.PlainText }
                    StyledText {
                        text: CryoDConsent.preference(modelData)
                            + (CryoDConsent.canChoose(modelData) ? "" : " · App unavailable")
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                    }
                }
                RippleButtonWithIcon {
                    objectName: "cryodChooseApp:" + modelData.app_id
                    materialIcon: "tune"; mainText: "Choose"
                    enabled: !CryoDConsent.busy && CryoDConsent.canChoose(modelData)
                    onClicked: CryoDConsent.ask(modelData)
                }
            }
        }
        RowLayout {
            visible: root.matchingApps.length > root.appPageSize
            Layout.fillWidth: true
            RippleButtonWithIcon {
                objectName: "cryodAppPrevious"
                materialIcon: "chevron_left"; mainText: "Previous"
                enabled: root.appPage > 0
                onClicked: root.appPage--
            }
            StyledText {
                Layout.fillWidth: true
                text: (root.appPage * root.appPageSize + 1) + "–"
                    + Math.min((root.appPage + 1) * root.appPageSize, root.matchingApps.length)
                    + " of " + root.matchingApps.length
            }
            RippleButtonWithIcon {
                objectName: "cryodAppNext"
                materialIcon: "chevron_right"; mainText: "Next"
                enabled: (root.appPage + 1) * root.appPageSize < root.matchingApps.length
                onClicked: root.appPage++
            }
        }
        StyledText {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: CryoDConsent.error || CryoDConsent.suggestionError || CryoDConsent.message
            visible: text.length > 0
            color: CryoDConsent.error || CryoDConsent.suggestionError ? Appearance.m3colors.m3error : Appearance.m3colors.m3onSurface
        }
    }
    RowLayout {
        Layout.fillWidth: true
        StyledText { Layout.fillWidth: true; text: "GPU and latency boost" }
        SettingsSwitch {
            checked: FocusMode.hardwareEnabled
            enabled: !FocusMode.busy
            onToggled: FocusMode.setHardwareEnabled(checked)
        }
    }
    StyledText {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: "Optional manual hardware boost. Uses more power and restores its previous settings when turned off."
    }
    StyledText {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        visible: text.length > 0
        text: FocusMode.error || CryoDSession.error || CryoDSession.fallbackError
        color: Appearance.m3colors.m3error
    }
}
