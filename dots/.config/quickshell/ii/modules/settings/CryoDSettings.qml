import QtQuick
import "../../services/CryoDAppStats.js" as AppStats
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
    property string appScope: "relevant"
    property string appSort: "relevant"
    property real minimumCpu: 0
    readonly property var matchingApps: CryoDConsent.available ? AppStats.select(
        CryoDConsent.apps, CryoDConsent.appName, appFilter, appScope, appSort, minimumCpu) : []
    onAppFilterChanged: appPage = 0
    onAppScopeChanged: appPage = 0
    onAppSortChanged: appPage = 0
    onMinimumCpuChanged: appPage = 0
    onMatchingAppsChanged: appPage = Math.min(appPage, Math.max(0, Math.ceil(matchingApps.length / appPageSize) - 1))
    Connections {
        target: CryoDConsent
        function onAvailableChanged() { if (!CryoDConsent.available) root.appPage = 0; }
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
            StyledText { Layout.fillWidth: true; text: "Performance"; font.weight: Font.Medium }
            SettingsSwitch {
                objectName: "cryodPerformance"
                checked: FocusMode.enabled
                enabled: !FocusMode.busy && (FocusMode.available || FocusMode.enabled || FocusMode.hardwareLeased)
                onToggled: FocusMode.setEnabled(checked)
            }
        }
        StyledText {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: FocusMode.statusText + ". Gives supported focused apps CPU priority. Off restores its CPU and optional hardware boosts."
        }
        ColumnLayout {
            objectName: "cryodPerformanceOptions"
            visible: FocusMode.enabled
            Layout.fillWidth: true
            RowLayout {
                Layout.fillWidth: true
                StyledText { Layout.fillWidth: true; text: "Include GPU and latency boost" }
                SettingsSwitch {
                    objectName: "cryodPerformanceHardware"
                    checked: FocusMode.hardwareEnabled
                    enabled: !FocusMode.busy
                    onToggled: FocusMode.setHardwareEnabled(checked)
                }
            }
            StyledText {
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                text: "Uses more power. Remembers your choice for the next time Performance is enabled."
            }
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
            text: "Keeps each new launcher app in its own group for Performance. Already running apps and terminal launches keep their current groups. This does not enable app freezing."
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
        Flow {
            Layout.fillWidth: true
            spacing: 8
            StyledComboBox {
                objectName: "cryodAppScope"
                width: Math.min(230, parent.width)
                model: ["Seen or configured", "Seen by CryoD", "Background CPU", "Running apps", "All installed apps"]
                onActivated: root.appScope = ["relevant", "seen", "cpu", "running", "all"][currentIndex]
            }
            StyledComboBox {
                objectName: "cryodAppSort"
                width: Math.min(230, parent.width)
                model: ["Sort: Most relevant", "Sort: Background CPU", "Sort: Last seen", "Sort: Name"]
                onActivated: root.appSort = ["relevant", "cpu", "recent", "name"][currentIndex]
            }
            StyledComboBox {
                objectName: "cryodAppCpuMinimum"
                width: Math.min(200, parent.width)
                model: ["Any CPU usage", "CPU ≥ 1%", "CPU ≥ 5%", "CPU ≥ 10%", "CPU ≥ 25%"]
                onActivated: root.minimumCpu = [0, 1, 5, 10, 25][currentIndex]
            }
        }
        StyledText {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: "CPU shows peak sustained background use recorded by suggestions over the last 30 days. 100% equals one CPU core."
        }
        StyledText {
            objectName: "cryodAppCount"
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: !CryoDConsent.available ? "Waiting for app information…"
                : root.matchingApps.length === 0 ? "No matching apps. Try All installed apps or lower the CPU filter."
                : root.matchingApps.length + " matching apps"
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
                        text: AppStats.summary(modelData)
                        textFormat: Text.PlainText
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                    }
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
            text: CryoDConsent.error || CryoDConsent.suggestionError || CryoDConsent.historyError || CryoDConsent.message
            visible: text.length > 0
            color: CryoDConsent.error || CryoDConsent.suggestionError ? Appearance.m3colors.m3error : Appearance.m3colors.m3onSurface
        }
    }
    StyledText {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        visible: text.length > 0
        text: FocusMode.error || CryoDSession.error || CryoDSession.fallbackError
        color: Appearance.m3colors.m3error
    }
}
