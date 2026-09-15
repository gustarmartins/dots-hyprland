pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Item {
    id: root
    required property var screen
    readonly property int gridColumns: Math.max(1, Config.options.overview.columns || 8)
    readonly property int gridRows: Math.max(1, Config.options.overview.rows || 4)
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen) ?? Hyprland.focusedMonitor
    readonly property var toplevels: ToplevelManager.toplevels
    // Clamp to avoid lock-screen temp workspace (2147483647 - N) leaking into UI
    readonly property int effectiveActiveWorkspaceId: Math.max(1, Math.min(100, monitor?.activeWorkspace?.id ?? 1))
    readonly property int workspacesShown: root.gridRows * root.gridColumns
    readonly property int workspaceGroup: Math.floor((effectiveActiveWorkspaceId - 1) / workspacesShown)
    property bool monitorIsFocused: (Hyprland.focusedMonitor?.name == monitor?.name)
    property var windows: HyprlandData.windowList
    property var windowByAddress: HyprlandData.windowByAddress
    property var windowAddresses: HyprlandData.addresses
    property var monitorData: HyprlandData.monitors.find(m => m.id === root.monitor?.id)
    readonly property real displayWidth: Math.max(1, (monitor?.width || screen?.width || 1920) / (monitor?.scale || 1))
    readonly property real displayHeight: Math.max(1, (monitor?.height || screen?.height || 1080) / (monitor?.scale || 1))
    property real scale: Math.max(0.01, Math.min(Config.options.overview.scale || 0.12,
        (displayWidth - 88 - (root.gridColumns - 1) * workspaceSpacing) / (displayWidth * root.gridColumns),
        (displayHeight - 220 - (root.gridRows - 1) * workspaceSpacing) / (displayHeight * root.gridRows)))
    readonly property var workspaceCounts: {
        const result = {};
        for (const window of root.windows) {
            const id = window.workspace?.id;
            if (id > 0) result[id] = (result[id] ?? 0) + 1;
        }
        return result;
    }
    property real reveal: 0
    opacity: reveal
    transform: Translate { y: (1 - root.reveal) * 18 }
    NumberAnimation on reveal { from: 0; to: 1; duration: 320; easing.type: Easing.OutCubic; running: true }
    property color activeBorderColor: Appearance.colors.colSecondary

    readonly property real usableWidth: Math.max(1, displayWidth - ((monitorData?.reserved?.[0] ?? 0) + (monitorData?.reserved?.[2] ?? 0)) / (monitor?.scale ?? 1))
    readonly property real usableHeight: Math.max(1, displayHeight - ((monitorData?.reserved?.[1] ?? 0) + (monitorData?.reserved?.[3] ?? 0)) / (monitor?.scale ?? 1))
    property real workspaceImplicitWidth: usableWidth * root.scale
    property real workspaceImplicitHeight: usableHeight * root.scale
    property real largeWorkspaceRadius: 16
    property real smallWorkspaceRadius: 16

    property real workspaceNumberMargin: 80
    property real workspaceNumberSize: 250 * (monitor?.scale ?? 1)
    property int workspaceZ: 0
    property int windowZ: 1
    property int windowDraggingZ: 99999
    property real workspaceSpacing: 10

    property int draggingFromWorkspace: -1
    property int draggingTargetWorkspace: -1

    implicitWidth: overviewBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
    implicitHeight: overviewBackground.implicitHeight + Appearance.sizes.elevationMargin * 2

    property Component windowComponent: OverviewWindow {}
    property list<OverviewWindow> windowWidgets: []
    
    function getWsRow(ws) {
        // 1-indexed workspace, 0-indexed row
        var normalRow = Math.floor((ws - 1) / root.gridColumns) % root.gridRows;
        return (Config.options.overview.orderBottomUp ? root.gridRows - normalRow - 1 : normalRow);
    }
    function getWsColumn(ws) {
        // 1-indexed workspace, 0-indexed column
        var normalCol = (ws - 1) % root.gridColumns;
        return (Config.options.overview.orderRightLeft ? root.gridColumns - normalCol - 1 : normalCol);
    }
    function getWsInCell(ri, ci) {
        // 1-indexed workspace, 0-indexed row and column index
        return (Config.options.overview.orderBottomUp ? root.gridRows - ri - 1 : ri) * root.gridColumns + (Config.options.overview.orderRightLeft ? root.gridColumns - ci - 1 : ci) + 1
    }

    StyledRectangularShadow {
        target: overviewBackground
    }
    Rectangle { // Background
        id: overviewBackground
        property real padding: 18
        property real headingHeight: 48
        property real footerHeight: 26
        anchors.fill: parent
        anchors.margins: Appearance.sizes.elevationMargin

        implicitWidth: workspaceColumnLayout.implicitWidth + padding * 2
        implicitHeight: workspaceColumnLayout.implicitHeight + padding * 2 + headingHeight + footerHeight
        radius: root.largeWorkspaceRadius + padding
        color: Qt.alpha(Appearance.m3colors.m3surfaceContainerLow, 0.9)
        border.width: 1
        border.color: Qt.alpha(Appearance.m3colors.m3outlineVariant, 0.5)

        RowLayout {
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: overviewBackground.padding }
            StyledText { text: "Workspaces"; font.pixelSize: 22; font.weight: Font.Medium; color: Appearance.m3colors.m3onSurface }
            Item { Layout.fillWidth: true }
            StyledText { text: "Current · " + root.effectiveActiveWorkspaceId; font.pixelSize: 13; color: Appearance.m3colors.m3primary }
        }
        StyledText {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: overviewBackground.padding }
            elide: Text.ElideRight
            text: "Select a window or workspace   ·   Drag to move   ·   Esc to close"
            font.pixelSize: 12
            color: Appearance.m3colors.m3onSurfaceVariant
        }

        Column { // Workspaces
            id: workspaceColumnLayout

            z: root.workspaceZ
            anchors { left: parent.left; top: parent.top; leftMargin: overviewBackground.padding; topMargin: overviewBackground.padding + overviewBackground.headingHeight }
            spacing: workspaceSpacing
            
            Repeater {
                model: root.gridRows
                delegate: Row {
                    id: row
                    required property int index
                    spacing: workspaceSpacing

                    Repeater { // Workspace repeater
                        model: root.gridColumns
                        Rectangle { // Workspace
                            id: workspace
                            required property int index
                            property int colIndex: index
                            property int workspaceValue: root.workspaceGroup * root.workspacesShown + getWsInCell(row.index, colIndex)
                            readonly property int windowCount: root.workspaceCounts[workspaceValue] ?? 0
                            property color defaultWorkspaceColor: Qt.alpha(Appearance.m3colors.m3surfaceContainerHigh, windowCount > 0 ? 0.78 : 0.32)
                            property color hoveredWorkspaceColor: ColorUtils.mix(defaultWorkspaceColor, Appearance.colors.colLayer1Hover, 0.1)
                            property color hoveredBorderColor: Appearance.colors.colLayer2Hover
                            property bool hoveredWhileDragging: false

                            implicitWidth: root.workspaceImplicitWidth
                            implicitHeight: root.workspaceImplicitHeight
                            color: hoveredWhileDragging || workspaceArea.containsMouse ? hoveredWorkspaceColor : defaultWorkspaceColor
                            Behavior on color { ColorAnimation { duration: 160 } }
                            property bool workspaceAtLeft: colIndex === 0
                            property bool workspaceAtRight: colIndex === root.gridColumns - 1
                            property bool workspaceAtTop: row.index === 0
                            property bool workspaceAtBottom: row.index === root.gridRows - 1
                            topLeftRadius: (workspaceAtLeft && workspaceAtTop) ? root.largeWorkspaceRadius : root.smallWorkspaceRadius
                            topRightRadius: (workspaceAtRight && workspaceAtTop) ? root.largeWorkspaceRadius : root.smallWorkspaceRadius
                            bottomLeftRadius: (workspaceAtLeft && workspaceAtBottom) ? root.largeWorkspaceRadius : root.smallWorkspaceRadius
                            bottomRightRadius: (workspaceAtRight && workspaceAtBottom) ? root.largeWorkspaceRadius : root.smallWorkspaceRadius
                            border.width: 2
                            border.color: hoveredWhileDragging || workspaceArea.containsMouse ? Qt.alpha(Appearance.m3colors.m3primary, 0.65) : Qt.alpha(Appearance.m3colors.m3outlineVariant, 0.25)

                            StyledText {
                                anchors.centerIn: parent
                                text: workspace.workspaceValue
                                visible: workspace.windowCount === 0
                                font {
                                    pixelSize: Math.round(Math.max(22, 210 * (root.scale || 0.12)))
                                    weight: Font.DemiBold
                                    family: Appearance.font.family.expressive
                                }
                                color: Qt.alpha(Appearance.m3colors.m3onSurfaceVariant, 0.5)
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            MouseArea {
                                id: workspaceArea
                                hoverEnabled: true
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                onPressed: {
                                    if (root.draggingTargetWorkspace === -1) {
                                        GlobalStates.overviewOpen = false
                                        Hyprland.dispatch(`hl.dsp.focus({ workspace = ${workspace.workspaceValue} })`)
                                    }
                                }
                            }

                            DropArea {
                                anchors.fill: parent
                                onEntered: {
                                    root.draggingTargetWorkspace = workspace.workspaceValue
                                    if (root.draggingFromWorkspace == root.draggingTargetWorkspace) return;
                                    hoveredWhileDragging = true
                                }
                                onExited: {
                                    hoveredWhileDragging = false
                                    if (root.draggingTargetWorkspace == workspace.workspaceValue) root.draggingTargetWorkspace = -1
                                }
                            }

                        }
                    }
                }
            }
        }

        Item { // Windows & focused workspace indicator
            id: windowSpace
            anchors { left: parent.left; top: parent.top; leftMargin: overviewBackground.padding; topMargin: overviewBackground.padding + overviewBackground.headingHeight }
            implicitWidth: workspaceColumnLayout.implicitWidth
            implicitHeight: workspaceColumnLayout.implicitHeight

            Repeater { // Window repeater
                model: ScriptModel {
                    values: {
                        // console.log(JSON.stringify(ToplevelManager.toplevels.values.map(t => t), null, 2))
                        return ToplevelManager.toplevels.values.filter((toplevel) => {
                            const address = `0x${toplevel.HyprlandToplevel?.address}`
                            var win = windowByAddress[address]
                            const inWorkspaceGroup = (root.workspaceGroup * root.workspacesShown < win?.workspace?.id && win?.workspace?.id <= (root.workspaceGroup + 1) * root.workspacesShown)
                            return inWorkspaceGroup;
                        })
                    }
                }
                delegate: OverviewWindow {
                    id: window
                    required property var modelData
                    property int monitorId: windowData?.monitor
                    property var monitor: HyprlandData.monitors.find(m => m.id == monitorId)
                    property var address: `0x${modelData.HyprlandToplevel.address}`
                    toplevel: modelData
                    monitorData: this.monitor
                    scale: root.scale
                    widgetMonitor: HyprlandData.monitors.find(m => m.id == root.monitor.id)
                    windowData: windowByAddress[address]

                    property bool atInitPosition: (initX == x && initY == y)

                    // Offset on the canvas
                    property int workspaceColIndex: getWsColumn(windowData?.workspace.id)
                    property int workspaceRowIndex: getWsRow(windowData?.workspace.id)
                    xOffset: (root.workspaceImplicitWidth + workspaceSpacing) * workspaceColIndex
                    yOffset: (root.workspaceImplicitHeight + workspaceSpacing) * workspaceRowIndex
                    property real xWithinWorkspaceWidget: Math.max((windowData?.at[0] - (monitor?.x ?? 0) - monitorData?.reserved[0]) * root.scale, 0)
                    property real yWithinWorkspaceWidget: Math.max((windowData?.at[1] - (monitor?.y ?? 0) - monitorData?.reserved[1]) * root.scale, 0)

                    // Radius
                    property real minRadius: Appearance.rounding.small
                    property bool workspaceAtLeft: workspaceColIndex === 0
                    property bool workspaceAtRight: workspaceColIndex === root.gridColumns - 1
                    property bool workspaceAtTop: workspaceRowIndex === 0
                    property bool workspaceAtBottom: workspaceRowIndex === root.gridRows - 1
                    property bool workspaceAtTopLeft: (workspaceAtLeft && workspaceAtTop) 
                    property bool workspaceAtTopRight: (workspaceAtRight && workspaceAtTop) 
                    property bool workspaceAtBottomLeft: (workspaceAtLeft && workspaceAtBottom) 
                    property bool workspaceAtBottomRight: (workspaceAtRight && workspaceAtBottom) 
                    property real distanceFromLeftEdge: xWithinWorkspaceWidget
                    property real distanceFromRightEdge: root.workspaceImplicitWidth - (xWithinWorkspaceWidget + targetWindowWidth)
                    property real distanceFromTopEdge: yWithinWorkspaceWidget
                    property real distanceFromBottomEdge: root.workspaceImplicitHeight - (yWithinWorkspaceWidget + targetWindowHeight)
                    property real distanceFromTopLeftCorner: Math.max(distanceFromLeftEdge, distanceFromTopEdge)
                    property real distanceFromTopRightCorner: Math.max(distanceFromRightEdge, distanceFromTopEdge)
                    property real distanceFromBottomLeftCorner: Math.max(distanceFromLeftEdge, distanceFromBottomEdge)
                    property real distanceFromBottomRightCorner: Math.max(distanceFromRightEdge, distanceFromBottomEdge)
                    topLeftRadius: Math.max((workspaceAtTopLeft ? root.largeWorkspaceRadius : root.smallWorkspaceRadius) - distanceFromTopLeftCorner, minRadius)
                    topRightRadius: Math.max((workspaceAtTopRight ? root.largeWorkspaceRadius : root.smallWorkspaceRadius) - distanceFromTopRightCorner, minRadius)
                    bottomLeftRadius: Math.max((workspaceAtBottomLeft ? root.largeWorkspaceRadius : root.smallWorkspaceRadius) - distanceFromBottomLeftCorner, minRadius)
                    bottomRightRadius: Math.max((workspaceAtBottomRight ? root.largeWorkspaceRadius : root.smallWorkspaceRadius) - distanceFromBottomRightCorner, minRadius)

                    Timer {
                        id: updateWindowPosition
                        interval: Config.options.hacks.arbitraryRaceConditionDelay
                        repeat: false
                        running: false
                        onTriggered: {
                            window.x = Math.round(xWithinWorkspaceWidget + xOffset)
                            window.y = Math.round(yWithinWorkspaceWidget + yOffset)
                        }
                    }

                    z: Drag.active ? root.windowDraggingZ : (root.windowZ + windowData?.floating + windowData?.fullscreen * 2)
                    Drag.hotSpot.x: width / 2
                    Drag.hotSpot.y: height / 2
                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: hovered = true // For hover color change
                        onExited: hovered = false // For hover color change
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        drag.target: parent
                        onPressed: (mouse) => {
                            root.draggingFromWorkspace = windowData?.workspace.id
                            window.pressed = true
                            window.Drag.active = true
                            window.Drag.source = window
                            window.Drag.hotSpot.x = mouse.x
                            window.Drag.hotSpot.y = mouse.y
                            // console.log(`[OverviewWindow] Dragging window ${windowData?.address} from position (${window.x}, ${window.y})`)
                        }
                        onReleased: {
                            const targetWorkspace = root.draggingTargetWorkspace
                            window.pressed = false
                            window.Drag.active = false
                            root.draggingFromWorkspace = -1
                            if (targetWorkspace !== -1 && targetWorkspace !== windowData?.workspace.id) {
                                Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${targetWorkspace}, follow = false, window = "address:${window.windowData?.address}" })`)
                                updateWindowPosition.restart()
                            }
                            else {
                                if (!window.windowData.floating) {
                                    updateWindowPosition.restart()
                                    return
                                }
                                const percentageX = (window.x - xOffset) / root.workspaceImplicitWidth
                                const percentageY = (window.y - yOffset) / root.workspaceImplicitHeight
                                Hyprland.dispatch(`hl.dsp.window.move({ x = "${percentageX * root.screen.width}", y = "${percentageY * root.screen.height}", window = "address:${window.windowData?.address}" })`)
                            }
                        }
                        onClicked: (event) => {
                            if (!windowData) return;

                            if (event.button === Qt.LeftButton) {
                                GlobalStates.overviewOpen = false
                                Hyprland.dispatch(`hl.dsp.focus({window = "address:${windowData.address}"})`)
                                event.accepted = true
                            } else if (event.button === Qt.MiddleButton) {
                                Hyprland.dispatch(`hl.dsp.window.close({window = "address:${windowData.address}"})`)
                                event.accepted = true
                            }
                        }

                        StyledToolTip {
                            extraVisibleCondition: false
                            alternativeVisibleCondition: dragArea.containsMouse && !window.Drag.active
                            text: `${windowData?.title}\n[${windowData?.class}] ${windowData?.xwayland ? "[XWayland] " : ""}`
                        }
                    }
                }
            }

            Repeater {
                model: root.workspacesShown
                delegate: Rectangle {
                    required property int index
                    readonly property int ws: root.workspaceGroup * root.workspacesShown + index + 1
                    readonly property int count: root.workspaceCounts[ws] ?? 0
                    visible: count > 0
                    x: (root.workspaceImplicitWidth + root.workspaceSpacing) * root.getWsColumn(ws) + 8
                    y: (root.workspaceImplicitHeight + root.workspaceSpacing) * root.getWsRow(ws) + root.workspaceImplicitHeight - 28
                    width: Math.min(caption.implicitWidth + 16, root.workspaceImplicitWidth - 16)
                    height: 22
                    radius: 11
                    z: root.windowZ + 5
                    color: Qt.alpha(Appearance.m3colors.m3surfaceContainerLowest, 0.9)
                    StyledText {
                        id: caption
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                        verticalAlignment: Text.AlignVCenter
                        text: ws + " · " + count + (count === 1 ? " window" : " windows")
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        color: Appearance.m3colors.m3onSurface
                    }
                }
            }

            Rectangle { // Focused workspace indicator
                id: focusedWorkspaceIndicator
                property int rowIndex: getWsRow(root.effectiveActiveWorkspaceId)
                property int colIndex: getWsColumn(root.effectiveActiveWorkspaceId)
                x: (root.workspaceImplicitWidth + workspaceSpacing) * colIndex
                y: (root.workspaceImplicitHeight + workspaceSpacing) * rowIndex
                z: root.windowZ
                width: root.workspaceImplicitWidth
                height: root.workspaceImplicitHeight
                color: "transparent"
                property bool workspaceAtLeft: colIndex === 0
                property bool workspaceAtRight: colIndex === root.gridColumns - 1
                property bool workspaceAtTop: rowIndex === 0
                property bool workspaceAtBottom: rowIndex === root.gridRows - 1
                topLeftRadius: (workspaceAtLeft && workspaceAtTop) ? root.largeWorkspaceRadius : root.smallWorkspaceRadius
                topRightRadius: (workspaceAtRight && workspaceAtTop) ? root.largeWorkspaceRadius : root.smallWorkspaceRadius
                bottomLeftRadius: (workspaceAtLeft && workspaceAtBottom) ? root.largeWorkspaceRadius : root.smallWorkspaceRadius
                bottomRightRadius: (workspaceAtRight && workspaceAtBottom) ? root.largeWorkspaceRadius : root.smallWorkspaceRadius
                border.width: 2
                border.color: root.activeBorderColor
                Behavior on x {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on y {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on topLeftRadius {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
                Behavior on topRightRadius {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
                Behavior on bottomLeftRadius {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
                Behavior on bottomRightRadius {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
            }
        }
    }
}
