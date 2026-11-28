import QtQuick
import QtQuick.Controls
import ymusic.sdk

AbstractButton {
    id: root

    signal toggledTo(bool value)

    width: parent ? parent.width : 0
    implicitHeight: 52
    leftPadding: 12
    rightPadding: 12
    hoverEnabled: true
    opacity: enabled ? 1 : 0.38

    onClicked: root.toggledTo(!root.checked)

    background: Rectangle {
        radius: Theme.rounding.small
        color: root.down
            ? Theme.withAlpha(Theme.colors.onSurface, 0.12)
            : (root.hovered ? Theme.colors.layer2Hover : "transparent")

        Behavior on color {
            enabled: !Theme.performanceMode
            ColorAnimation { duration: 120 }
        }
    }

    contentItem: Item {
        StyledText {
            anchors.left: parent.left
            anchors.right: track.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            elide: Text.ElideRight
        }

        Rectangle {
            id: track
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 52
            height: 32
            radius: 16
            color: root.checked ? Theme.colors.primary : Theme.colors.surfaceContainerHigh
            border.width: root.checked ? 0 : 2
            border.color: Theme.colors.outline

            Behavior on color {
                enabled: !Theme.performanceMode
                ColorAnimation { duration: 140 }
            }

            Rectangle {
                property real thumbSize: root.down ? 28 : (root.checked ? 24 : 16)
                width: thumbSize
                height: thumbSize
                radius: thumbSize / 2
                anchors.verticalCenter: parent.verticalCenter
                x: root.checked
                    ? parent.width - width - (parent.height - width) / 2
                    : (parent.height - width) / 2
                color: root.checked ? Theme.colors.onPrimary : Theme.colors.outline

                Behavior on x {
                    enabled: !Theme.performanceMode && !Theme.reduceMotion
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
                Behavior on thumbSize {
                    enabled: !Theme.performanceMode && !Theme.reduceMotion
                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                }
                Behavior on color {
                    enabled: !Theme.performanceMode
                    ColorAnimation { duration: 140 }
                }
            }
        }
    }

    HoverHandler {
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
}
