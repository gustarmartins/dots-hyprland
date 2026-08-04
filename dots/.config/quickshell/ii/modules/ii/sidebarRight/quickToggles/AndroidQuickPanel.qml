import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

import qs.modules.ii.sidebarRight.notifications
import qs.modules.ii.sidebarRight.quickToggles.androidStyle

AbstractQuickPanel {
    id: root
    property bool editMode: false
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.minimumHeight: root.baseCellHeight * 2 + root.padding * 2 + 36 + root.spacing

    // Sizes
    property real spacing: 6
    property real padding: 6
    readonly property real baseCellWidth: {
        // This is the wrong calculation, but it looks correct in reality???
        // (theoretically spacing should be multiplied by 1 column less)
        const availableWidth = root.width - (root.padding * 2) - (root.spacing * (root.columns))
        return availableWidth / root.columns
    }
    readonly property real baseCellHeight: 56

    // Toggles
    readonly property list<string> availableToggleTypes: ["network", "bluetooth", "idleInhibitor", "easyEffects", "nightLight", "darkMode", "cloudflareWarp", "gameMode", "tearing", "directScanout", "tripleBuffer", "screenSnip", "colorPicker", "onScreenKeyboard", "mic", "audio", "notifications", "powerProfile","musicRecognition", "antiFlashbang", "memoryMode", "zramRecompress", "zramWriteback", "dropCaches", "memoryCompact", "gpuMemory"]
    readonly property int columns: Config.options.sidebar.quickToggles.android.columns
    readonly property list<var> toggles: Config.ready ? Config.options.sidebar.quickToggles.android.toggles : []
    readonly property list<var> toggleRows: toggleRowsForList(toggles)
    readonly property list<var> unusedToggles: {
        const types = availableToggleTypes.filter(type => !toggles.some(toggle => (toggle && toggle.type === type)))
        return types.map(type => { return { type: type, size: 1 } })
    }
    readonly property list<var> unusedToggleRows: toggleRowsForList(unusedToggles)
    readonly property var latestNotification: Notifications.list.length > 0
        ? Notifications.list[Notifications.list.length - 1]
        : null
    readonly property string latestNotificationText: notificationPreview(latestNotification)

    function plainNotificationText(value) {
        return String(value ?? "")
            .replace(/<[^>]*>/g, " ")
            .replace(/&nbsp;/gi, " ")
            .replace(/&amp;/gi, "&")
            .replace(/&lt;/gi, "<")
            .replace(/&gt;/gi, ">")
            .replace(/\s+/g, " ")
            .trim();
    }

    function notificationPreview(notification) {
        if (!notification)
            return Translation.tr("0 notifications");

        const appName = plainNotificationText(notification.appName);
        const summary = plainNotificationText(notification.summary);
        const body = plainNotificationText(notification.body);
        const parts = [];
        if (appName.length > 0)
            parts.push(appName);
        if (summary.length > 0 && summary !== appName)
            parts.push(summary);
        if (body.length > 0 && body !== summary)
            parts.push(body);
        return parts.length > 0 ? parts.join("  ·  ") : Translation.tr("%1 notifications").arg(Notifications.list.length);
    }

    function toggleRowsForList(togglesList) {
        var rows = [];
        var row = [];
        var totalSize = 0; // Total cols taken in current row
        for (var i = 0; i < togglesList.length; i++) {
            if (!togglesList[i]) continue;
            if (totalSize + togglesList[i].size > columns) {
                rows.push(row);
                row = [];
                totalSize = 0;
            }
            row.push(togglesList[i]);
            totalSize += togglesList[i].size;
        }
        if (row.length > 0) {
            rows.push(row);
        }
        return rows;
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: root.spacing

        StyledFlickable {
            id: togglesFlickable
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: contentItem.implicitHeight
            clip: true
            flickableDirection: Flickable.VerticalFlick
            interactive: contentHeight > height

            Column {
                id: contentItem
                width: togglesFlickable.width
                spacing: 12

                Column {
                    id: usedRows
                    width: parent.width
                    spacing: root.spacing

                    Repeater {
                        id: usedRowsRepeater
                        model: ScriptModel {
                            values: Array(root.toggleRows.length)
                        }
                        delegate: ButtonGroup {
                            id: toggleRow
                            required property int index
                            property var modelData: root.toggleRows[index]
                            property int startingIndex: {
                                const rows = root.toggleRows;
                                let sum = 0;
                                for (let i = 0; i < index; i++) {
                                    sum += rows[i].length;
                                }
                                return sum;
                            }
                            spacing: root.spacing

                            Repeater {
                                model: ScriptModel {
                                    values: toggleRow?.modelData ?? []
                                    objectProp: "type"
                                }
                                delegate: AndroidToggleDelegateChooser {
                                    startingIndex: toggleRow.startingIndex
                                    editMode: root.editMode
                                    baseCellWidth: root.baseCellWidth
                                    baseCellHeight: root.baseCellHeight
                                    spacing: root.spacing
                                    onOpenAudioOutputDialog: root.openAudioOutputDialog()
                                    onOpenAudioInputDialog: root.openAudioInputDialog()
                                    onOpenBluetoothDialog: root.openBluetoothDialog()
                                    onOpenNightLightDialog: root.openNightLightDialog()
                                    onOpenWifiDialog: root.openWifiDialog()
                                }
                            }
                        }
                    }
                }

                FadeLoader {
                    shown: root.editMode
                    anchors {
                        left: parent.left
                        right: parent.right
                        leftMargin: root.baseCellHeight / 2
                        rightMargin: root.baseCellHeight / 2
                    }
                    sourceComponent: Rectangle {
                        implicitHeight: 1
                        color: Appearance.colors.colOutlineVariant
                    }
                }

                FadeLoader {
                    shown: root.editMode
                    sourceComponent: Column {
                        id: unusedRows
                        spacing: root.spacing

                        Repeater {
                            model: ScriptModel {
                                values: Array(root.unusedToggleRows.length)
                            }
                            delegate: ButtonGroup {
                                id: unusedToggleRow
                                required property int index
                                property var modelData: root.unusedToggleRows[index]
                                spacing: root.spacing

                                Repeater {
                                    model: ScriptModel {
                                        values: unusedToggleRow?.modelData ?? []
                                        objectProp: "type"
                                    }
                                    delegate: AndroidToggleDelegateChooser {
                                        startingIndex: -1
                                        editMode: root.editMode
                                        baseCellWidth: root.baseCellWidth
                                        baseCellHeight: root.baseCellHeight
                                        spacing: root.spacing
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        NotificationStatusButton {
            id: notificationButton
            Layout.fillWidth: true
            buttonIcon: "notifications"
            buttonText: root.latestNotificationText
            marquee: Notifications.list.length > 0
            onClicked: root.openNotifications()
            StyledToolTip {
                text: Translation.tr("%1 notifications").arg(Notifications.list.length)
                    + " · " + Translation.tr("Show notifications")
            }
        }
    }
}
