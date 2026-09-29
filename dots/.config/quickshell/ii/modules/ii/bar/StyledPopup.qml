import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

LazyLoader {
    id: root

    property Item hoverTarget
    default property Item contentItem
    property real popupBackgroundMargin: 0

    readonly property bool popupRequested: !!hoverTarget?.containsMouse
        && !!hoverTarget?.QsWindow.window?.visible

    property bool windowWarmed: false
    onPopupRequestedChanged: if (popupRequested) windowWarmed = true

    // Build outside the pointer handler. On this engine, setting a layer window
    // invisible destroys its native window and render thread. After first use,
    // keep it mapped but completely transparent, input-empty and without blur.
    activeAsync: true

    component: PanelWindow {
        id: popupWindow
        color: "transparent"
        visible: root.windowWarmed && !!root.hoverTarget?.QsWindow.window?.visible
        screen: root.hoverTarget?.QsWindow.window?.screen ?? null

        anchors.left: !Config.options.bar.vertical || (Config.options.bar.vertical && !Config.options.bar.bottom)
        anchors.right: Config.options.bar.vertical && Config.options.bar.bottom
        anchors.top: Config.options.bar.vertical || (!Config.options.bar.vertical && !Config.options.bar.bottom)
        anchors.bottom: !Config.options.bar.vertical && Config.options.bar.bottom

        implicitWidth: popupBackground.implicitWidth + Appearance.sizes.elevationMargin * 2 + root.popupBackgroundMargin
        implicitHeight: popupBackground.implicitHeight + Appearance.sizes.elevationMargin * 2 + root.popupBackgroundMargin

        mask: SurfaceRegion {
            id: popupRegion
            surface: root.popupRequested ? popupBackground : null
        }
        BackgroundEffect.blurRegion: root.popupRequested && popupBackground.glassEnabled ? popupRegion : null

        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        margins {
            left: {
                if (!Config.options.bar.vertical) {
                    // Center popup under the hover target, but clamp to the
                    // screen so a wide popup near an edge isn't clipped.
                    const targetWindow = root.hoverTarget?.QsWindow.window;
                    if (!targetWindow) return 0;
                    const centered = (targetWindow.mapFromItem(
                        root.hoverTarget,
                        (root.hoverTarget.width - popupBackground.implicitWidth) / 2, 0
                    ).x) ?? 0;
                    const screenW = popupWindow.screen?.width ?? Infinity;
                    const maxLeft = screenW - popupWindow.implicitWidth;
                    return Math.max(0, Math.min(centered, maxLeft));
                }
                return Appearance.sizes.verticalBarWidth
            }
            top: {
                if (!Config.options.bar.vertical) return Appearance.sizes.barHeight;
                const targetWindow = root.hoverTarget?.QsWindow.window;
                if (!targetWindow) return Appearance.sizes.barHeight;
                return targetWindow.mapFromItem(
                    root.hoverTarget, 
                    (root.hoverTarget.height - popupBackground.implicitHeight) / 2, 0
                ).y;
            }
            right: Appearance.sizes.verticalBarWidth
            bottom: Appearance.sizes.barHeight
        }
        WlrLayershell.namespace: "quickshell:popup"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        StyledRectangularShadow {
            target: popupBackground
            visible: root.popupRequested
        }

        GlassSurface {
            id: popupBackground
            visible: root.popupRequested
            readonly property real margin: 10
            anchors {
                fill: parent
                leftMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.left)
                rightMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.right)
                topMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.top)
                bottomMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.bottom)
            }
            implicitWidth: root.contentItem.implicitWidth + margin * 2
            implicitHeight: root.contentItem.implicitHeight + margin * 2
            baseColor: Appearance.m3colors.m3surfaceContainer
            radius: 24
            topLeftRadius: !Config.options.bar.bottom ? 12 : 24
            topRightRadius: !Config.options.bar.bottom ? 12 : 24
            bottomLeftRadius: Config.options.bar.bottom ? 12 : 24
            bottomRightRadius: Config.options.bar.bottom ? 12 : 24
            children: [root.contentItem]

        }
    }
}
