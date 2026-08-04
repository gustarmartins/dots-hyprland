import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

GroupButton {
    id: button
    property string buttonIcon: ""
    property string buttonText: ""
    property bool marquee: false

    baseHeight: 36
    baseWidth: content.implicitWidth + 46
    clickedWidth: baseWidth + 6

    buttonRadius: baseHeight / 2
    buttonRadiusPressed: Appearance.rounding.small
    colBackground: Appearance.colors.colLayer2
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colBackgroundActive: Appearance.colors.colLayer2Active
    property color colText: toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1

    contentItem: Item {
        id: content
        anchors.fill: parent
        implicitWidth: button.marquee ? 260 : contentRowLayout.implicitWidth
        implicitHeight: Math.max(contentRowLayout.implicitHeight, marqueeText.implicitHeight)

        RowLayout {
            id: contentRowLayout
            anchors.centerIn: parent
            spacing: 5
            visible: !button.marquee
            MaterialSymbol {
                visible: buttonIcon !== ""
                text: buttonIcon
                iconSize: Appearance.font.pixelSize.huge
                color: button.colText
            }
            StyledText {
                visible: buttonText !== ""
                text: buttonText
                font.pixelSize: Appearance.font.pixelSize.small
                color: button.colText
            }
        }

        MaterialSymbol {
            id: marqueeIcon
            visible: button.marquee && buttonIcon !== ""
            anchors {
                left: parent.left
                leftMargin: 13
                verticalCenter: parent.verticalCenter
            }
            text: buttonIcon
            iconSize: Appearance.font.pixelSize.huge
            color: button.colText
        }

        Item {
            id: marqueeViewport
            visible: button.marquee
            clip: true
            anchors {
                left: marqueeIcon.visible ? marqueeIcon.right : parent.left
                leftMargin: marqueeIcon.visible ? 9 : 13
                right: parent.right
                rightMargin: 13
                top: parent.top
                bottom: parent.bottom
            }

            StyledText {
                id: marqueeText
                anchors.verticalCenter: parent.verticalCenter
                text: button.buttonText
                font.pixelSize: Appearance.font.pixelSize.small
                color: button.colText
                textFormat: Text.PlainText

                onTextChanged: {
                    x = 0;
                    if (marqueeAnimation.running)
                        marqueeAnimation.restart();
                }

                SequentialAnimation on x {
                    id: marqueeAnimation
                    running: button.marquee && button.visible && marqueeText.implicitWidth > marqueeViewport.width
                    loops: Animation.Infinite
                    PauseAnimation { duration: 1800 }
                    NumberAnimation {
                        from: 0
                        to: marqueeViewport.width - marqueeText.implicitWidth
                        duration: Math.max(1800, (marqueeText.implicitWidth - marqueeViewport.width) * 28)
                        easing.type: Easing.Linear
                    }
                    PauseAnimation { duration: 1400 }
                    PropertyAction { value: 0 }
                }
            }
        }
    }

}
