import QtQuick
import QtQuick.Controls.Basic
import ymusic.ui

Item {
    id: root

    property bool expanded: false
    readonly property string symbol: backend.volume <= 0.001 ? "volume_off"
        : backend.volume <= 0.34 ? "volume_mute"
        : backend.volume <= 0.67 ? "volume_down" : "volume_up"

    implicitWidth: pill.width
    implicitHeight: 34

    ToolTip {
        id: volumeTip
        parent: root
        x: (root.width - width) / 2
        y: -height - 10
        visible: root.visible && pillHover.hovered
        delay: 250
        padding: 9
        horizontalPadding: 14
        text: Math.round(backend.volume * 100) + "%"
        contentItem: Text {
            text: volumeTip.text
            font.family: Appearance.fontFamily
            font.pixelSize: Appearance.fontSize.smaller
            font.weight: Font.DemiBold
            color: Appearance.colors.onPrimaryContainer
            horizontalAlignment: Text.AlignHCenter
        }
        background: Rectangle {
            radius: height / 2
            color: Appearance.colors.primaryContainer
            border.width: 1
            border.color: Appearance.colors.outlineVariant
        }
    }
    WheelHandler {
        onWheel: (event) => {
            backend.setVolume(Math.max(0, Math.min(1, backend.volume + event.angleDelta.y / 120 * 0.05)));
            event.accepted = true;
        }
    }

    Rectangle {
        id: pill
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: root.expanded ? 154 : 34
        height: 34
        radius: height / 2
        color: root.expanded ? Appearance.colors.surfaceContainerHighest : "transparent"
        border.width: root.expanded ? 1 : 0
        border.color: Qt.rgba(1, 1, 1, 0.1)
        clip: true

        Behavior on width {
            ElementMoveSmall {}
        }
        Behavior on color {
            ElementMoveFastColor {}
        }

        HoverHandler {
            id: pillHover
            onHoveredChanged: {
                if (!hovered && !slider.isDragging) {
                    root.expanded = false;
                }
            }
        }

        // Slider inside expanding capsule
        StyledSlider {
            id: slider
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.right: button.left
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.expanded && pill.width > 80 ? 1.0 : 0.0
            visible: opacity > 0.0
            value: backend.volume
            trackHeight: 3
            activeTrackHeight: 5
            fillColor: Appearance.colors.onSurface
            hoverFillColor: Appearance.colors.primary
            onUserSeek: (fraction) => backend.setVolume(fraction)
            onIsDraggingChanged: {
                if (!isDragging && !pillHover.hovered) root.expanded = false;
            }

            Behavior on opacity {
                NumberAnimation { duration: 140 }
            }
        }

        // Speaker icon button
        IconButton {
            id: button
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            size: 34
            iconSize: 20
            symbol: root.symbol
            iconColor: root.expanded ? Appearance.colors.primary : Appearance.colors.onSurfaceVariant
            activeIconColor: Appearance.colors.primary
            onClicked: {
                if (root.expanded) {
                    backend.toggleMute();
                } else {
                    root.expanded = true;
                }
            }
        }
    }
}
