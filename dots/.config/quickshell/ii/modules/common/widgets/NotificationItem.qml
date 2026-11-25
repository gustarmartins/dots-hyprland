import qs
import qs.modules.common
import qs.services
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Notifications

Item { // Notification item area
    id: root
    objectName: "notificationCard"
    readonly property string formattedBody: NotificationUtils.processNotificationBody(String(notificationObject?.mailData && !Mail.config.preview ? (notificationObject?.body ?? "").split("\n\n")[0] : notificationObject?.body ?? ""), notificationObject?.appName || notificationObject?.summary).replace(/\n/g, "<br/>")
    property var notificationObject
    property bool groupExpanded: false
    property bool detailsExpanded: false
    property bool expanded: groupExpanded && (onlyNotification || detailsExpanded)
    onGroupExpandedChanged: if (!groupExpanded) detailsExpanded = false
    property bool popup: false
    property bool onlyNotification: false
    readonly property var compactActions: Notifications.visibleActions(notificationObject).filter(action => action.identifier !== "default" && String(action.text ?? "").trim().length > 0)
    property real fontSize: Appearance.font.pixelSize.small
    property real padding: onlyNotification ? 0 : 8
    property real summaryElideRatio: 0.85
    property int compactBodyLineCount: popup ? 3 : 2
    property int expandedBodyLineCount: popup ? 16 : 2147483647

    property real dragConfirmThreshold: 70 // Drag further to discard notification
    property real dismissOvershoot: notificationIcon.implicitWidth + 20 // Account for gaps and bouncy animations
    property var qmlParent: root?.parent?.parent // There's something between this and the parent ListView
    property var parentDragIndex: qmlParent?.dragIndex ?? -1
    property var parentDragDistance: qmlParent?.dragDistance ?? 0
    property var dragIndexDiff: Math.abs(parentDragIndex - index)
    property real xOffset: dragIndexDiff == 0 ? parentDragDistance : 
        Math.abs(parentDragDistance) > dragConfirmThreshold ? 0 :
        dragIndexDiff == 1 ? (parentDragDistance * 0.3) :
        dragIndexDiff == 2 ? (parentDragDistance * 0.1) : 0

    implicitHeight: background.implicitHeight
    signal groupExpansionRequested()

    Connections {
        target: Notifications
        function onSessionOpening(id) {
            if (root.notificationObject?.notificationId === id) GlobalStates.sidebarRightOpen = false;
        }
        function onSessionOpened(id) {
            if (root.notificationObject?.notificationId === id) GlobalStates.sidebarRightOpen = false;
        }
    }

    function toggleExpanded() {
        if (!root.groupExpanded || root.onlyNotification) root.groupExpansionRequested();
        else root.detailsExpanded = !root.detailsExpanded;
    }

    function activate() {
        const action = Notifications.visibleActions(root.notificationObject).find(a => a.identifier === "default");
        if (action) Notifications.attemptInvokeAction(root.notificationObject.notificationId, action.identifier);
        else root.toggleExpanded();
    }

    function destroyWithAnimation(left = false) {
        root.qmlParent.resetDrag()
        background.anchors.leftMargin = background.anchors.leftMargin; // Break binding
        destroyAnimation.left = left;
        destroyAnimation.running = true;
    }

    TextMetrics {
        id: summaryTextMetrics
        font.pixelSize: root.fontSize
        text: root.notificationObject?.summary ?? ""
    }

    SequentialAnimation { // Drag finish animation
        id: destroyAnimation
        property bool left: true
        running: false

        NumberAnimation {
            target: background.anchors
            property: "leftMargin"
            to: (root.width + root.dismissOvershoot) * (destroyAnimation.left ? -1 : 1)
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
        onFinished: () => {
            if (notificationObject) Notifications.discardNotification(notificationObject.notificationId);
        }
    }

    DragManager { // Drag manager
        id: dragManager
        anchors.fill: root
        anchors.leftMargin: root.expanded ? -notificationIcon.implicitWidth : 0
        interactive: root.groupExpanded || root.onlyNotification
        automaticallyReset: false
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onClicked: (mouse) => {
            if (mouse.button === Qt.MiddleButton) {
                root.destroyWithAnimation();
            } else if (mouse.button === Qt.RightButton) root.toggleExpanded();
            else root.activate();
        }

        onDraggingChanged: () => {
            if (dragging) {
                root.qmlParent.dragIndex = root.index ?? root.parent.children.indexOf(root);
            }
        }

        onDragDiffXChanged: () => {
            root.qmlParent.dragDistance = dragDiffX;
        }

        onDragReleased: (diffX, diffY) => {
            if (Math.abs(diffX) > root.dragConfirmThreshold)
                root.destroyWithAnimation(diffX < 0);
            else 
                dragManager.resetDrag();
        }
    }

    NotificationAppIcon { // App icon
        id: notificationIcon
        opacity: (!onlyNotification && (notificationObject?.image ?? "") != "" && expanded) ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        image: notificationObject?.image ?? ""
        anchors.right: background.left
        anchors.top: background.top
        anchors.rightMargin: 10
    }

    Rectangle { // Background of notification item
        id: background
        width: parent.width
        anchors.left: parent.left
        radius: 16
        anchors.leftMargin: root.xOffset

        Behavior on anchors.leftMargin {
            enabled: !dragManager.dragging
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }

        color: (root.groupExpanded && !onlyNotification) ?
            ((notificationObject?.urgency ?? NotificationUrgency.Normal) == NotificationUrgency.Critical) ?
                ColorUtils.mix(Appearance.colors.colSecondaryContainer, Appearance.colors.colLayer2, 0.35) :
                (Appearance.colors.colLayer3) :
            ColorUtils.transparentize(Appearance.colors.colLayer3)

        implicitHeight: contentColumn.implicitHeight + (root.groupExpanded ? padding * 2 : 0)
        Behavior on implicitHeight {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        ColumnLayout { // Content column
            id: contentColumn
            anchors.fill: parent
            anchors.margins: root.groupExpanded ? root.padding : 0
            spacing: 3

            Behavior on anchors.margins {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            RowLayout { // Summary row
                id: summaryRow
                visible: !root.onlyNotification || !root.expanded || summaryText.text.length > 0
                Layout.fillWidth: true
                implicitHeight: Math.max(summaryText.implicitHeight, compactBodyText.implicitHeight, expansionControl.visible ? expansionControl.implicitHeight : 0)
                StyledText {
                    id: summaryText
                    Layout.fillWidth: summaryTextMetrics.width >= summaryRow.implicitWidth * root.summaryElideRatio
                    visible: !root.onlyNotification || root.expanded
                    font.pixelSize: root.fontSize
                    color: Appearance.colors.colOnLayer3
                    elide: Text.ElideRight
                    wrapMode: root.expanded ? Text.Wrap : Text.NoWrap
                    maximumLineCount: root.expanded ? 2147483647 : 1
                    text: root.notificationObject?.summary ?? ""
                }
                StyledText {
                    id: compactBodyText
                    opacity: !root.expanded ? 1 : 0
                    visible: opacity > 0
                    Layout.fillWidth: true
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    font.pixelSize: root.fontSize
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    wrapMode: Text.Wrap // Needed for proper eliding????
                    maximumLineCount: root.compactBodyLineCount
                    textFormat: Text.StyledText
                    onLinkActivated: link => { if (/^https?:\/\//i.test(link)) Qt.openUrlExternally(link); }
                    PointingHandLinkHover {}
                    text: {
                        return root.expanded ? "" : root.formattedBody
                    }
                }
                NotificationGroupExpandButton {
                    id: expansionControl
                    objectName: "notificationExpand-" + root.notificationObject?.notificationId
                    visible: root.groupExpanded && !root.onlyNotification
                    count: 1
                    more: true
                    expanded: root.expanded
                    onClicked: root.toggleExpanded()
                    altAction: () => root.toggleExpanded()
                    Accessible.name: root.expanded ? Translation.tr("Collapse notification") : Translation.tr("Expand notification")
                    StyledToolTip { text: root.expanded ? Translation.tr("Collapse") : Translation.tr("Show full notification") }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.popup && !root.expanded && root.compactActions.length > 0
                Repeater {
                    model: root.popup && !root.expanded ? root.compactActions.slice(0, 3) : []
                    NotificationActionButton {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        buttonText: modelData.text
                        urgency: root.notificationObject?.urgency ?? NotificationUrgency.Normal
                        onClicked: if (root.notificationObject) Notifications.attemptInvokeAction(root.notificationObject.notificationId, modelData.identifier)
                    }
                }
            }

            Loader {
                Layout.fillWidth: true
                active: root.expanded
                asynchronous: true
                visible: active
                Layout.preferredHeight: item?.implicitHeight ?? 48
                sourceComponent: ColumnLayout { // Expanded content
                id: expandedContentColumn
                Layout.fillWidth: true


                StyledText { // Notification body (expanded)
                    id: notificationBodyText
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Layout.fillWidth: true
                    font.pixelSize: root.fontSize
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    maximumLineCount: root.expandedBodyLineCount
                    textFormat: Text.StyledText
                    text: {
                        return root.formattedBody
                    }

                    onLinkActivated: (link) => {
                        if (/^https?:\/\//i.test(link)) Qt.openUrlExternally(link)
                        GlobalStates.sidebarRightOpen = false
                    }
                    
                    PointingHandLinkHover {}
                }

                Item {
                    Layout.fillWidth: true
                    implicitWidth: actionsFlickable.implicitWidth
                    implicitHeight: actionsFlickable.implicitHeight

                    layer.enabled: false
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: actionsFlickable.width
                            height: actionsFlickable.height
                            radius: 16
                        }
                    }

                    ScrollEdgeFade {
                        target: actionsFlickable
                        vertical: false
                    }

                    StyledFlickable { // Notification actions
                        id: actionsFlickable
                        anchors.fill: parent
                        implicitHeight: actionRowLayout.implicitHeight
                        contentWidth: actionRowLayout.implicitWidth

                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        Behavior on height {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        Behavior on implicitHeight {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        RowLayout {
                            id: actionRowLayout
                            Layout.alignment: Qt.AlignBottom

                            NotificationActionButton {
                                Layout.fillWidth: true
                                buttonText: Translation.tr("Close")
                                urgency: notificationObject?.urgency ?? NotificationUrgency.Normal
                                implicitWidth: ((notificationObject?.actions?.length ?? 0) == 0) ? ((actionsFlickable.width - actionRowLayout.spacing) / 2) :
                                    (contentItem.implicitWidth + leftPadding + rightPadding)

                                onClicked: {
                                    root.destroyWithAnimation()
                                }

                                contentItem: MaterialSymbol {
                                    iconSize: Appearance.font.pixelSize.larger
                                    horizontalAlignment: Text.AlignHCenter
                                    color: ((notificationObject?.urgency ?? NotificationUrgency.Normal) == NotificationUrgency.Critical) ?
                                        Appearance.m3colors.m3onSecondaryContainer : Appearance.m3colors.m3onSurface
                                    text: "close"
                                }
                            }

                            Repeater {
                                id: actionRepeater
                                model: Notifications.visibleActions(notificationObject)
                                NotificationActionButton {
                                    id: notifAction
                                    required property var modelData
                                    Layout.fillWidth: true
                                    buttonText: modelData.text
                                    urgency: notificationObject?.urgency ?? NotificationUrgency.Normal
                                    onClicked: {
                                        if (notificationObject) Notifications.attemptInvokeAction(notificationObject.notificationId, modelData.identifier);
                                    }
                                }
                            }

                            NotificationActionButton {
                                Layout.fillWidth: true
                                urgency: notificationObject?.urgency ?? NotificationUrgency.Normal
                                implicitWidth: ((notificationObject?.actions?.length ?? 0) == 0) ? ((actionsFlickable.width - actionRowLayout.spacing) / 2) :
                                    (contentItem.implicitWidth + leftPadding + rightPadding)

                                onClicked: {
                                    Quickshell.clipboardText = notificationObject?.body ?? ""
                                    copyIcon.text = "inventory"
                                    copyIconTimer.restart()
                                }

                                Timer {
                                    id: copyIconTimer
                                    interval: 1500
                                    repeat: false
                                    onTriggered: {
                                        copyIcon.text = "content_copy"
                                    }
                                }

                                contentItem: MaterialSymbol {
                                    id: copyIcon
                                    iconSize: Appearance.font.pixelSize.larger
                                    horizontalAlignment: Text.AlignHCenter
                                    color: ((notificationObject?.urgency ?? NotificationUrgency.Normal) == NotificationUrgency.Critical) ?
                                        Appearance.m3colors.m3onSecondaryContainer : Appearance.m3colors.m3onSurface
                                    text: "content_copy"
                                }
                            }
                            
                        }
                    }
                }
            }
            }
        }
    }
}
