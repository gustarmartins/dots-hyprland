import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ColumnLayout {
    id: root
    visible: EdenAudioBoost.enabled
    spacing: 4

    property int holdDurationMs: 850
    property string lockedTargetKey: ""
    property string lockedTargetName: ""

    readonly property bool canBoost: !EdenAudioBoost.busy && !EdenAudioBoost.active && EdenAudioBoost.streams > 0
    readonly property string displayTarget: holdOverlay.holding
        ? (root.lockedTargetName || EdenAudioBoost.targetName || "Current app")
        : (EdenAudioBoost.active ? (EdenAudioBoost.activeApp || EdenAudioBoost.targetName || "Current app")
            : (EdenAudioBoost.targetName || "Current app"))
    readonly property string dbLabel: "+" + Math.round(EdenAudioBoost.db || 12) + " dB"

    Rectangle {
        id: card
        objectName: "currentAppBoostCard"
        Layout.fillWidth: true
        implicitHeight: 58
        radius: 16
        scale: holdOverlay.holding ? 0.985 : 1.0
        color: EdenAudioBoost.active
            ? Appearance.m3colors.m3errorContainer
            : Appearance.m3colors.m3surfaceContainerHigh
        border.width: 1
        border.color: EdenAudioBoost.active
            ? ColorUtils.transparentize(Appearance.m3colors.m3error, 0.35)
            : ColorUtils.transparentize(Appearance.m3colors.m3outlineVariant, 0.45)

        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }

        HoldToConfirmOverlay {
            id: holdOverlay
            objectName: "currentAppBoostHold"
            cornerRadius: card.radius
            durationMs: root.holdDurationMs
            accentColor: Appearance.m3colors.m3error
            showIdleGuard: root.canBoost
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.topMargin: 8
            anchors.bottomMargin: 10
            spacing: 10

            // Stylized icon badge
            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: 12
                color: EdenAudioBoost.active
                    ? Appearance.m3colors.m3error
                    : holdOverlay.holding
                        ? ColorUtils.transparentize(Appearance.m3colors.m3error, 0.18)
                        : ColorUtils.transparentize(Appearance.m3colors.m3primary, 0.86)
                Behavior on color { ColorAnimation { duration: 140 } }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: EdenAudioBoost.active ? "volume_up" : (holdOverlay.holding ? "bolt" : "campaign")
                    iconSize: 20
                    fill: EdenAudioBoost.active || holdOverlay.holding ? 1 : 0
                    color: (EdenAudioBoost.active || holdOverlay.holding)
                        ? Appearance.m3colors.m3onError
                        : Appearance.m3colors.m3primary
                }
            }

            // Two-line live status copy
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    objectName: "currentAppBoostTitle"
                    Layout.fillWidth: true
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    color: EdenAudioBoost.active
                        ? Appearance.m3colors.m3onErrorContainer
                        : Appearance.m3colors.m3onSurface
                    text: EdenAudioBoost.busy
                        ? "Updating app boost…"
                        : holdOverlay.holding
                            ? ("Boosting " + root.displayTarget + " · " + root.dbLabel)
                            : EdenAudioBoost.active
                                ? (root.displayTarget + " boosted · " + root.dbLabel)
                                : EdenAudioBoost.streams > 0
                                    ? ("Boost " + root.displayTarget + " · " + root.dbLabel)
                                    : ("Boost current app · " + root.dbLabel)
                }

                StyledText {
                    objectName: "currentAppBoostSubtitle"
                    Layout.fillWidth: true
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    color: holdOverlay.showEarlyHint
                        ? Appearance.m3colors.m3error
                        : EdenAudioBoost.active
                            ? ColorUtils.transparentize(Appearance.m3colors.m3onErrorContainer, 0.18)
                            : Appearance.m3colors.m3onSurfaceVariant
                    text: holdOverlay.showEarlyHint
                        ? "Hold button to confirm " + root.dbLabel + " boost"
                        : holdOverlay.holding
                            ? "Keep holding to apply · release to cancel"
                            : EdenAudioBoost.active
                                ? "Click to reset immediately · uses current EQ"
                                : EdenAudioBoost.streams > 0
                                    ? ("Hold to boost · " + (EdenAudioBoost.targetReason === "focused" ? "Focused app" : "Active audio"))
                                    : "Start audio in any app first"
                }
            }

            // Right pill badge: HOLD / live % / RESET
            Rectangle {
                objectName: "currentAppBoostPill"
                Layout.preferredHeight: 24
                Layout.preferredWidth: Math.max(48, pillText.implicitWidth + 16)
                radius: 12
                visible: EdenAudioBoost.active || root.canBoost || holdOverlay.holding
                color: EdenAudioBoost.active
                    ? Appearance.m3colors.m3error
                    : holdOverlay.holding
                        ? Appearance.m3colors.m3error
                        : ColorUtils.transparentize(Appearance.m3colors.m3error, 0.84)
                border.width: (!EdenAudioBoost.active && !holdOverlay.holding) ? 1 : 0
                border.color: ColorUtils.transparentize(Appearance.m3colors.m3error, 0.55)

                StyledText {
                    id: pillText
                    anchors.centerIn: parent
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: (EdenAudioBoost.active || holdOverlay.holding)
                        ? Appearance.m3colors.m3onError
                        : Appearance.m3colors.m3error
                    text: EdenAudioBoost.active
                        ? "RESET"
                        : holdOverlay.holding
                            ? (Math.round(holdOverlay.progress * 100) + "%")
                            : "HOLD"
                }
            }
        }

        Accessible.name: EdenAudioBoost.active
            ? ("Current app boost active on " + root.displayTarget + "; click to reset")
            : ("Boost " + root.displayTarget + " by " + root.dbLabel + "; press and hold to activate")

        MouseArea {
            id: interaction
            objectName: "currentAppBoostArea"
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            enabled: !EdenAudioBoost.busy && (EdenAudioBoost.active || EdenAudioBoost.streams > 0)
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

            onPressed: event => {
                if (event.button !== Qt.LeftButton) return;
                if (EdenAudioBoost.active) return;
                if (EdenAudioBoost.streams <= 0) return;
                root.lockedTargetKey = EdenAudioBoost.targetKey;
                root.lockedTargetName = EdenAudioBoost.targetName;
                const keyToBoost = root.lockedTargetKey;
                holdOverlay.startHold(
                    () => EdenAudioBoost.boost(keyToBoost),
                    root.holdDurationMs,
                    "Boost " + (root.lockedTargetName || "app"),
                    "Hold button to confirm " + root.dbLabel + " boost",
                    Appearance.m3colors.m3error
                );
            }

            onPositionChanged: {
                if (holdOverlay.holding && !containsMouse)
                    holdOverlay.cancelHold(false);
            }

            onReleased: event => {
                if (event.button !== Qt.LeftButton) return;
                if (holdOverlay.holding) {
                    holdOverlay.cancelHold(containsMouse);
                    return;
                }
                if (holdOverlay.consumeCompleted()) return;
                if (EdenAudioBoost.active && containsMouse)
                    EdenAudioBoost.reset();
            }

            onCanceled: holdOverlay.cancelHold(false)
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: EdenAudioBoost.error.length > 0
        text: EdenAudioBoost.error
        font.pixelSize: 11
        wrapMode: Text.WordWrap
        color: Appearance.m3colors.m3error
    }
}
