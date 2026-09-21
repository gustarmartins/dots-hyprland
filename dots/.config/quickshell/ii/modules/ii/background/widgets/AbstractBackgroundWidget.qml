import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets.widgetCanvas

AbstractWidget {
    id: root

    required property string configEntryName
    required property int screenWidth
    required property int screenHeight
    required property int scaledScreenWidth
    required property int scaledScreenHeight
    required property real wallpaperScale
    property bool visibleWhenLocked: false
    property var configEntry: Config.options.background.widgets[configEntryName]
    property string placementStrategy: configEntry.placementStrategy
    property real canvasOffsetX: 0
    property real canvasOffsetY: 0
    property bool centerOnScreen: false
    property point automaticCenter: Qt.point(NaN, NaN)
    readonly property real positionOffsetX: placementStrategy === "free" || centerOnScreen ? -canvasOffsetX : 0
    readonly property real positionOffsetY: placementStrategy === "free" || centerOnScreen ? -canvasOffsetY : 0
    readonly property real targetX: clampPosition(placementStrategy !== "free" && isFinite(automaticCenter.x)
        ? automaticCenter.x - width / 2 : configEntry.x, scaledScreenWidth - width)
    readonly property real targetY: clampPosition(placementStrategy !== "free" && isFinite(automaticCenter.y)
        ? automaticCenter.y - height / 2 : configEntry.y, scaledScreenHeight - height)
    readonly property real placedX: (centerOnScreen ? (screenWidth - width) / 2 : targetX) + positionOffsetX
    readonly property real placedY: (centerOnScreen ? (screenHeight - height) / 2 : targetY) + positionOffsetY
    x: placedX
    y: placedY
    // Cancel the animated canvas offset exactly, without a second animation lag.
    animateXPos: placementStrategy !== "free"
    animateYPos: placementStrategy !== "free"
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
    
    onWallpaperPathChanged: refreshPlacementIfNeeded()
    onPlacementStrategyChanged: refreshPlacementIfNeeded()
    Connections {
        target: Config
        function onReadyChanged() { refreshPlacementIfNeeded() }
    }
    function refreshPlacementIfNeeded() {
        if (!Config.ready) return;
        if (root.placementStrategy === "free" && !root.needsColText) return;
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
                // console.log("[Background] Least busy region output:", output)
                if (output.length === 0) return;
                const parsedContent = JSON.parse(output);
                root.dominantColor = parsedContent.dominant_color || Appearance.colors.colPrimary;
                if (root.placementStrategy === "free") return;
                root.automaticCenter = Qt.point(parsedContent.center_x * root.wallpaperScale,
                    parsedContent.center_y * root.wallpaperScale);
            }
        }
    }
}
