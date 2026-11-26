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

    property string trackId
    property string titleText
    property string artistsText
    property string coverUrl
    property bool current: false
    property bool available: true
    property bool isAi: false
    property MaterialScheme scheme: Appearance.colors

    implicitHeight: 54
    hoverEnabled: true
    focusPolicy: Qt.TabFocus
    padding: 6
    leftPadding: 10
    rightPadding: 10
    enabled: !current && available
    scale: down ? 0.975 : (hovered ? 1.015 : 1)

    Behavior on scale {
        enabled: !Appearance.performanceMode
        Bounce {}
    }

    background: Rectangle {
        radius: 10
        color: root.current ? Qt.alpha(root.scheme.primary, 0.09)
             : (root.hovered ? root.scheme.layer1Hover : "transparent")

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
            width: 42
            height: 42
            radius: 6
            source: root.coverUrl
            fallbackKey: root.trackId.length > 0 ? root.trackId : root.titleText
        }

        Column {
            anchors.left: art.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Item {
                width: parent.width
                height: Math.max(queueTitleLabel.implicitHeight, 16)

                readonly property bool showAiBadge: Backend.showAiLabels && root.isAi

                StyledText {
                    id: queueTitleLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, Math.max(0, parent.width - (queueAiBadge.visible ? queueAiBadge.width + 6 : 0)))
                    text: root.titleText
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.fontSize.smallie
                    font.weight: root.current ? Font.DemiBold : Font.Normal
                    color: root.current ? root.scheme.primary : root.scheme.onSurface
                }

                AiBadge {
                    id: queueAiBadge
                    visible: parent.showAiBadge
                    anchors.left: queueTitleLabel.right
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    compact: true
                    scheme: root.scheme
                }
            }
            StyledText {
                width: parent.width
                text: root.artistsText
                elide: Text.ElideRight
                font.pixelSize: Appearance.fontSize.smaller
                color: root.scheme.onSurfaceVariant
            }
        }
    }

    HoverHandler {
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
}
