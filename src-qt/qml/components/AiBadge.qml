pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

Item {
    id: root

    property MaterialScheme scheme: Appearance.colors
    property bool compact: false
    property string tooltip: qsTr("Сгенерировано ИИ")
    readonly property bool hovered: hover.hovered

    implicitWidth: pill.implicitWidth
    implicitHeight: compact ? 18 : 20

    scale: hovered ? 1.06 : 1.0
    Behavior on scale {
        enabled: !Appearance.performanceMode
        Bounce {}
    }

    Rectangle {
        id: pill
        anchors.fill: parent
        implicitWidth: row.implicitWidth + (root.compact ? 10 : 12)
        implicitHeight: root.implicitHeight
        radius: Appearance.rounding.full
        color: root.hovered ? root.scheme.tertiaryContainerHover : root.scheme.tertiaryContainer
        border.width: 1
        border.color: Qt.alpha(root.scheme.onTertiaryContainer, root.hovered ? 0.28 : 0.14)

        Behavior on color {
            ElementMoveFastColor {}
        }
        Behavior on border.color {
            ElementMoveFastColor {}
        }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: root.compact ? 3 : 4

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: root.compact ? 11 : 13
                height: width

                MaterialShape {
                    anchors.fill: parent
                    visible: !AppSettings.noShapes
                    shape: root.hovered ? "sunny" : "cookie6"
                    color: Qt.alpha(root.scheme.onTertiaryContainer, 0.16)
                    spinAngle: root.hovered ? 35 : 0

                    Behavior on spinAngle {
                        enabled: !Appearance.performanceMode
                        Bounce {}
                    }
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "auto_awesome"
                    iconSize: root.compact ? 10 : 11
                    fill: 1
                    weight: 600
                    color: root.scheme.onTertiaryContainer
                    rotation: root.hovered ? -14 : 0

                    Behavior on rotation {
                        enabled: !Appearance.performanceMode
                        Bounce {}
                    }
                }
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: "AI"
                font.pixelSize: root.compact ? 10 : 11
                font.weight: Font.Bold
                font.letterSpacing: 0.4
                color: root.scheme.onTertiaryContainer
            }
        }
    }

    HoverHandler {
        id: hover
    }

    StyledToolTip {
        visible: root.hovered && root.tooltip.length > 0
        text: root.tooltip
    }
}
