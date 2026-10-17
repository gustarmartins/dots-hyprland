import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland

import qs.modules.ii.sidebarRight.quickToggles
import qs.modules.ii.sidebarRight.quickToggles.classicStyle

import qs.modules.ii.sidebarRight.bluetoothDevices
import qs.modules.ii.sidebarRight.nightLight
import qs.modules.ii.sidebarRight.volumeMixer
import qs.modules.ii.sidebarRight.wifiNetworks

Item {
    id: root
    property alias glassSurface: sidebarRightBackground
    property int sidebarWidth: Appearance.sizes.sidebarWidth
    property int sidebarPadding: 16
    property string settingsQmlPath: Quickshell.shellPath("settings.qml")
    property bool showAudioOutputDialog: false
    property bool showAudioInputDialog: false
    property bool showBluetoothDialog: false
    property bool showNightLightDialog: false
    property bool showWifiDialog: false
    property bool editMode: false
    property bool showingNotifications: false
    property bool showingWidgets: false

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (!GlobalStates.sidebarRightOpen) {
                root.showWifiDialog = false;
                root.showBluetoothDialog = false;
                root.showAudioOutputDialog = false;
                root.showAudioInputDialog = false;
            } else {
                root.showingNotifications = false;
            }
        }
    }

    implicitHeight: 600
    implicitWidth: sidebarWidth

    StyledRectangularShadow {
        target: sidebarRightBackground
    }
    GlassSurface {
        id: sidebarRightBackground

        anchors.fill: parent
        implicitHeight: parent.height - Appearance.sizes.hyprlandGapsOut * 2
        implicitWidth: sidebarWidth - Appearance.sizes.hyprlandGapsOut * 2
        surfaceOpacity: (DesktopEffects.settings.panel_opacity ?? 94) / 100
        radius: 28
        topRightRadius: 12
        bottomRightRadius: 12

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: sidebarPadding
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                ColumnLayout {
                    spacing: 3
                    StyledText {
                        text: "Control center"
                        font.pixelSize: 24
                        font.weight: Font.Medium
                        color: Appearance.m3colors.m3onSurface
                    }
                    StyledText {
                        text: Qt.formatDateTime(DateTime.clock.date, "ddd, d MMM") + "  ·  Up " + DateTime.uptime
                        font.pixelSize: 11
                        color: Appearance.m3colors.m3onSurfaceVariant
                    }
                }
                Item { Layout.fillWidth: true }
                QuickToggleButton {
                    objectName: "controlCenterEdit"
                    toggled: root.editMode
                    visible: Config.options.sidebar.quickToggles.style === "android"
                    buttonIcon: root.editMode ? "check" : "edit"
                    onClicked: {
                        root.showingNotifications = false;
                        root.showingWidgets = false;
                        root.editMode = !root.editMode;
                    }
                    StyledToolTip { text: root.editMode ? "Finish editing" : "Arrange and resize widgets" }
                }
                QuickToggleButton {
                    buttonIcon: "settings"
                    onClicked: {
                        GlobalStates.sidebarRightOpen = false;
                        Quickshell.execDetached(["qs", "-p", root.settingsQmlPath]);
                    }
                    StyledToolTip { text: Translation.tr("Settings") }
                }
                QuickToggleButton {
                    buttonIcon: "power_settings_new"
                    onClicked: GlobalStates.sessionOpen = true
                    StyledToolTip { text: Translation.tr("Session") }
                }
                QuickToggleButton {
                    buttonIcon: "close"
                    onClicked: GlobalStates.sidebarRightOpen = false
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: [
                        {label: "Controls", icon: "tune", value: "controls"},
                        {label: "Inbox · " + Notifications.list.length, icon: "notifications", value: "inbox"},
                        {label: "Agenda", icon: "calendar_month", value: "agenda"}
                    ]
                    delegate: RippleButton {
                        id: tabButton
                        objectName: "controlTab-" + modelData.value
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: 36
                        buttonRadius: 12
                        toggled: (root.showingNotifications ? "inbox" : root.showingWidgets ? "agenda" : "controls") === modelData.value
                        colBackground: Appearance.m3colors.m3surfaceContainerHigh
                        onClicked: {
                            root.showingNotifications = modelData.value === "inbox";
                            root.showingWidgets = modelData.value === "agenda";
                        }
                        contentItem: RowLayout {
                            spacing: 6
                            MaterialSymbol { text: modelData.icon; iconSize: 17; color: tabButton.toggled ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onSurface }
                            StyledText { Layout.fillWidth: true; text: modelData.label; font.pixelSize: 12; color: tabButton.toggled ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onSurface; elide: Text.ElideRight }
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: !root.showingNotifications && !root.showingWidgets && !root.editMode
                spacing: 10
                DesktopMood { Layout.fillWidth: true; Layout.preferredWidth: 1 }
                EasyEffectsPresets { Layout.fillWidth: true; Layout.preferredWidth: 1.4; visible: EasyEffects.available }
            }

            EdenBoostWidget { Layout.fillWidth: true; visible: EdenAudioBoost.enabled && !root.showingNotifications && !root.showingWidgets && !root.editMode }

            Loader {
                id: slidersLoader
                Layout.fillWidth: true
                visible: active && !root.showingNotifications && !root.showingWidgets && !root.editMode
                active: {
                    const configQuickSliders = Config.options.sidebar.quickSliders
                    if (!configQuickSliders.enable) return false
                    if (!configQuickSliders.showMic && !configQuickSliders.showVolume && !configQuickSliders.showBrightness) return false;
                    return true;
                }
                sourceComponent: QuickSliders {}
            }

            LoaderedQuickPanelImplementation {
                styleName: "classic"
                sourceComponent: ClassicQuickPanel {}
            }

            LoaderedQuickPanelImplementation {
                styleName: "android"
                sourceComponent: AndroidQuickPanel {
                    editMode: root.editMode
                }
            }

            CenterWidgetGroup {
                visible: root.showingNotifications
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: true
                Layout.fillWidth: true
                onOpenQuickSettings: root.showingNotifications = false
            }

            BottomWidgetGroup {
                visible: root.showingWidgets
                forceExpanded: root.showingWidgets
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: true
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
            }
        }
    }

    ToggleDialog {
        shownPropertyString: "showAudioOutputDialog"
        dialog: VolumeDialog {
            isSink: true
        }
    }

    ToggleDialog {
        shownPropertyString: "showAudioInputDialog"
        dialog: VolumeDialog {
            isSink: false
        }
    }

    ToggleDialog {
        shownPropertyString: "showBluetoothDialog"
        dialog: BluetoothDialog {}
        onShownChanged: {
            if (!shown) {
                Bluetooth.defaultAdapter.discovering = false;
            } else {
                Bluetooth.defaultAdapter.enabled = true;
                Bluetooth.defaultAdapter.discovering = true;
            }
        }
    }

    ToggleDialog {
        shownPropertyString: "showNightLightDialog"
        dialog: NightLightDialog {}
    }

    ToggleDialog {
        shownPropertyString: "showWifiDialog"
        dialog: WifiDialog {}
        onShownChanged: {
            if (!shown) return;
            Network.enableWifi();
            Network.rescanWifi();
        }
    }

    component ToggleDialog: Loader {
        id: toggleDialogLoader
        required property string shownPropertyString
        property alias dialog: toggleDialogLoader.sourceComponent
        readonly property bool shown: root[shownPropertyString]
        anchors.fill: parent

        onShownChanged: if (shown) toggleDialogLoader.active = true;
        active: shown
        onActiveChanged: {
            if (active) {
                item.show = true;
                item.forceActiveFocus();
            }
        }
        Connections {
            target: toggleDialogLoader.item
            function onDismiss() {
                toggleDialogLoader.item.show = false
                root[toggleDialogLoader.shownPropertyString] = false;
            }
            function onVisibleChanged() {
                if (!toggleDialogLoader.item.visible && !root[toggleDialogLoader.shownPropertyString]) toggleDialogLoader.active = false;
            }
        }
    }

    component LoaderedQuickPanelImplementation: Loader {
        id: quickPanelImplLoader
        required property string styleName
        Layout.alignment: item?.Layout.alignment ?? Qt.AlignHCenter
        Layout.fillWidth: item?.Layout.fillWidth ?? false
        Layout.fillHeight: item?.Layout.fillHeight ?? false
        Layout.minimumHeight: item?.Layout.minimumHeight ?? 0
        visible: active && !root.showingNotifications && !root.showingWidgets
        active: Config.options.sidebar.quickToggles.style === styleName
        Connections {
            target: quickPanelImplLoader.item
            function onOpenAudioOutputDialog() {
                root.showAudioOutputDialog = true;
            }
            function onOpenAudioInputDialog() {
                root.showAudioInputDialog = true;
            }
            function onOpenBluetoothDialog() {
                root.showBluetoothDialog = true;
            }
            function onOpenNightLightDialog() {
                root.showNightLightDialog = true;
            }
            function onOpenWifiDialog() {
                root.showWifiDialog = true;
            }
            function onOpenNotifications() {
                root.showingNotifications = true;
                root.showingWidgets = false;
            }
        }
    }

}
