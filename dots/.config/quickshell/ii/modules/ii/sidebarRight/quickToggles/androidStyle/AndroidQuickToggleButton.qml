import QtQuick
import "../TileGrid.js" as TileGrid
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.functions
import qs.modules.common.widgets

GroupButton {
    id: root
    required property int buttonIndex
    required property var buttonData
    required property bool expandedSize
    required property real baseCellWidth
    required property real baseCellHeight
    required property real cellSpacing
    required property int cellSize
    property int cellRows: 1
    property int gridColumns: 7
    signal openMenu()
    signal tileResized(int index, int width, int height)
    signal tileMoved(int index, real x, real y)
    property QuickToggleModel toggleModel
    property string name: toggleModel?.name ?? ""
    readonly property string compactName: ({notifications: "Inbox", idleInhibitor: "Keep awake", onScreenKeyboard: "Keyboard", colorPicker: "Pick color", screenSnip: "Capture", antiFlashbang: "Anti-flash", tripleBuffer: "Buffer", darkMode: "Theme", directScanout: "Scanout", powerProfile: "Power", musicRecognition: "Identify", memoryCompact: "Compact", zramRecompress: "Recompress", zramWriteback: "Writeback", dropCaches: "Caches"})[buttonData.type] ?? name
    property string statusText: toggleModel?.hasStatusText ? (toggleModel?.statusText || (toggled ? Translation.tr("Active") : Translation.tr("Inactive"))) : ""
    property string tooltipText: toggleModel?.tooltipText ?? ""
    property string buttonIcon: toggleModel?.icon ?? "close"
    property bool available: toggleModel?.available ?? true
    property var mainAction: toggleModel?.mainAction ?? null
    property bool altActionOnRightClick: toggleModel?.altActionOnRightClick ?? false
    property bool editMode: false
    function removeTile() {
        const type = root.buttonData.type;
        sizePopup.close();
        // Resolve by identity: moving and resizing may have reordered the model.
        Config.options.sidebar.quickToggles.android.toggles =
            TileGrid.snapshot(Config.options.sidebar.quickToggles.android.toggles, root.gridColumns).filter(tile => tile.type !== type);
    }
    onEditModeChanged: if (!editMode) sizePopup.close()
    readonly property bool splitAltAction: altAction && expandedSize && !altActionOnRightClick
    property bool moving: false
    property bool resizing: false
    property real dragX: 0
    property real dragY: 0
    property int previewWidth: cellSize
    property int previewHeight: cellRows
    objectName: "controlTile-" + buttonData.type
    toggled: toggleModel?.toggled ?? false
    altAction: toggleModel?.hasMenu ? (() => root.openMenu()) : (toggleModel?.altAction ?? null)
    baseWidth: baseCellWidth * cellSize + cellSpacing * (cellSize - 1)
    baseHeight: baseCellHeight * cellRows + cellSpacing * (cellRows - 1)
    width: baseWidth
    height: baseHeight
    bounce: false
    enableImplicitWidthAnimation: false
    enableImplicitHeightAnimation: false
    enabled: available || editMode
    padding: 8
    horizontalPadding: padding
    verticalPadding: padding
    buttonRadius: 18
    buttonRadiusPressed: 14
    colBackground: Appearance.m3colors.m3surfaceContainerHigh
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colBackgroundActive: Appearance.colors.colLayer2Active
    colBackgroundToggled: Appearance.m3colors.m3primaryContainer
    colBackgroundToggledHover: ColorUtils.mix(colBackgroundToggled, Appearance.m3colors.m3onPrimaryContainer, 0.08)
    colBackgroundToggledActive: ColorUtils.mix(colBackgroundToggled, Appearance.m3colors.m3onPrimaryContainer, 0.12)
    property color colText: toggled ? Appearance.m3colors.m3onPrimaryContainer : Appearance.m3colors.m3onSurface
    opacity: root.moving ? 0.45 : root.enabled ? 1 : 0.45
    onClicked: {
        if (editMode) return;
        if (!altActionOnRightClick && expandedSize && altAction) altAction();
        else if (mainAction) mainAction();
    }
    contentItem: Item {
        RowLayout {
            anchors.centerIn: parent
            width: parent.width
            visible: root.expandedSize
            spacing: 8
            MouseArea {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 40
                acceptedButtons: root.splitAltAction ? Qt.LeftButton : Qt.NoButton
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.mainAction && !root.editMode) root.mainAction()
                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: root.splitAltAction ? ColorUtils.transparentize(root.colText, 0.92) : "transparent"
                    MaterialSymbol { anchors.centerIn: parent; text: root.buttonIcon; iconSize: 24; color: root.colText; fill: root.toggled ? 1 : 0 }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                StyledText {
                    Layout.fillWidth: true
                    text: root.name
                    color: root.colText
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.statusText.length > 0
                    text: root.statusText
                    font.pixelSize: 11
                    color: root.colText
                    opacity: 0.75
                    elide: Text.ElideRight
                }
            }
        }
        ColumnLayout {
            anchors.centerIn: parent
            width: parent.width
            visible: !root.expandedSize
            spacing: 4
            MaterialSymbol { Layout.alignment: Qt.AlignHCenter; text: root.buttonIcon; iconSize: 24; color: root.colText; fill: root.toggled ? 1 : 0 }
            StyledText {
                Layout.fillWidth: true
                visible: root.width >= 64
                text: root.compactName
                font.pixelSize: 11
                color: root.colText
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
    }
    // Keep the tile's explicit right-click action outside edit mode.
    MouseArea {
        anchors.fill: parent
        visible: root.altActionOnRightClick && !root.editMode
        acceptedButtons: Qt.RightButton
        onClicked: if (root.altAction) root.altAction()
    }
    Rectangle {
        parent: root.parent
        visible: root.moving || root.resizing
        z: 100
        x: root.x + (root.moving ? root.dragX : 0)
        y: root.y + (root.moving ? root.dragY : 0)
        width: root.resizing ? root.previewWidth * (root.baseCellWidth + root.cellSpacing) - root.cellSpacing : root.width
        height: root.resizing ? root.previewHeight * (root.baseCellHeight + root.cellSpacing) - root.cellSpacing : root.height
        radius: 18
        color: ColorUtils.transparentize(Appearance.m3colors.m3primary, 0.8)
        border.width: 2
        border.color: Appearance.m3colors.m3primary
        StyledText {
            anchors.centerIn: parent
            text: root.resizing ? root.previewWidth + " × " + root.previewHeight : root.name
            color: Appearance.m3colors.m3onSurface
        }
    }
    MouseArea {
        id: editInteraction
        objectName: "tileMove-" + root.buttonData.type
        visible: root.editMode
        anchors.fill: parent
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: true
        property point startPoint
        onPressed: event => {
            if (event.button === Qt.RightButton) { sizePopup.open(); return; }
            startPoint = mapToItem(root.parent, event.x, event.y);
            root.dragX = 0; root.dragY = 0;
        }
        onPositionChanged: event => {
            if (!(pressedButtons & Qt.LeftButton)) return;
            const point = mapToItem(root.parent, event.x, event.y);
            root.dragX = point.x - startPoint.x;
            root.dragY = point.y - startPoint.y;
            root.moving = Math.abs(root.dragX) + Math.abs(root.dragY) > 8;
        }
        onReleased: event => {
            if (event.button !== Qt.LeftButton) return;
            const moved = root.moving;
            const x = root.x + root.dragX; const y = root.y + root.dragY;
            root.moving = false;
            if (moved) root.tileMoved(root.buttonIndex, x, y);
            else sizePopup.open();
        }
        onCanceled: root.moving = false
        // Let the surrounding Flickable scroll; wheel input must never edit layout.
        onWheel: event => event.accepted = false
    }
    MouseArea {
        objectName: "tileDelete-" + root.buttonData.type
        visible: root.editMode
        anchors.top: parent.top
        anchors.right: parent.right
        width: 28
        height: 28
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        onClicked: root.removeTile()
        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: 12
            color: Appearance.m3colors.m3errorContainer
            MaterialSymbol { anchors.centerIn: parent; text: "close"; iconSize: 18; color: Appearance.m3colors.m3onErrorContainer }
        }
    }

    Rectangle {
        visible: root.editMode
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 5
        width: sizeLabel.implicitWidth + 10
        height: 18
        radius: 6
        color: Appearance.m3colors.m3surfaceContainerHighest
        StyledText { id: sizeLabel; anchors.centerIn: parent; text: root.cellSize + " × " + root.cellRows; font.pixelSize: 10 }
    }
    MouseArea {
        id: resizeHandle
        objectName: "tileResize-" + root.buttonData.type
        visible: root.editMode
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: 26
        height: 26
        cursorShape: Qt.SizeFDiagCursor
        preventStealing: true
        property point startPoint
        onPressed: event => {
            startPoint = mapToItem(root.parent, event.x, event.y);
            root.previewWidth = root.cellSize; root.previewHeight = root.cellRows;
            root.resizing = true;
        }
        onPositionChanged: event => {
            if (!pressed) return;
            const point = mapToItem(root.parent, event.x, event.y);
            root.previewWidth = Math.max(1, Math.min(root.gridColumns, root.cellSize + Math.round((point.x - startPoint.x) / (root.baseCellWidth + root.cellSpacing))));
            root.previewHeight = Math.max(1, Math.min(7, root.cellRows + Math.round((point.y - startPoint.y) / (root.baseCellHeight + root.cellSpacing))));
        }
        onReleased: {
            root.resizing = false;
            root.tileResized(root.buttonIndex, root.previewWidth, root.previewHeight);
        }
        onCanceled: root.resizing = false
        MaterialSymbol { anchors.centerIn: parent; text: "open_in_full"; iconSize: 15; color: root.colText }
    }
    Popup {
        id: sizePopup
        objectName: "tileSizePopup-" + root.buttonData.type
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent ? Math.max(0, parent.width - 24) : 0,
            Math.max(250, root.gridColumns * 31 + 32))
        padding: 16
        modal: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { radius: 18; color: Appearance.m3colors.m3surfaceContainerHigh; border.width: 1; border.color: Appearance.m3colors.m3outlineVariant }
        contentItem: ColumnLayout {
            spacing: 10
            StyledText { Layout.fillWidth: true; text: root.name; font.weight: Font.Medium; elide: Text.ElideRight }
            StyledText { text: "Choose width × height"; font.pixelSize: 12; color: Appearance.m3colors.m3onSurfaceVariant }
            Grid {
                id: sizeGrid
                objectName: "tileSizeGrid-" + root.buttonData.type
                columns: root.gridColumns
                spacing: 3
                property int selectedColumn: root.cellSize
                property int selectedRow: root.cellRows
                Repeater {
                    model: root.gridColumns * 7
                    delegate: Rectangle {
                        required property int index
                        readonly property int column: index % root.gridColumns + 1
                        readonly property int row: Math.floor(index / root.gridColumns) + 1
                        width: 28
                        height: 24
                        radius: 4
                        opacity: column > root.gridColumns ? 0.25 : 1
                        color: column <= sizeGrid.selectedColumn && row <= sizeGrid.selectedRow ? Appearance.m3colors.m3primary : Appearance.m3colors.m3surfaceContainerHighest
                        MouseArea {
                            anchors.fill: parent
                            enabled: parent.column <= root.gridColumns
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: { sizeGrid.selectedColumn = parent.column; sizeGrid.selectedRow = parent.row; }
                            onClicked: {
                                const index = root.buttonIndex;
                                const width = parent.column; const height = parent.row;
                                sizePopup.close();
                                root.tileResized(index, width, height);
                            }
                        }
                    }
                }
            }
            StyledText { text: sizeGrid.selectedColumn + " × " + sizeGrid.selectedRow + " cells"; font.pixelSize: 12 }
            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 34
                objectName: "tileRemoveMenu-" + root.buttonData.type
                buttonText: "Remove tile"
                onClicked: root.removeTile()
            }
        }
    }
    StyledToolTip {
        extraVisibleCondition: !root.editMode
        text: root.tooltipText || (root.name + (root.statusText ? " · " + root.statusText : ""))
    }
}
