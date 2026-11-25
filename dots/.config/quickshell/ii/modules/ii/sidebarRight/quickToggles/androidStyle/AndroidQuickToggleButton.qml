import QtQuick
import "../TileGrid.js" as TileGrid
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
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
    Binding {
        target: root.toggleModel
        property: "pollingEnabled"
        when: root.toggleModel !== null
        value: root.visible && (root.Window.window?.visible ?? false)
        restoreMode: Binding.RestoreBindingOrValue
    }
    property string name: toggleModel?.name ?? ""
    readonly property string compactName: ({notifications: "Inbox", idleInhibitor: "Keep awake", onScreenKeyboard: "Keyboard", colorPicker: "Pick color", screenSnip: "Capture", antiFlashbang: "Anti-flash", tripleBuffer: "Buffer", darkMode: "Theme", directScanout: "Scanout", powerProfile: "Power", musicRecognition: "Identify", memoryCompact: "Compact", zramRecompress: "Recompress", zramWriteback: "Writeback", dropCaches: "Caches", vrr: "VRR"})[buttonData.type] ?? name
    readonly property string tileCategory: TileGrid.categoryOf(buttonData.type)
    readonly property color categoryAccent: tileCategory === "performance"
        ? (Appearance.m3colors.m3tertiary ?? Appearance.m3colors.m3primary)
        : tileCategory === "advanced"
            ? (Appearance.m3colors.m3error ?? Appearance.m3colors.m3primary)
            : tileCategory === "comfort"
                ? (Appearance.m3colors.m3secondary ?? Appearance.m3colors.m3primary)
                : Appearance.m3colors.m3primary
    readonly property color categoryToggledBg: tileCategory === "performance"
        ? (Appearance.m3colors.m3tertiaryContainer ?? Appearance.m3colors.m3primaryContainer)
        : tileCategory === "advanced"
            ? (Appearance.m3colors.m3errorContainer ?? Appearance.m3colors.m3primaryContainer)
            : tileCategory === "comfort"
                ? (Appearance.m3colors.m3secondaryContainer ?? Appearance.m3colors.m3primaryContainer)
                : Appearance.m3colors.m3primaryContainer
    readonly property color categoryToggledFg: tileCategory === "performance"
        ? (Appearance.m3colors.m3onTertiaryContainer ?? Appearance.m3colors.m3onPrimaryContainer)
        : tileCategory === "advanced"
            ? (Appearance.m3colors.m3onErrorContainer ?? Appearance.m3colors.m3onPrimaryContainer)
            : tileCategory === "comfort"
                ? (Appearance.m3colors.m3onSecondaryContainer ?? Appearance.m3colors.m3onPrimaryContainer)
                : Appearance.m3colors.m3onPrimaryContainer
    readonly property color categoryRestBg: tileCategory === "performance"
        ? ColorUtils.mix(Appearance.m3colors.m3surfaceContainerHigh, categoryToggledBg, 0.87)
        : tileCategory === "advanced"
            ? ColorUtils.mix(Appearance.m3colors.m3surfaceContainerHigh, categoryToggledBg, 0.90)
            : tileCategory === "comfort"
                ? (Appearance.m3colors.m3surfaceContainer ?? Appearance.m3colors.m3surfaceContainerHigh)
                : Appearance.m3colors.m3surfaceContainerHigh
    readonly property color categoryBorderColor: root.toggled
        ? ColorUtils.transparentize(categoryAccent, 0.50)
        : (root.mainActionRequiresHold
            ? ColorUtils.transparentize(Appearance.m3colors.m3error ?? categoryAccent, 0.58)
            : tileCategory === "performance"
                ? ColorUtils.transparentize(categoryAccent, 0.70)
                : tileCategory === "advanced"
                    ? ColorUtils.transparentize(categoryAccent, 0.74)
                    : tileCategory === "essentials"
                        ? ColorUtils.transparentize(categoryAccent, 0.82)
                        : ColorUtils.transparentize(Appearance.m3colors.m3outlineVariant ?? categoryAccent, 0.55))
    readonly property string holdBadgeText: root.mainActionRequiresHold
        ? Translation.tr("HOLD")
        : (root.altActionRequiresHold ? Translation.tr("R·HOLD") : "")
    property string statusText: toggleModel?.hasStatusText ? (toggleModel?.statusText || (toggled ? Translation.tr("Active") : Translation.tr("Inactive"))) : ""
    property string tooltipText: toggleModel?.tooltipText ?? ""
    property string buttonIcon: toggleModel?.icon ?? "close"
    property bool available: toggleModel?.available ?? true
    property var mainAction: toggleModel?.mainAction ?? null
    property bool altActionOnRightClick: toggleModel?.altActionOnRightClick ?? false
    property bool mainActionRequiresHold: toggleModel?.mainActionRequiresHold ?? false
    property bool altActionRequiresHold: toggleModel?.altActionRequiresHold ?? false
    property int mainHoldDurationMs: toggleModel?.mainHoldDurationMs ?? 950
    property int altHoldDurationMs: toggleModel?.altHoldDurationMs ?? 1100
    property string mainHoldLabel: toggleModel?.mainHoldLabel ?? ""
    property string altHoldLabel: toggleModel?.altHoldLabel ?? ""
    readonly property bool hasHoldGuard: root.mainActionRequiresHold || root.altActionRequiresHold
    property bool editMode: false
    function removeTile() {
        const type = root.buttonData.type;
        sizePopup.close();
        // Resolve by identity: moving and resizing may have reordered the model.
        Config.options.sidebar.quickToggles.android.toggles =
            TileGrid.snapshot(Config.options.sidebar.quickToggles.android.toggles, root.gridColumns).filter(tile => tile.type !== type);
    }
    onEditModeChanged: {
        if (!editMode) sizePopup.close();
        else holdOverlay.cancelHold(false);
    }
    readonly property bool splitAltAction: altAction && expandedSize && !altActionOnRightClick && !hasHoldGuard
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
    scale: holdOverlay.holding ? 0.975 : 1.0
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    bounce: false
    enableImplicitWidthAnimation: false
    enableImplicitHeightAnimation: false
    enabled: available || editMode
    padding: 8
    horizontalPadding: padding
    verticalPadding: padding
    buttonRadius: 18
    buttonRadiusPressed: 14
    colBackground: root.categoryRestBg
    colBackgroundHover: ColorUtils.mix(root.categoryRestBg, Appearance.m3colors.m3onSurface, 0.92)
    colBackgroundActive: ColorUtils.mix(root.categoryRestBg, Appearance.m3colors.m3onSurface, 0.86)
    colBackgroundToggled: root.categoryToggledBg
    colBackgroundToggledHover: ColorUtils.mix(colBackgroundToggled, root.categoryToggledFg, 0.92)
    colBackgroundToggledActive: ColorUtils.mix(colBackgroundToggled, root.categoryToggledFg, 0.88)
    property color colText: toggled ? root.categoryToggledFg : Appearance.m3colors.m3onSurface
    opacity: root.moving ? 0.45 : root.enabled ? 1 : 0.45
    Binding {
        target: root.mouseArea
        property: "enabled"
        value: !(root.hasHoldGuard && !root.editMode)
        restoreMode: Binding.RestoreBindingOrValue
    }
    onClicked: {
        if (editMode || hasHoldGuard) return;
        if (!altActionOnRightClick && expandedSize && altAction) altAction();
        else if (mainAction) mainAction();
    }
    // Subtle semantic category frame (defers to HoldToConfirmOverlay ring while holding)
    Rectangle {
        z: 1
        anchors.fill: parent
        radius: root.down ? root.buttonRadiusPressed : root.buttonRadius
        color: "transparent"
        visible: !(holdOverlay.holding || holdOverlay.showEarlyHint)
        border.width: 1
        border.color: root.categoryBorderColor
    }
    // Compact 1-col corner indicator dot for guarded hold tiles
    Rectangle {
        z: 3
        visible: !root.expandedSize && root.hasHoldGuard && !root.editMode && !holdOverlay.holding && !holdOverlay.showEarlyHint
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 8
        anchors.rightMargin: 8
        width: 6
        height: 6
        radius: 3
        color: root.toggled ? root.colText : Appearance.m3colors.m3error
        opacity: root.mainActionRequiresHold ? 0.95 : 0.65
    }
    contentItem: Item {
        RowLayout {
            anchors.centerIn: parent
            width: parent.width
            visible: root.expandedSize
            spacing: 8
            MouseArea {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 38
                acceptedButtons: root.splitAltAction ? Qt.LeftButton : Qt.NoButton
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.mainAction && !root.editMode) root.mainAction()
                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: root.toggled
                        ? ColorUtils.transparentize(root.colText, root.splitAltAction ? 0.86 : 0.90)
                        : ColorUtils.transparentize(root.categoryAccent, root.splitAltAction ? 0.82 : 0.87)
                    border.width: root.splitAltAction ? 1 : 0
                    border.color: root.toggled
                        ? ColorUtils.transparentize(root.colText, 0.72)
                        : ColorUtils.transparentize(root.categoryAccent, 0.70)
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.buttonIcon
                        iconSize: 22
                        color: (holdOverlay.holding || holdOverlay.showEarlyHint)
                            ? Appearance.m3colors.m3error
                            : (root.toggled ? root.colText : root.categoryAccent)
                        fill: (root.toggled || holdOverlay.holding) ? 1 : 0
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    StyledText {
                        Layout.fillWidth: true
                        text: root.name
                        color: root.colText
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        wrapMode: root.holdBadgeText.length > 0 ? Text.NoWrap : Text.WordWrap
                        maximumLineCount: root.holdBadgeText.length > 0 ? 1 : 2
                    }
                    Rectangle {
                        objectName: "tileHoldBadge-" + root.buttonData.type
                        visible: root.holdBadgeText.length > 0 && !root.editMode && !holdOverlay.holding && !holdOverlay.showEarlyHint
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: holdBadgeLabel.implicitWidth + 8
                        implicitHeight: 15
                        radius: 7.5
                        color: root.toggled
                            ? ColorUtils.transparentize(root.colText, 0.84)
                            : ColorUtils.transparentize(Appearance.m3colors.m3error, root.mainActionRequiresHold ? 0.82 : 0.89)
                        border.width: 1
                        border.color: root.toggled
                            ? ColorUtils.transparentize(root.colText, 0.60)
                            : ColorUtils.transparentize(Appearance.m3colors.m3error, root.mainActionRequiresHold ? 0.45 : 0.68)
                        StyledText {
                            id: holdBadgeLabel
                            anchors.centerIn: parent
                            text: root.holdBadgeText
                            font.pixelSize: 8
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.4
                            color: root.toggled ? root.colText : Appearance.m3colors.m3error
                            opacity: root.mainActionRequiresHold ? 0.98 : 0.85
                        }
                    }
                }
                StyledText {
                    objectName: "tileStatus-" + root.buttonData.type
                    Layout.fillWidth: true
                    visible: root.statusText.length > 0 || holdOverlay.holding || holdOverlay.showEarlyHint
                    text: holdOverlay.holding
                        ? ((holdOverlay.holdLabel || root.name) + " · " + Math.round(holdOverlay.progress * 100) + "%")
                        : holdOverlay.showEarlyHint
                            ? holdOverlay.earlyHintText
                            : root.statusText
                    font.pixelSize: 11
                    font.weight: (holdOverlay.holding || holdOverlay.showEarlyHint) ? Font.DemiBold : Font.Normal
                    color: (holdOverlay.holding || holdOverlay.showEarlyHint) ? Appearance.m3colors.m3error : root.colText
                    opacity: (holdOverlay.holding || holdOverlay.showEarlyHint) ? 1.0 : 0.78
                    elide: Text.ElideRight
                }
            }
        }
        ColumnLayout {
            anchors.centerIn: parent
            width: parent.width
            visible: !root.expandedSize
            spacing: 4
            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: root.buttonIcon
                iconSize: 23
                color: (holdOverlay.holding || holdOverlay.showEarlyHint)
                    ? Appearance.m3colors.m3error
                    : (root.toggled ? root.colText : root.categoryAccent)
                fill: (root.toggled || holdOverlay.holding) ? 1 : 0
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.width >= 64
                text: holdOverlay.holding
                    ? (Math.round(holdOverlay.progress * 100) + "%")
                    : holdOverlay.showEarlyHint
                        ? Translation.tr("Hold")
                        : root.compactName
                font.pixelSize: 11
                font.weight: (holdOverlay.holding || holdOverlay.showEarlyHint) ? Font.DemiBold : Font.Normal
                color: (holdOverlay.holding || holdOverlay.showEarlyHint) ? Appearance.m3colors.m3error : root.colText
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
    }
    HoldToConfirmOverlay {
        id: holdOverlay
        objectName: "tileHoldOverlay-" + root.buttonData.type
        z: 2
        cornerRadius: root.down ? root.buttonRadiusPressed : root.buttonRadius
        accentColor: Appearance.m3colors.m3error
        showIdleGuard: root.hasHoldGuard && !root.editMode
    }
    // Guarded press-and-hold interaction for risky left/right actions.
    MouseArea {
        id: guardedInteraction
        objectName: "tileGuardedArea-" + root.buttonData.type
        z: 4
        anchors.fill: parent
        visible: root.hasHoldGuard && !root.editMode
        enabled: root.available && !root.editMode
        hoverEnabled: true
        preventStealing: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        property int activeButton: Qt.NoButton

        onPressed: event => {
            activeButton = event.button;
            if (event.button === Qt.LeftButton) {
                root.down = true;
                if (root.mainActionRequiresHold) {
                    holdOverlay.startHold(
                        root.mainAction,
                        root.mainHoldDurationMs,
                        root.mainHoldLabel || ("Hold · " + root.name),
                        Translation.tr("Hold to confirm"),
                        Appearance.m3colors.m3error
                    );
                }
            } else if (event.button === Qt.RightButton) {
                if (!root.altAction) {
                    activeButton = Qt.NoButton;
                    return;
                }
                root.down = true;
                if (root.altActionRequiresHold) {
                    holdOverlay.startHold(
                        root.altAction,
                        root.altHoldDurationMs,
                        root.altHoldLabel || ("Hold · " + root.name),
                        Translation.tr("Hold right-click"),
                        Appearance.m3colors.m3error
                    );
                }
            }
        }
        onPositionChanged: {
            if (holdOverlay.holding && !containsMouse) {
                root.down = false;
                activeButton = Qt.NoButton;
                holdOverlay.cancelHold(false);
            }
        }
        onReleased: event => {
            const btn = activeButton;
            activeButton = Qt.NoButton;
            root.down = false;
            if (holdOverlay.holding) {
                holdOverlay.cancelHold(containsMouse);
                return;
            }
            if (holdOverlay.consumeCompleted()) return;
            if (!containsMouse) return;
            if (btn === Qt.LeftButton && !root.mainActionRequiresHold) {
                if (!root.altActionOnRightClick && root.expandedSize && root.altAction && !root.altActionRequiresHold)
                    root.altAction();
                else if (root.mainAction)
                    root.mainAction();
            } else if (btn === Qt.RightButton && !root.altActionRequiresHold) {
                if (root.altAction) root.altAction();
            }
        }
        onCanceled: {
            root.down = false;
            activeButton = Qt.NoButton;
            holdOverlay.cancelHold(false);
        }
    }
    // Keep the tile's explicit right-click action outside edit mode (for unguarded tiles).
    MouseArea {
        anchors.fill: parent
        visible: root.altActionOnRightClick && !root.editMode && !root.hasHoldGuard
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
