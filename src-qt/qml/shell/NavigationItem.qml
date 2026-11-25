/*
 * Swiftify, a spotify player for desktop
 * Copyright (C) 2026  shred0s
 * Modified for ymusic (2026).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import ymusic.ui

T.AbstractButton {
    id: root

    property string symbol
    property url artworkUrl
    property string fallbackKey: text
    property bool selected: false
    property bool showArtwork: false
    property bool compact: false
    property string iconShape: "cookie9"
    property bool keepsShape: false
    property alias trailing: trailingSlot.data
    property int indent: 0

    implicitHeight: 40
    hoverEnabled: true
    focusPolicy: Qt.TabFocus

    background: Item {
        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.full
            color: !root.selected && root.down ? Appearance.colors.layer1Active
                 : Qt.alpha(Appearance.colors.layer1Hover, !root.selected && root.hovered ? 1 : 0)

            Behavior on color {
                ElementMoveFastColor {}
            }
        }

        WavyClip {
            id: pill

            property real openness: root.selected ? 1 : 0

            anchors.centerIn: parent
            width: parent.width * (0.35 + 0.65 * Math.min(openness, 1))
            height: parent.height
            opacity: root.selected ? 1 : 0
            visible: opacity > 0
            radius: height / 2
            wavy: root.selected && root.hovered
            depth: 2
            wavelength: 14

            Behavior on openness {
                enabled: !Appearance.performanceMode
                ElementMove {}
            }
            Behavior on opacity {
                NumberAnimation { duration: Appearance.duration(160); easing.type: Easing.OutCubic }
            }

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: root.down ? Appearance.colors.secondaryContainerActive
                     : root.hovered ? Appearance.colors.secondaryContainerHover : Appearance.colors.secondaryContainer

                Behavior on color {
                    ElementMoveFastColor {}
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            visible: root.visualFocus
            radius: Appearance.rounding.full
            color: "transparent"
            border.width: 2
            border.color: Appearance.colors.secondary
        }
    }

    contentItem: Item {
        Item {
            id: iconSlot
            x: root.compact ? Math.round((parent.width - width) / 2) : 14 + root.indent
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 24

            MaterialSymbol {
                anchors.centerIn: parent
                Reveal.shown: !root.selected && !root.showArtwork
                text: root.symbol
                iconSize: 22
                weight: root.hovered ? 600 : 400
                color: Appearance.colors.onSurfaceVariant
            }
            ShapeIcon {
                anchors.centerIn: parent
                Reveal.shown: root.selected && !root.showArtwork
                Reveal.overshoot: 2.4
                size: 30
                iconSize: 16
                shape: root.iconShape
                keepsShape: root.keepsShape
                symbol: root.symbol
                color: Appearance.colors.primary
                iconColor: Appearance.colors.onPrimary
                hovered: root.hovered
            }
            ArtworkImage {
                anchors.centerIn: parent
                visible: root.showArtwork
                width: 24
                height: 24
                radius: 5
                source: root.artworkUrl
                fallbackKey: root.fallbackKey
            }
        }

        StyledText {
            visible: !root.compact
            anchors.left: iconSlot.right
            anchors.leftMargin: 12
            anchors.right: trailingSlot.visible ? trailingSlot.left : parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            elide: Text.ElideRight
            font.pixelSize: Appearance.fontSize.small
            font.weight: root.selected ? Font.DemiBold : Font.Medium
            color: root.selected ? Appearance.colors.onSecondaryContainer : Appearance.colors.onSurface
        }

        Row {
            id: trailingSlot
            visible: !root.compact && children.length > 0
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
        }
    }

    Loader {
        anchors.fill: parent
        active: root.compact && root.hovered && root.text.length > 0
        sourceComponent: StyledToolTip {
            visible: true
            text: root.text
        }
    }

    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }
}
