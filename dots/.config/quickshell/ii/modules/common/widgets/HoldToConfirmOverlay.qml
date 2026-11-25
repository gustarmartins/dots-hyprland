import QtQuick
import QtQuick.Window
import qs.modules.common
import qs.modules.common.functions

/**
 * Reusable stylized press-and-hold safety overlay with sweeping liquid fill,
 * luminous leading edge, bottom progress rail, border energy glow, completion
 * burst, and springy rewind on cancel. Zero animations or timers run at rest.
 */
Item {
    id: root
    anchors.fill: parent

    property real cornerRadius: 16
    property int durationMs: 950
    property color accentColor: Appearance?.m3colors?.m3error ?? "#f2b8b5"
    property color onAccentColor: Appearance?.m3colors?.m3onError ?? "#601410"
    property bool showIdleGuard: false

    property real progress: 0
    property bool holding: false
    property bool completed: false
    property bool showEarlyHint: false
    property string holdLabel: ""
    property string earlyHintText: ""
    property real burstOpacity: 0

    property var _pendingAction: null

    signal holdCompleted()
    signal holdCanceled(bool earlyRelease)

    function startHold(actionFn, customDurationMs, customLabel, customHint, customColor) {
        rewindAnim.stop();
        burstAnim.stop();
        earlyHintTimer.stop();
        root.burstOpacity = 0;
        root.showEarlyHint = false;
        root.completed = false;
        root._pendingAction = actionFn ?? null;
        if (customDurationMs !== undefined && customDurationMs > 0)
            root.durationMs = customDurationMs;
        if (customLabel !== undefined)
            root.holdLabel = customLabel;
        if (customHint !== undefined)
            root.earlyHintText = customHint;
        if (customColor !== undefined)
            root.accentColor = customColor;
        root.progress = 0;
        root.holding = true;
        holdAnim.duration = Math.max(120, root.durationMs);
        holdAnim.restart();
    }

    function cancelHold(triggerHint) {
        if (!root.holding) return;
        const wasIncomplete = root.progress < 0.999;
        holdAnim.stop();
        root.holding = false;
        root._pendingAction = null;
        if (triggerHint && wasIncomplete) {
            root.showEarlyHint = true;
            earlyHintTimer.restart();
        }
        if (root.progress > 0.001) {
            rewindAnim.from = root.progress;
            rewindAnim.restart();
        } else {
            root.progress = 0;
        }
        root.holdCanceled(Boolean(triggerHint && wasIncomplete));
    }

    function clearEarlyHint() {
        earlyHintTimer.stop();
        root.showEarlyHint = false;
    }

    function consumeCompleted() {
        if (!root.completed) return false;
        root.completed = false;
        return true;
    }

    onVisibleChanged: if (!visible) cancelHold(false)

    Connections {
        target: root.Window.window
        enabled: root.Window.window !== null
        function onVisibleChanged() {
            if (root.Window.window && !root.Window.window.visible)
                root.cancelHold(false);
        }
    }

    NumberAnimation {
        id: holdAnim
        target: root
        property: "progress"
        from: 0
        to: 1
        duration: root.durationMs
        easing.type: Easing.InOutQuad
        onFinished: {
            if (!root.holding || root.progress < 0.999) return;
            const action = root._pendingAction;
            root._pendingAction = null;
            root.holding = false;
            root.completed = true;
            root.showEarlyHint = false;
            earlyHintTimer.stop();
            burstAnim.restart();
            resetProgressTimer.restart();
            root.holdCompleted();
            if (action) action();
        }
    }

    NumberAnimation {
        id: rewindAnim
        target: root
        property: "progress"
        to: 0
        duration: 180
        easing.type: Easing.OutCubic
    }

    SequentialAnimation {
        id: burstAnim
        NumberAnimation {
            target: root
            property: "burstOpacity"
            from: 0.42
            to: 0
            duration: 260
            easing.type: Easing.OutCubic
        }
    }

    Timer {
        id: resetProgressTimer
        interval: 220
        repeat: false
        onTriggered: {
            if (!root.holding) {
                root.progress = 0;
                root.completed = false;
            }
        }
    }

    Timer {
        id: earlyHintTimer
        interval: 1500
        repeat: false
        onTriggered: root.showEarlyHint = false
    }

    // Sweeping liquid fill clipped to the button bounds with morphing right corners
    Item {
        anchors.fill: parent
        clip: true
        visible: root.progress > 0.001

        Rectangle {
            id: liquidSweep
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.max(0, parent.width * root.progress)
            topLeftRadius: root.cornerRadius
            bottomLeftRadius: root.cornerRadius
            topRightRadius: root.progress > 0.9 ? root.cornerRadius : 4
            bottomRightRadius: root.progress > 0.9 ? root.cornerRadius : 4
            color: ColorUtils.transparentize(root.accentColor, Math.max(0.56, 0.78 - root.progress * 0.22))

            // Luminous leading comet edge
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.topMargin: 2
                anchors.bottomMargin: 2
                width: Math.min(3, parent.width)
                radius: 1.5
                visible: root.holding && root.progress > 0.02 && root.progress < 0.995
                color: root.accentColor
                opacity: 0.45 + root.progress * 0.5
            }
        }
    }

    // Completion burst flash
    Rectangle {
        anchors.fill: parent
        radius: root.cornerRadius
        color: root.accentColor
        opacity: root.burstOpacity
        visible: root.burstOpacity > 0.001
    }

    // Precision bottom progress bar (subtle idle hairline on danger tiles, expands to 4px during hold)
    Rectangle {
        id: progressRail
        objectName: "holdProgressBar"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Math.max(8, root.cornerRadius * 0.6)
        anchors.rightMargin: Math.max(8, root.cornerRadius * 0.6)
        anchors.bottomMargin: 4
        height: (root.holding || root.progress > 0.001 || root.showEarlyHint) ? 4 : (root.showIdleGuard ? 2 : 0)
        radius: height / 2
        visible: height > 0
        color: (root.holding || root.progress > 0.001)
            ? ColorUtils.transparentize(root.accentColor, 0.76)
            : root.showEarlyHint
                ? ColorUtils.transparentize(root.accentColor, 0.45)
                : ColorUtils.transparentize(root.accentColor, 0.68)

        Rectangle {
            id: progressFill
            objectName: "holdProgressFill"
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.max(0, parent.width * root.progress)
            radius: parent.radius
            color: root.accentColor
            visible: root.progress > 0.001

            // Specular highlight tip at the leading edge of the progress bar
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.min(8, parent.width)
                radius: parent.radius
                color: Qt.lighter(root.accentColor, 1.45)
                opacity: root.holding ? 0.9 : 0.4
            }
        }
    }

    // Animated perimeter ring while holding or flashing early-release feedback
    Rectangle {
        anchors.fill: parent
        radius: root.cornerRadius
        color: "transparent"
        border.width: (root.holding || root.showEarlyHint) ? 1.5 : 0
        border.color: root.holding
            ? ColorUtils.transparentize(root.accentColor, Math.max(0.05, 0.55 - root.progress * 0.5))
            : ColorUtils.transparentize(root.accentColor, 0.25)
    }
}
