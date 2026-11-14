pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import ymusic.ui

T.AbstractButton {
    id: root

    property string shape: "circle"
    property string morphTo: shape
    property bool morphed: false
    property color color: Appearance.colors.primary
    property color hoverColor: color
    property real spinRate: 0
    property string tooltip

    property real morph: morphed ? 1 : 0

    Behavior on morph {
        enabled: !Appearance.performanceMode
        SpringAnimation { spring: 3.5; damping: 0.3; epsilon: 0.002 }
    }

    padding: 0
    hoverEnabled: true
    focusPolicy: Qt.TabFocus
    opacity: enabled ? 1 : 0.38
    scale: down ? 0.88 : 1

    Behavior on scale {
        enabled: !Appearance.performanceMode
        SpringAnimation { spring: 7; damping: 0.24; epsilon: 0.002 }
    }

    background: Item {
        MaterialShape {
            readonly property real room: Math.round(parent.width * 0.16)

            anchors.fill: parent
            anchors.margins: -room
            extent: parent.width / Math.max(1, parent.width + 2 * room)
            shape: root.shape
            morphTo: root.morphTo
            morph: root.morph
            color: root.hovered ? root.hoverColor : root.color
            spinRate: root.spinRate

            Behavior on color {
                ElementMoveFastColor {}
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: root.tooltip.length > 0 && root.hovered
        sourceComponent: StyledToolTip {
            visible: true
            text: root.tooltip
        }
    }

    HoverHandler {
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
}
