pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

Item {
    id: root

    property MaterialScheme scheme: Appearance.colors
    property bool expanded: false
    readonly property string symbol: backend.volume <= 0.01 ? "volume_off"
        : backend.volume <= 0.34 ? "volume_mute"
        : backend.volume <= 0.67 ? "volume_down" : "volume_up"

    implicitWidth: 32
    implicitHeight: 32

    WheelHandler {
        onWheel: (event) => {
            backend.setVolume(Math.max(0, Math.min(1, backend.volume + event.angleDelta.y / 120 * 0.05)))
            event.accepted = true
        }
    }

    Rectangle {
        id: pill
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: root.expanded ? 172 : 32
        height: root.expanded ? 42 : 32
        radius: Appearance.rounding.normal
        color: Qt.alpha(root.scheme.surfaceContainerHighest, root.expanded ? 1 : 0)
        z: 3

        Behavior on width { ElementMoveSmall {} }
        Behavior on height { ElementMoveSmall {} }
        Behavior on color { ElementMoveFastColor {} }

        HoverHandler {
            id: pillHover
            onHoveredChanged: if (!hovered && !slider.pressed) root.expanded = false
        }

        StyledSlider {
            id: slider
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.right: button.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.expanded && pill.width > 100 ? 1 : 0
            visible: opacity > 0
            scheme: root.scheme
            trackThickness: 8
            handleLength: 20
            showStopIndicator: false
            showValueTip: true
            enabled: !(backend.sleepTimerRunning && backend.sleepTimerFade === "fade")
            value: backend.volume
            onMoved: backend.setVolume(value)
            onPressedChanged: if (!pressed && !pillHover.hovered) root.expanded = false

            Behavior on opacity {
                NumberAnimation { duration: Appearance.duration(150) }
            }
        }

        IconButton {
            id: button
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            size: 32
            iconSize: 20
            scheme: root.scheme
            symbol: root.symbol
            iconColor: root.expanded ? root.scheme.primary : root.scheme.onSurfaceVariant
            tooltip: root.expanded ? (backend.volume <= 0.01 ? qsTr("Включить звук") : qsTr("Выключить звук")) : qsTr("Громкость: ") + Math.round(backend.volume * 100) + "%"
            onClicked: {
                if (root.expanded) {
                    backend.toggleMute()
                } else {
                    root.expanded = true
                }
            }
        }
    }
}
