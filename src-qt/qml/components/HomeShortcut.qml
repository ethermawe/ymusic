import QtQuick
import QtQuick.Templates as T
import ymusic.ui

T.AbstractButton {
    id: root

    property string title
    property string subtitle
    property string symbol
    property color badgeColor: Appearance.colors.primaryContainer
    property color badgeIconColor: Appearance.colors.onPrimaryContainer

    implicitHeight: 64
    hoverEnabled: true
    focusPolicy: Qt.TabFocus
    scale: down ? 0.96 : (hovered ? 1.02 : 1)

    Behavior on scale {
        Bounce {}
    }

    background: Rectangle {
        radius: Appearance.rounding.normal
        color: root.hovered ? Appearance.colors.surfaceContainerHighest : Appearance.colors.surfaceContainerHigh
        border.width: 1
        border.color: root.hovered ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.04)

        Behavior on color {
            ElementMoveFastColor {}
        }
    }

    contentItem: Item {
        // Icon badge
        Rectangle {
            id: badge
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 42
            height: 42
            radius: Appearance.rounding.small
            color: root.badgeColor

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.symbol
                iconSize: 22
                color: root.badgeIconColor
            }
        }

        // Text details
        Column {
            anchors.left: badge.right
            anchors.leftMargin: 14
            anchors.right: chevron.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            StyledText {
                width: parent.width
                text: root.title
                elide: Text.ElideRight
                font.pixelSize: Appearance.fontSize.small
                font.weight: Font.DemiBold
            }

            StyledText {
                width: parent.width
                text: root.subtitle
                elide: Text.ElideRight
                font.pixelSize: Appearance.fontSize.smaller
                color: Appearance.colors.onSurfaceVariant
            }
        }

        // Chevron
        MaterialSymbol {
            id: chevron
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: "chevron_right"
            iconSize: 20
            color: Appearance.colors.onSurfaceVariant
            opacity: root.hovered ? 1.0 : 0.6

            Behavior on opacity {
                NumberAnimation { duration: 140 }
            }
        }
    }
}
