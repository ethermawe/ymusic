import QtQuick
import QtQuick.Templates as T
import ymusic.ui

T.AbstractButton {
    id: root

    property string symbol
    property bool selected: false
    property color badgeColor: Appearance.colors.primaryContainer
    property color badgeIconColor: Appearance.colors.onPrimaryContainer
    property alias trailing: trailingSlot.data
    property string iconShape: "cookie9"

    implicitHeight: 42
    hoverEnabled: true
    focusPolicy: Qt.TabFocus

    background: Item {
        // State layer on hover
        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.full
            color: !root.selected && root.down ? Qt.rgba(1, 1, 1, 0.08)
                 : (!root.selected && root.hovered ? Qt.rgba(1, 1, 1, 0.04) : "transparent")

            Behavior on color {
                ElementMoveFastColor {}
            }
        }

        // Selected pill indicator
        Rectangle {
            id: pill
            property real openness: root.selected ? 1 : 0

            anchors.centerIn: parent
            width: parent.width * (0.35 + 0.65 * openness)
            height: parent.height
            opacity: root.selected ? 1 : 0
            visible: opacity > 0
            radius: height / 2
            color: root.down ? Appearance.colors.secondaryContainer
                 : (root.hovered ? Appearance.colors.secondaryContainer : Qt.rgba(Appearance.colors.primary.r, Appearance.colors.primary.g, Appearance.colors.primary.b, 0.16))
            border.width: root.selected ? 1 : 0
            border.color: Qt.rgba(Appearance.colors.primary.r, Appearance.colors.primary.g, Appearance.colors.primary.b, 0.3)

            Behavior on openness {
                ElementMoveSmall {}
            }
            Behavior on opacity {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }
            Behavior on color {
                ElementMoveFastColor {}
            }
        }
    }

    contentItem: Item {
        Row {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            spacing: 12

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 24
                height: 24

                MaterialShape {
                    anchors.centerIn: parent
                    width: 32
                    height: 32
                    shape: root.iconShape
                    color: Appearance.colors.primary
                    opacity: root.selected || root.hovered ? 1 : 0
                    scale: root.selected || root.hovered ? 1 : 0.55
                    spinAngle: root.hovered ? 24 : 0

                    Behavior on opacity {
                        NumberAnimation { duration: Appearance.reduceMotion ? 0 : 160 }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: Appearance.reduceMotion ? 0 : 360
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.6
                        }
                    }
                    Behavior on spinAngle {
                        NumberAnimation {
                            duration: Appearance.reduceMotion ? 0 : 380
                            easing.type: Easing.OutBack
                        }
                    }
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.symbol
                    iconSize: root.selected || root.hovered ? 18 : 20
                    color: root.selected || root.hovered ? Appearance.colors.onPrimary : Appearance.colors.onSurfaceVariant
                    rotation: root.hovered ? -10 : 0
                    Behavior on rotation {
                        NumberAnimation {
                            duration: Appearance.reduceMotion ? 0 : 380
                            easing.type: Easing.OutBack
                        }
                    }
                    Behavior on iconSize {
                        NumberAnimation { duration: Appearance.reduceMotion ? 0 : 180 }
                    }
                    Behavior on color {
                        ColorAnimation { duration: Appearance.reduceMotion ? 0 : 160 }
                    }
                }
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - 36 - trailingSlot.width)
                text: root.text
                elide: Text.ElideRight
                font.pixelSize: Appearance.fontSize.small
                font.weight: root.selected ? Font.DemiBold : Font.Normal
                color: root.selected ? Appearance.colors.primary
                     : (root.hovered ? Appearance.colors.onSurface : Appearance.colors.onSurfaceVariant)
            }

            Row {
                id: trailingSlot
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
