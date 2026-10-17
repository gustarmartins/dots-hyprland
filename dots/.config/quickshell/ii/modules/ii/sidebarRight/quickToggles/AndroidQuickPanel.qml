import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.ii.sidebarRight.notifications
import qs.modules.ii.sidebarRight.quickToggles.androidStyle
import "TileGrid.js" as TileGrid

AbstractQuickPanel {
    id: root
    objectName: "controlTilePanel"
    property bool editMode: false
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.minimumHeight: 140
    color: "transparent"
    property real spacing: 8
    property real padding: 0
    readonly property int columns: Math.max(1, Math.min(12, Config.options.sidebar.quickToggles.android.columns))
    readonly property real baseCellWidth: Math.max(1, (togglesFlickable.width - spacing * (columns - 1)) / columns)
    readonly property real baseCellHeight: 72
    readonly property list<string> availableToggleTypes: ["network", "bluetooth", "idleInhibitor", "easyEffects", "nightLight", "darkMode", "cloudflareWarp", "gameMode", "tearing", "vrr", "lsfg", "directScanout", "tripleBuffer", "screenSnip", "colorPicker", "onScreenKeyboard", "mic", "audio", "notifications", "powerProfile", "musicRecognition", "antiFlashbang", "memoryMode", "focusMode", "buildCache", "zramAlgo", "zramRecompress", "zramWriteback", "dropCaches", "memoryCompact", "gpuMemory"]
    readonly property list<var> toggles: Config.ready ? Config.options.sidebar.quickToggles.android.toggles : []
    readonly property var placement: TileGrid.layout(toggles, columns, 7)
    readonly property var unusedToggles: availableToggleTypes.filter(type => !toggles.some(tile => tile?.type === type))
    readonly property var latestNotification: Notifications.list.length > 0 ? Notifications.list[Notifications.list.length - 1] : null
    readonly property string latestNotificationText: notificationPreview(latestNotification)

    function resizeTile(index, width, height) {
        Config.options.sidebar.quickToggles.android.toggles = TileGrid.resize(toggles, index, width, height, columns);
    }
    function moveTile(index, x, y) {
        Config.options.sidebar.quickToggles.android.toggles = TileGrid.move(toggles, index,
            x / (baseCellWidth + spacing), y / (baseCellHeight + spacing), columns);
    }
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


    ColumnLayout {
        anchors.fill: parent
        spacing: 8
        RowLayout {
            visible: root.editMode
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                text: "Drag to place · corner to resize · × to remove · click for size"
                wrapMode: Text.WordWrap
                font.pixelSize: 12
                color: Appearance.m3colors.m3onSurfaceVariant
            }
            StyledText { text: "Columns"; font.pixelSize: 12 }
            StyledSpinBox {
                objectName: "tileGridColumns"
                from: 1
                to: 12
                value: root.columns
                onValueModified: Config.options.sidebar.quickToggles.android.columns = value
                Accessible.name: "Grid columns"
            }
        }
        StyledFlickable {
            id: togglesFlickable
            objectName: "controlTileScroll"
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: tileCanvas.height + (root.editMode ? addTiles.implicitHeight + 16 : 0)
            clip: true
            flickableDirection: Flickable.VerticalFlick
            interactive: contentHeight > height
            Item {
                id: tileCanvas
                objectName: "controlTileCanvas"
                width: togglesFlickable.width
                height: root.placement.rows * (root.baseCellHeight + root.spacing) - root.spacing
                Repeater {
                    model: root.editMode ? root.columns * root.placement.rows : 0
                    delegate: Rectangle {
                        required property int index
                        x: (index % root.columns) * (root.baseCellWidth + root.spacing)
                        y: Math.floor(index / root.columns) * (root.baseCellHeight + root.spacing)
                        width: root.baseCellWidth
                        height: root.baseCellHeight
                        radius: 14
                        color: "transparent"
                        border.width: 1
                        border.color: Appearance.m3colors.m3outlineVariant
                        opacity: 0.4
                    }
                }
                Repeater {
                    model: root.placement.tiles
                    delegate: AndroidToggleDelegateChooser {
                        startingIndex: 0
                        editMode: root.editMode
                        baseCellWidth: root.baseCellWidth
                        baseCellHeight: root.baseCellHeight
                        spacing: root.spacing
                        columns: root.columns
                        onTileResized: (index, width, height) => root.resizeTile(index, width, height)
                        onTileMoved: (index, x, y) => root.moveTile(index, x, y)
                        onOpenAudioOutputDialog: root.openAudioOutputDialog()
                        onOpenAudioInputDialog: root.openAudioInputDialog()
                        onOpenBluetoothDialog: root.openBluetoothDialog()
                        onOpenNightLightDialog: root.openNightLightDialog()
                        onOpenWifiDialog: root.openWifiDialog()
                    }
                }
            }
            Flow {
                id: addTiles
                x: 0
                y: tileCanvas.height + 16
                width: parent.width
                spacing: 6
                visible: root.editMode
                Repeater {
                    model: root.editMode ? root.unusedToggles : []
                    delegate: RippleButton {
                        required property string modelData
                        implicitWidth: label.implicitWidth + 24
                        implicitHeight: 34
                        buttonRadius: 12
                        colBackground: Appearance.m3colors.m3surfaceContainerHigh
                        onClicked: Config.options.sidebar.quickToggles.android.toggles = Array.from(root.toggles).concat([{type: modelData, size: 2, height: 1}])
                        contentItem: StyledText {
                            id: label
                            text: "+ " + modelData.replace(/([a-z])([A-Z])/g, "$1 $2")
                            font.pixelSize: 12
                        }
                    }
                }
            }
        }
        NotificationStatusButton {
            Layout.fillWidth: true
            buttonIcon: "notifications"
            buttonText: root.latestNotificationText
            marquee: Notifications.list.length > 0
            onClicked: root.openNotifications()
            StyledToolTip { text: Translation.tr("%1 notifications").arg(Notifications.list.length) }
        }
    }
}
