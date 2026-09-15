import QtQuick
import Qt5Compat.GraphicalEffects
import qs.services
Item {
    id: root
    property bool animate: true
    property int workspace: 1
    readonly property real strength: (DesktopEffects.settings.ambient_strength ?? 35) / 100
    readonly property real speed: (DesktopEffects.settings.ambient_speed ?? 100) / 100
    clip: true
    Repeater {
        model: DesktopEffects.settings.aurora ? 3 : 0
        delegate: RadialGradient {
            id: light
            required property int index
            property real drift: 0
            width: root.width * 1.1
            height: root.height * 1.2
            x: root.width * (index * 0.35 - 0.4 + drift * 0.18)
            y: root.height * (-0.4 + index * 0.18 + drift * 0.15)
            horizontalRadius: width * 0.5
            verticalRadius: height * 0.5
            opacity: root.strength
            gradient: Gradient {
                GradientStop { position: 0; color: DesktopEffects.colors[light.index] }
                GradientStop { position: 0.5; color: Qt.alpha(DesktopEffects.colors[light.index], 0.22) }
                GradientStop { position: 1; color: "transparent" }
            }
            SequentialAnimation on drift {
                running: root.animate
                loops: Animation.Infinite
                NumberAnimation { to: 1; duration: (14000 + light.index * 3000) / root.speed; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0; duration: (17000 + light.index * 3000) / root.speed; easing.type: Easing.InOutSine }
            }
        }
    }
    Item {
        width: parent.width
        height: parent.height
        x: -(root.workspace % 10) * 6
        Behavior on x { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
        Repeater {
            model: DesktopEffects.settings.stars ? 36 : 0
            delegate: Rectangle {
                id: star
                required property int index
                x: ((index * 173 + 97) % 1000) / 1000 * root.width
                y: ((index * 239 + 31) % 1000) / 1000 * root.height
                width: index % 5 === 0 ? 3 : 1.5
                height: width
                radius: width / 2
                color: DesktopEffects.colors[index % 3]
                opacity: 0.5
                SequentialAnimation on opacity {
                    running: root.animate
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.12; duration: (2000 + star.index * 131) / root.speed; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.85; duration: (2700 + star.index * 101) / root.speed; easing.type: Easing.InOutSine }
                }
            }
        }
    }
}
