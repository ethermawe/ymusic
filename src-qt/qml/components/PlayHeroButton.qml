import QtQuick
import QtQuick.Templates as T
import ymusic.ui

T.AbstractButton {
    id: root

    property bool playing: false
    property real size: 44
    property real iconSize: Math.round(size * 0.52)
    property color color: Appearance.colors.primary
    property color hoverColor: Appearance.colors.primaryHover
    property color iconColor: Appearance.colors.onPrimary

    implicitWidth: size
    implicitHeight: size
    hoverEnabled: true

    scale: down ? 0.90 : (hovered ? 1.07 : 1.0)
    Behavior on scale {
        NumberAnimation {
            duration: 220
            easing.type: Easing.OutBack
            easing.overshoot: 2.2
        }
    }

    onPlayingChanged: pop.restart()

    background: Rectangle {
        anchors.fill: parent
        radius: root.size / 2
        color: root.hovered ? root.hoverColor : root.color

        Behavior on color {
            ColorAnimation { duration: 160 }
        }

        // Ambient glow
        Rectangle {
            anchors.centerIn: parent
            width: parent.width + 8
            height: parent.height + 8
            radius: width / 2
            z: -1
            color: root.color
            opacity: root.hovered ? 0.35 : 0.15
            Behavior on opacity {
                NumberAnimation { duration: 200 }
            }
        }
    }

    contentItem: Item {
        anchors.fill: parent

        MaterialSymbol {
            id: glyph
            anchors.centerIn: parent
            // Center play arrow visually slightly to the right
            anchors.horizontalCenterOffset: root.playing ? 0 : 1
            text: root.playing ? "pause" : "play_arrow"
            iconSize: root.iconSize
            color: root.iconColor

            NumberAnimation {
                id: pop
                target: glyph
                property: "scale"
                from: 0.6
                to: 1.0
                duration: 380
                easing.type: Easing.OutBack
                easing.overshoot: 2.4
            }
        }
    }
}
