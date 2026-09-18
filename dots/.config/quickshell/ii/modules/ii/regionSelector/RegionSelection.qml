pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.utils
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Qt.labs.synchronizer
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "SelectionGeometry.js" as Geometry

PanelWindow {
    id: root
    property bool sessionReady: false
    property bool sessionBusy: false
    property bool sessionHidden: false
    property bool inputReady: false
    property string sessionId: ""
    property var selectedRegion: null
    property string hint: ""
    signal processing(bool running, bool hidePanels)
    signal recordingStarted()
    signal preparationFailed(string message)
    visible: root.sessionReady && root.preparationDone && !root.sessionHidden
    color: "transparent"
    WlrLayershell.namespace: "quickshell:regionSelector"
    WlrLayershell.layer: WlrLayer.Overlay
    // Take focus immediately while selecting; release it during recording.
    WlrLayershell.keyboardFocus: root.visible && root.phase === RegionSelection.Phase.Select
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    // Modes
    // TODO: Ask: sidebar AI
    enum SnipAction { Copy, Edit, Search, CharRecognition, Record, RecordWithSound } 
    enum SelectionMode { RectCorners, Circle }
    enum Phase { Select, Post }
    property var action: RegionSelection.SnipAction.Copy
    property var selectionMode: RegionSelection.SelectionMode.RectCorners
    property var phase: RegionSelection.Phase.Select
    signal dismiss()
    Component.onDestruction: Quickshell.execDetached(["rm", "-f", root.screenshotPath])
    function cancelGesture() { mouseArea.cancelGesture(); }
    onSelectionModeChanged: { if (mouseArea) mouseArea.reset(); root.selectedRegion = null; }

    // Styles
    property string screenshotDir: Directories.screenshotTemp
    property color overlayColor: ColorUtils.transparentize("#000000", 0.4)
    property color brightText: Appearance.m3colors.darkmode ? Appearance.colors.colOnLayer0 : Appearance.colors.colLayer0
    property color brightSecondary: Appearance.m3colors.darkmode ? Appearance.colors.colSecondary : Appearance.colors.colOnSecondary
    property color brightTertiary: Appearance.m3colors.darkmode ? Appearance.colors.colTertiary : Qt.lighter(Appearance.colors.colPrimary)
    property color selectionBorderColor: ColorUtils.mix(brightText, brightSecondary, 0.5)
    property color selectionFillColor: "#33ffffff"
    property color windowBorderColor: brightSecondary
    property color windowFillColor: ColorUtils.transparentize(windowBorderColor, 0.85)
    property color imageBorderColor: brightTertiary
    property color imageFillColor: ColorUtils.transparentize(imageBorderColor, 0.85)
    property color onBorderColor: "#ff000000"
    property real targetRegionOpacity: Config.options.regionSelector.targetRegions.opacity
    property bool contentRegionOpacity: Config.options.regionSelector.targetRegions.contentRegionOpacity

    // Vars for indicators
    readonly property var windows: [...HyprlandData.windowList].sort((a, b) => {
        // Sort floating=true windows before others
        if (a.floating === b.floating) return (a.focusHistoryID ?? 999) - (b.focusHistoryID ?? 999);
        return a.floating ? -1 : 1;
    })
    readonly property var layers: HyprlandData.layers
    readonly property real falsePositivePreventionRatio: 0.5

    // Screen & interaction vars
    readonly property HyprlandMonitor hyprlandMonitor: Hyprland.monitorFor(screen)
    readonly property real monitorScale: frozenImage.sourceSize.width > 0 && root.screen.width > 0
        ? frozenImage.sourceSize.width / root.screen.width : (hyprlandMonitor?.scale > 0 ? hyprlandMonitor.scale : 1)
    readonly property real monitorOffsetX: hyprlandMonitor?.x ?? root.screen.x
    readonly property real monitorOffsetY: hyprlandMonitor?.y ?? root.screen.y
    property int activeWorkspaceId: hyprlandMonitor?.activeWorkspace?.id ?? 0
    property string screenshotPath: `${root.screenshotDir}/region-${root.sessionId}-${screen.name}.png`
    readonly property bool draggedAway: mouseArea.moved
    readonly property bool dragging: mouseArea.dragging
    readonly property var points: mouseArea.points
    property var mouseButton: null
    property var imageRegions: []
    readonly property int specialWorkspaceId: HyprlandData.monitors.find(m => m.name === root.screen.name)?.specialWorkspace?.id ?? 0
    readonly property list<var> windowRegions: root.windows.filter(w =>
        w.mapped !== false && !w.hidden && (w.workspace.id === root.activeWorkspaceId || w.pinned ||
        (root.specialWorkspaceId !== 0 && w.workspace.id === root.specialWorkspaceId))
    ).map(window => ({
        at: [window.at[0] - root.monitorOffsetX, window.at[1] - root.monitorOffsetY],
        size: window.size, class: window.class, title: window.title
    })).filter(w => Geometry.clip({x: w.at[0], y: w.at[1], width: w.size[0], height: w.size[1]}, root.screen.width, root.screen.height))
    readonly property list<var> layerRegions: {
        const layersOfThisMonitor = root.layers[root.screen.name]
        const topLayers = layersOfThisMonitor?.levels["2"]
        if (!topLayers) return [];
        const nonBarTopLayers = topLayers
            .filter(layer => !(layer.namespace.includes(":bar") || layer.namespace.includes(":verticalBar") || layer.namespace.includes(":dock")))
            .map(layer => {
            return {
                at: [layer.x, layer.y],
                size: [layer.w, layer.h],
                namespace: layer.namespace,
            }
        })
        const offsetAdjustedLayers = nonBarTopLayers.map(layer => {
            return {
                at: [layer.at[0] - root.monitorOffsetX, layer.at[1] - root.monitorOffsetY],
                size: layer.size,
                namespace: layer.namespace,
            }
        });
        return offsetAdjustedLayers;
    }

    // Config
    property bool isCircleSelection: (root.selectionMode === RegionSelection.SelectionMode.Circle)
    property bool enableWindowRegions: Config.options.regionSelector.targetRegions.windows && !isCircleSelection
    property bool enableLayerRegions: Config.options.regionSelector.targetRegions.layers && !isCircleSelection
    property bool enableContentRegions: Config.options.regionSelector.targetRegions.content

    // Target
    property real targetedRegionX: -1
    property real targetedRegionY: -1
    property real targetedRegionWidth: 0
    property real targetedRegionHeight: 0
    function targetedRegionValid() {
        return root.targetedRegionWidth > 0 && root.targetedRegionHeight > 0
    }
    function targetedRect() {
        const padding = Config.options.regionSelector.targetRegions.selectionPadding;
        return {x: root.targetedRegionX - padding, y: root.targetedRegionY - padding,
            width: root.targetedRegionWidth + padding * 2, height: root.targetedRegionHeight + padding * 2};
    }

    function updateTargetedRegion(x, y) {
        // Image regions
        const clickedRegion = (root.enableContentRegions ? root.imageRegions : []).find(region => {
            return region.at[0] <= x && x <= region.at[0] + region.size[0] && region.at[1] <= y && y <= region.at[1] + region.size[1];
        });
        if (clickedRegion) {
            root.targetedRegionX = clickedRegion.at[0];
            root.targetedRegionY = clickedRegion.at[1];
            root.targetedRegionWidth = clickedRegion.size[0];
            root.targetedRegionHeight = clickedRegion.size[1];
            return;
        }

        // Layer regions
        const clickedLayer = (root.enableLayerRegions ? root.layerRegions : []).find(region => {
            return region.at[0] <= x && x <= region.at[0] + region.size[0] && region.at[1] <= y && y <= region.at[1] + region.size[1];
        });
        if (clickedLayer) {
            root.targetedRegionX = clickedLayer.at[0];
            root.targetedRegionY = clickedLayer.at[1];
            root.targetedRegionWidth = clickedLayer.size[0];
            root.targetedRegionHeight = clickedLayer.size[1];
            return;
        }

        // Window regions
        const clickedWindow = (root.enableWindowRegions ? root.windowRegions : []).find(region => {
            return region.at[0] <= x && x <= region.at[0] + region.size[0] && region.at[1] <= y && y <= region.at[1] + region.size[1];
        });
        if (clickedWindow) {
            root.targetedRegionX = clickedWindow.at[0];
            root.targetedRegionY = clickedWindow.at[1];
            root.targetedRegionWidth = clickedWindow.size[0];
            root.targetedRegionHeight = clickedWindow.size[1];
            return;
        }

        root.targetedRegionX = -1;
        root.targetedRegionY = -1;
        root.targetedRegionWidth = 0;
        root.targetedRegionHeight = 0;
    }

    readonly property real regionWidth: root.selectedRegion?.width ?? mouseArea.regionWidth
    readonly property real regionHeight: root.selectedRegion?.height ?? mouseArea.regionHeight
    readonly property real regionX: root.selectedRegion?.x ?? mouseArea.regionX
    readonly property real regionY: root.selectedRegion?.y ?? mouseArea.regionY

    // Screenshot stuff
    TempScreenshotProcess {
        id: screenshotProc
        running: true
        screen: root.screen
        screenshotDir: root.screenshotDir
        screenshotPath: root.screenshotPath
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.preparationFailed("Could not capture " + root.screen.name + ". Try again.");
                return;
            }
            root.captureReady = true;
            if (root.enableContentRegions) imageDetectionProcess.running = true;
        }
    }
    property bool isRecording: root.action === RegionSelection.SnipAction.Record || root.action === RegionSelection.SnipAction.RecordWithSound
    property bool captureReady: false
    readonly property bool preparationDone: root.captureReady && frozenImage.status === Image.Ready

    Process {
        id: imageDetectionProcess
        command: ["bash", "-c", `${Directories.scriptPath}/images/find-regions-venv.sh ` 
            + `--hyprctl ` 
            + `--image '${StringUtils.shellSingleQuoteEscape(root.screenshotPath)}' ` 
            + `--max-width ${Math.round(root.screen.width * root.falsePositivePreventionRatio)} ` 
            + `--max-height ${Math.round(root.screen.height * root.falsePositivePreventionRatio)} `]
        stdout: StdioCollector {
            id: imageDimensionCollector
            onStreamFinished: {
                try {
                    const regions = JSON.parse(imageDimensionCollector.text);
                    if (!Array.isArray(regions)) return;
                    imageRegions = RegionFunctions.filterImageRegions(
                        regions.filter(r => Array.isArray(r.at) && Array.isArray(r.size)), root.windowRegions);
                } catch (e) { console.warn("[Region Selector] Content detection unavailable:", e); }
            }
        }
    }

    function snip(rect) {
        if (root.sessionBusy) return;
        const clipped = Geometry.clip(rect, root.screen.width, root.screen.height);
        if (!clipped) {
            root.selectedRegion = null;
            mouseArea.reset();
            root.hint = "Drag an area to capture, or click a highlighted target.";
            return;
        }
        root.selectedRegion = clipped;
        let action = root.action;
        if (action === RegionSelection.SnipAction.Copy || action === RegionSelection.SnipAction.Edit)
            action = root.mouseButton === Qt.RightButton ? RegionSelection.SnipAction.Edit : RegionSelection.SnipAction.Copy;
        if (root.isRecording) {
            // wf-recorder takes global logical coordinates, not screenshot pixels.
            const region = `${Math.round(clipped.x + root.monitorOffsetX)},${Math.round(clipped.y + root.monitorOffsetY)} ${Math.round(clipped.width)}x${Math.round(clipped.height)}`;
            let args = [Directories.recordScriptPath, "--region", region];
            if (action === RegionSelection.SnipAction.RecordWithSound) args.push("--sound");
            Quickshell.execDetached(args);
            root.phase = RegionSelection.Phase.Post;
            root.selectionMode = RegionSelection.SelectionMode.RectCorners;
            root.selectedRegion = clipped;
            root.recordingStarted();
            return;
        }
        const pixels = Geometry.pixels(clipped, root.monitorScale, root.screen.width, root.screen.height);
        const names = ["copy", "edit", "search", "ocr"];
        if (!pixels || !names[action]) { root.hint = "This capture action is unavailable."; return; }
        root.hint = action === RegionSelection.SnipAction.Search ? "Searching image…" : "Processing selection…";
        actionProc.command = ["python3", Directories.scriptPath + "/images/region-action.py",
            "--action", names[action], "--image", root.screenshotPath,
            "--geometry", String(pixels.x), String(pixels.y), String(pixels.width), String(pixels.height),
            "--save-dir", Config.options.screenSnip.savePath,
            "--search-url", Config.options.search.imageSearch.imageSearchEngineBaseUrl,
            "--editor", Config.options.regionSelector.annotation.useSatty ? "satty" : "swappy"];
        root.processing(true, action === RegionSelection.SnipAction.Edit);
        actionProc.running = true;
    }
    Process {
        id: actionProc
        stderr: StdioCollector { id: actionError }
        onExited: (exitCode, exitStatus) => {
            root.processing(false, false);
            if (exitCode === 0) root.dismiss();
            else {
                root.selectedRegion = null;
                mouseArea.reset();
                root.hint = "Capture failed: " + actionError.text.trim() + " Drag again to retry.";
                console.warn("[Region Selector]", root.hint);
            }
        }
    }

    // Only clickable in Selection phase
    mask: Region {
        item: switch(root.phase) {
            case RegionSelection.Phase.Select: return mouseArea;
            case RegionSelection.Phase.Post: return null;
        }
    }

    Image { // Display the same frozen frame that the action will crop.
        id: frozenImage
        onStatusChanged: if (status === Image.Error) root.preparationFailed("Could not read the captured image. Try again.")
        anchors.fill: parent
        source: root.captureReady ? "file://" + root.screenshotPath : ""
        cache: false
        fillMode: Image.Stretch
        visible: root.phase === RegionSelection.Phase.Select

        focus: root.visible
        Keys.onPressed: (event) => { // Esc to close
            if (event.key === Qt.Key_Escape && !root.sessionBusy) {
                root.dismiss();
            }
        }
    }

    SelectionGesture {
        id: mouseArea
        anchors.fill: parent
        accepting: root.inputReady && !root.sessionBusy && root.phase === RegionSelection.Phase.Select
        onStarted: { root.hint = ""; root.selectedRegion = null; }
        onInterrupted: reason => { root.selectedRegion = null; root.hint = reason; }
        onPointerMoved: (px, py) => root.updateTargetedRegion(px, py)
        onFinished: (px, py, button, wasMoved) => {
            root.mouseButton = button;
            let rect = null;
            if (!wasMoved) {
                root.updateTargetedRegion(px, py);
                if (root.targetedRegionValid()) rect = root.targetedRect();
            } else if (root.isCircleSelection) {
                const padding = Config.options.regionSelector.circle.padding + Config.options.regionSelector.circle.strokeWidth / 2;
                rect = Geometry.bounds(mouseArea.points, padding);
            } else rect = {x: mouseArea.regionX, y: mouseArea.regionY, width: mouseArea.regionWidth, height: mouseArea.regionHeight};
            root.snip(rect);
        }

        Loader {
            z: 2
            anchors.fill: parent
            active: root.selectionMode === RegionSelection.SelectionMode.RectCorners
            sourceComponent: RectCornersSelectionDetails {
                regionX: root.regionX
                regionY: root.regionY
                regionWidth: root.regionWidth
                regionHeight: root.regionHeight
                mouseX: mouseArea.mouseX
                mouseY: mouseArea.mouseY
                color: root.selectionBorderColor
                overlayColor: root.overlayColor
                breathingBorderOnly: root.phase === RegionSelection.Phase.Post
            }
        }

        Loader {
            z: 2
            anchors.fill: parent
            active: root.selectionMode === RegionSelection.SelectionMode.Circle
            sourceComponent: CircleSelectionDetails {
                color: root.selectionBorderColor
                overlayColor: root.overlayColor
                points: root.points
            }
        }

        // The thing to the bottom-right with an icon
        CursorGuide {
            z: 9999
            visible: root.phase === RegionSelection.Phase.Select
            x: root.dragging ? root.regionX + root.regionWidth : mouseArea.mouseX
            y: root.dragging ? root.regionY + root.regionHeight : mouseArea.mouseY
            action: root.action
            selectionMode: root.selectionMode
        }

        // Window regions
        Repeater {
            model: ScriptModel {
                values: {
                    if (root.phase === RegionSelection.Phase.Select && root.enableWindowRegions) {
                        return root.windowRegions
                    } else {
                        return []
                    }
                }
            }
            delegate: TargetRegion {
                z: 2
                required property var modelData
                clientDimensions: modelData
                showIcon: true
                targeted: !root.draggedAway && //
                    (root.targetedRegionX === modelData.at[0]  //
                    && root.targetedRegionY === modelData.at[1] //
                    && root.targetedRegionWidth === modelData.size[0] //
                    && root.targetedRegionHeight === modelData.size[1])

                opacity: root.draggedAway ? 0 : root.targetRegionOpacity
                borderColor: root.windowBorderColor
                fillColor: targeted ? root.windowFillColor : "transparent"
                text: `${modelData.class}`
                radius: Appearance.rounding.windowRounding
            }
        }

        // Layer regions
        Repeater {
            model: ScriptModel {
                values: {
                    if (root.phase === RegionSelection.Phase.Select && root.enableLayerRegions) {
                        return root.layerRegions
                    } else {
                        return []
                    }
                }
            }
            delegate: TargetRegion {
                z: 3
                required property var modelData
                clientDimensions: modelData
                targeted: !root.draggedAway &&
                    (root.targetedRegionX === modelData.at[0] 
                    && root.targetedRegionY === modelData.at[1]
                    && root.targetedRegionWidth === modelData.size[0]
                    && root.targetedRegionHeight === modelData.size[1])

                opacity: root.draggedAway ? 0 : root.targetRegionOpacity
                borderColor: root.windowBorderColor
                fillColor: targeted ? root.windowFillColor : "transparent"
                text: `${modelData.namespace}`
                radius: Appearance.rounding.windowRounding
            }
        }

        // Content regions
        Repeater {
            model: ScriptModel {
                values: {
                    if (root.phase === RegionSelection.Phase.Select && root.enableContentRegions) {
                        return root.imageRegions
                    } else {
                        return []
                    }
                }
            }
            delegate: TargetRegion {
                z: 4
                required property var modelData
                clientDimensions: modelData
                targeted: !root.draggedAway &&
                    (root.targetedRegionX === modelData.at[0] 
                    && root.targetedRegionY === modelData.at[1]
                    && root.targetedRegionWidth === modelData.size[0]
                    && root.targetedRegionHeight === modelData.size[1])

                opacity: root.draggedAway ? 0 : root.contentRegionOpacity
                borderColor: root.imageBorderColor
                fillColor: targeted ? root.imageFillColor : "transparent"
                text: Translation.tr("Content region")
            }
        }

        Rectangle {
            z: 11
            visible: root.hint.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: regionSelectionControls.top
            anchors.bottomMargin: 12
            width: Math.min(parent.width - 40, 640)
            height: hintText.implicitHeight + 20
            radius: 12
            color: Appearance.m3colors.m3surfaceContainerHigh
            StyledText {
                id: hintText
                anchors.fill: parent
                anchors.margins: 10
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: root.hint
            }
        }

        // Controls
        Row {
            id: regionSelectionControls
            z: 10
            visible: root.phase === RegionSelection.Phase.Select
            enabled: root.inputReady && !root.sessionBusy
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: -height
            }
            opacity: 0
            Connections {
                target: root
                function onVisibleChanged() {
                    if (!visible) return;
                    regionSelectionControls.anchors.bottomMargin = 8;
                    regionSelectionControls.opacity = 1;
                }
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on anchors.bottomMargin {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            spacing: 6

            OptionsToolbar {
                Synchronizer on action {
                    property alias source: root.action
                }
                Synchronizer on selectionMode {
                    property alias source: root.selectionMode
                }
                onDismiss: root.dismiss();
            }
            ToolbarPairedFab {
                anchors.verticalCenter: parent.verticalCenter
                iconText: "close"
                onClicked: root.dismiss();
                StyledToolTip {
                    text: Translation.tr("Close")
                }
            }
        }
        
    }
}
