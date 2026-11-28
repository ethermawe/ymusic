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

    property string trackTitle: ""
    property string trackArtists: ""
    property url artworkUrl: ""
    property bool available: true
    property bool current: false
    property bool isAi: false
    property MaterialScheme scheme: PlayerStyle.darkScheme

    enabled: !current
    hoverEnabled: true
    focusPolicy: Qt.TabFocus
    padding: 8
    leftPadding: 12
    rightPadding: 12
    implicitWidth: 300
    implicitHeight: 54 + topPadding + bottomPadding

    background: Rectangle {
        radius: 14
        color: Qt.rgba(1, 1, 1, root.current ? 0.09 : (root.down ? 0.1 : (root.hovered ? 0.05 : 0)))

        Behavior on color {
            ElementMoveFastColor {}
        }
    }

    contentItem: Item {
        opacity: root.available ? 1 : 0.38

        ArtworkImage {
            id: art
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 54
            height: 54
            radius: 8
            source: root.artworkUrl
            placeholderSymbol: "music_note"
            fallbackKey: root.trackTitle
        }

        Column {
            anchors.left: art.right
            anchors.leftMargin: 13
            anchors.right: speaker.visible ? speaker.left : parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            Item {
                width: parent.width
                height: Math.max(immersiveQueueTitle.implicitHeight, 18)

                readonly property bool showAiBadge: Backend.showAiLabels && root.isAi

                ScrollingText {
                    id: immersiveQueueTitle
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - (immersiveQueueAiBadge.visible ? immersiveQueueAiBadge.width + 6 : 0))
                    text: root.trackTitle
                    horizontalAlignment: Text.AlignLeft
                    font.pixelSize: Appearance.fontSize.small
                    font.weight: root.current ? Font.Bold : Font.DemiBold
                    color: root.current ? "white" : Qt.rgba(1, 1, 1, 0.86)
                    running: root.current || root.hovered
                }

                AiBadge {
                    id: immersiveQueueAiBadge
                    visible: parent.showAiBadge
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    compact: true
                    scheme: root.scheme
                }
            }
            StyledText {
                width: parent.width
                text: root.trackArtists
                elide: Text.ElideRight
                font.pixelSize: Appearance.fontSize.smallie
                color: Qt.rgba(1, 1, 1, 0.62)
            }
        }

        MaterialSymbol {
            id: speaker
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            Reveal.shown: root.current
            text: "volume_up"
            fill: 1
            iconSize: 20
            color: root.scheme.primary
        }
    }

    HoverHandler {
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
}
