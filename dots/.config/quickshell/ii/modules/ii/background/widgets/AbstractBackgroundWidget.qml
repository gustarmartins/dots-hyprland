import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets.widgetCanvas
import "../WidgetPlacement.js" as WidgetPlacement

AbstractWidget {
    id: root

    required property string configEntryName
    required property int screenWidth
    required property int screenHeight
    required property int scaledScreenWidth
    required property int scaledScreenHeight
    required property real wallpaperScale
    property int monitorId: -1
    property real monitorX: 0
    property real monitorY: 0
    property var monitorReserved: [0, 0, 0, 0]
    property int activeWorkspaceId: -1
    property var avoidRects: []
    property bool visibleWhenLocked: false
    property var configEntry: Config.options.background.widgets[configEntryName]
    property string placementStrategy: configEntry.placementStrategy
    property real canvasOffsetX: 0
    property real canvasOffsetY: 0
    property bool centerOnScreen: false
    property point automaticCenter: Qt.point(NaN, NaN)
    property point openSpaceCenter: Qt.point(NaN, NaN)

    readonly property bool useOpenSpace: placementStrategy === "avoidWindows"
        && isFinite(openSpaceCenter.x) && isFinite(openSpaceCenter.y)
    readonly property bool useWallpaperAuto: placementStrategy !== "free"
        && isFinite(automaticCenter.x) && isFinite(automaticCenter.y)
    readonly property real targetX: clampPosition(useOpenSpace
        ? openSpaceCenter.x - width / 2
        : useWallpaperAuto ? automaticCenter.x - width / 2 : configEntry.x,
        scaledScreenWidth - width)
    readonly property real targetY: clampPosition(useOpenSpace
        ? openSpaceCenter.y - height / 2
        : useWallpaperAuto ? automaticCenter.y - height / 2 : configEntry.y,
        scaledScreenHeight - height)

    property real animatedTargetX: targetX
    property real animatedTargetY: targetY
    Behavior on animatedTargetX {
        enabled: root.placementStrategy !== "free" && !root.centerOnScreen && !root.drag.active
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    Behavior on animatedTargetY {
        enabled: root.placementStrategy !== "free" && !root.centerOnScreen && !root.drag.active
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    readonly property bool pinToScreen: placementStrategy === "free" || placementStrategy === "avoidWindows" || centerOnScreen
    readonly property real clampedParallaxX: clampPosition(animatedTargetX + canvasOffsetX, screenWidth - width) - animatedTargetX
    readonly property real clampedParallaxY: clampPosition(animatedTargetY + canvasOffsetY, screenHeight - height) - animatedTargetY
    readonly property real positionOffsetX: pinToScreen ? -canvasOffsetX : clampedParallaxX - canvasOffsetX
    readonly property real positionOffsetY: pinToScreen ? -canvasOffsetY : clampedParallaxY - canvasOffsetY
    readonly property real placedX: (centerOnScreen ? (screenWidth - width) / 2 : animatedTargetX) + positionOffsetX
    readonly property real placedY: (centerOnScreen ? (screenHeight - height) / 2 : animatedTargetY) + positionOffsetY
    readonly property var currentScreenRect: ({
        x: placedX + canvasOffsetX,
        y: placedY + canvasOffsetY,
        width: width,
        height: height,
    })

    x: placedX
    y: placedY
    // Smooth automatic placement happens on animatedTargetX/Y; keep x/y un-animated so
    // canvas parallax cancellation and clamping never lag behind workspace transitions.
    animateXPos: false
    animateYPos: false
    visible: opacity > 0
    opacity: (GlobalStates.screenLocked && !visibleWhenLocked) ? 0 : 1
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    scale: (draggable && containsPress) ? 1.05 : 1
    Behavior on scale {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    draggable: placementStrategy === "free" && !GlobalStates.screenLocked
    drag.minimumX: positionOffsetX
    drag.maximumX: positionOffsetX + Math.max(0, scaledScreenWidth - width)
    drag.minimumY: positionOffsetY
    drag.maximumY: positionOffsetY + Math.max(0, scaledScreenHeight - height)
    function clampPosition(value, maximum) {
        return Math.max(0, Math.min(Number.isFinite(value) ? value : 0, Math.max(0, maximum)));
    }
    function restorePlacementBinding() {
        // MouseArea drag writes x/y. Restore bindings for resize, lock and config changes.
        root.x = Qt.binding(() => root.placedX);
        root.y = Qt.binding(() => root.placedY);
    }
    onReleased: {
        if (!draggable) return;
        configEntry.x = clampPosition(root.x - positionOffsetX, scaledScreenWidth - width);
        configEntry.y = clampPosition(root.y - positionOffsetY, scaledScreenHeight - height);
        restorePlacementBinding();
    }
    onCanceled: restorePlacementBinding()

    property bool needsColText: false
    property color dominantColor: Appearance.colors.colPrimary
    property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
    property color colText: {
        const onNormalBackground = (GlobalStates.screenLocked && Config.options.lock.blur.enable)
        const adaptiveColor = ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12))
        return onNormalBackground ? Appearance.colors.colOnLayer0 : adaptiveColor;
    }

    property bool wallpaperIsVideo: Config.options.background.wallpaperPath.endsWith(".mp4") || Config.options.background.wallpaperPath.endsWith(".webm") || Config.options.background.wallpaperPath.endsWith(".mkv") || Config.options.background.wallpaperPath.endsWith(".avi") || Config.options.background.wallpaperPath.endsWith(".mov")
    property string wallpaperPath: wallpaperIsVideo ? Config.options.background.thumbnailPath : Config.options.background.wallpaperPath

    function recomputeOpenSpace() {
        if (root.placementStrategy !== "avoidWindows" || GlobalStates.screenLocked) {
            root.openSpaceCenter = Qt.point(NaN, NaN);
            return;
        }
        const obstacles = WidgetPlacement.monitorObstacles(
            HyprlandData.windowList, root.monitorId, root.monitorX, root.monitorY, root.activeWorkspaceId);
        const combined = obstacles.concat(Array.isArray(root.avoidRects) ? root.avoidRects : []);
        const spot = WidgetPlacement.bestOpenSpot(
            root.screenWidth, root.screenHeight, root.monitorReserved,
            combined, root.width || 230, root.height || 230,
            { edgeMargin: 24, obstaclePadding: 16 });
        root.openSpaceCenter = spot ? Qt.point(spot.x, spot.y) : Qt.point(NaN, NaN);
    }

    function scheduleOpenSpaceRefresh() {
        if (root.placementStrategy !== "avoidWindows") {
            openSpaceTimer.stop();
            root.openSpaceCenter = Qt.point(NaN, NaN);
            return;
        }
        openSpaceTimer.restart();
    }

    Timer {
        id: openSpaceTimer
        interval: 90
        repeat: false
        onTriggered: root.recomputeOpenSpace()
    }

    Connections {
        target: HyprlandData
        enabled: root.placementStrategy === "avoidWindows"
        function onWindowListChanged() { root.scheduleOpenSpaceRefresh(); }
    }

    onMonitorIdChanged: scheduleOpenSpaceRefresh()
    onMonitorXChanged: scheduleOpenSpaceRefresh()
    onMonitorYChanged: scheduleOpenSpaceRefresh()
    onMonitorReservedChanged: scheduleOpenSpaceRefresh()
    onActiveWorkspaceIdChanged: scheduleOpenSpaceRefresh()
    onAvoidRectsChanged: scheduleOpenSpaceRefresh()
    onWidthChanged: scheduleOpenSpaceRefresh()
    onHeightChanged: scheduleOpenSpaceRefresh()

    onWallpaperPathChanged: refreshPlacementIfNeeded()
    onScaledScreenWidthChanged: refreshPlacementIfNeeded()
    onScaledScreenHeightChanged: refreshPlacementIfNeeded()
    onPlacementStrategyChanged: {
        refreshPlacementIfNeeded();
        scheduleOpenSpaceRefresh();
    }
    Component.onCompleted: {
        refreshPlacementIfNeeded();
        scheduleOpenSpaceRefresh();
    }
    Connections {
        target: Config
        function onReadyChanged() {
            root.refreshPlacementIfNeeded();
            root.scheduleOpenSpaceRefresh();
        }
    }
    function refreshPlacementIfNeeded() {
        if (!Config.ready) return;
        if (root.placementStrategy === "free" && !root.needsColText) return;
        if (!root.wallpaperPath) return;
        leastBusyRegionProc.wallpaperPath = root.wallpaperPath;
        leastBusyRegionProc.running = false;
        leastBusyRegionProc.running = true;
    }
    Process {
        id: leastBusyRegionProc
        property string wallpaperPath: root.wallpaperPath
        // TODO: make these less arbitrary
        property int contentWidth: 300
        property int contentHeight: 300
        property int horizontalPadding: 200
        property int verticalPadding: 200
        command: [Quickshell.shellPath("scripts/images/least-busy-region-venv.sh") // Comments to force the formatter to break lines
            , "--screen-width", Math.round(root.scaledScreenWidth) //
            , "--screen-height", Math.round(root.scaledScreenHeight) //
            , "--width", contentWidth //
            , "--height", contentHeight //
            , "--horizontal-padding", horizontalPadding //
            , "--vertical-padding", verticalPadding //
            , wallpaperPath //
            , ...(root.placementStrategy === "mostBusy" ? ["--busiest"] : [])
            // "--visual-output",
        ]
        stdout: StdioCollector {
            id: leastBusyRegionOutputCollector
            onStreamFinished: {
                const output = leastBusyRegionOutputCollector.text;
                if (output.length === 0) return;
                try {
                    const parsedContent = JSON.parse(output);
                    root.dominantColor = parsedContent.dominant_color || Appearance.colors.colPrimary;
                    if (root.placementStrategy === "free") return;
                    root.automaticCenter = Qt.point(parsedContent.center_x * root.wallpaperScale,
                        parsedContent.center_y * root.wallpaperScale);
                } catch (error) {
                    console.warn("[Background] Failed to parse placement output:", error);
                }
            }
        }
    }
}
