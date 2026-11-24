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

import QtQuick
import QtQuick.Controls.Basic
import ymusic.ui

ItemDelegate {
    id: root

    required property var option
    property bool selected: false
    readonly property bool isAuto: option.id === "auto"
    readonly property bool isUserTheme: option.id.startsWith("user:")
    signal deleteRequested()

    implicitWidth: 124
    implicitHeight: 104
    padding: 0
    hoverEnabled: true

    scale: down ? 0.94 : (hovered ? 1.04 : 1.0)
    Behavior on scale { Bounce {} }

    background: Item {}

    contentItem: Column {
        spacing: 6

        Item {
            width: root.width
            height: 76

            Rectangle {
                anchors.fill: parent
                radius: 16
                color: root.option.window
                border.width: root.selected ? 3 : 1
                border.color: root.selected ? Appearance.colors.primary
                            : root.isAuto ? Qt.rgba(Appearance.colors.primary.r, Appearance.colors.primary.g, Appearance.colors.primary.b, 0.55)
                            : Qt.rgba(1, 1, 1, 0.14)

                Behavior on border.width {
                    NumberAnimation { duration: Appearance.duration(140) }
                }

                // Sidebar preview bars
                Column {
                    x: 9
                    y: 12
                    spacing: 5

                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            width: 10
                            height: 4
                            radius: 2
                            color: root.option.text
                            opacity: 0.35
                        }
                    }
                }

                // Page preview
                Rectangle {
                    x: 26
                    y: 8
                    width: parent.width - 34
                    height: parent.height - 16
                    radius: 9
                    color: root.option.page

                    Rectangle {
                        x: 8
                        y: 9
                        width: parent.width * 0.62
                        height: 5
                        radius: 2.5
                        color: root.option.text
                        opacity: 0.85
                    }
                    Rectangle {
                        x: 8
                        y: 19
                        width: parent.width * 0.4
                        height: 5
                        radius: 2.5
                        color: root.option.text
                        opacity: 0.45
                    }
                    Row {
                        x: 8
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 8
                        spacing: 4

                        MaterialShape { width: 13; height: 13; shape: "flower"; color: root.option.primary }
                        MaterialShape { width: 13; height: 13; shape: "clover4"; color: root.option.secondary }
                        MaterialShape { width: 13; height: 13; shape: "cookie9"; color: root.option.tertiary }
                    }
                }
            }

            // Selected checkmark badge
            MaterialShape {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: -6
                width: 26
                height: 26
                shape: "cookie9"
                color: Appearance.colors.primary
                spinAngle: root.selected ? 0 : -90
                scale: root.selected ? 1 : 0
                visible: scale > 0.01

                Behavior on scale {
                    SpringAnimation { spring: 5; damping: 0.28; epsilon: 0.005 }
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "check"
                    iconSize: 16
                    color: Appearance.colors.onPrimary
                }
            }

            IconButton {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: -6
                visible: root.isUserTheme && (root.hovered || root.selected)
                symbol: "close"
                size: 22
                iconSize: 13
                colBackground: Appearance.colors.errorContainer
                colBackgroundHover: Appearance.colors.error
                iconColor: hovered ? Appearance.colors.onError : Appearance.colors.onErrorContainer
                tooltip: "Удалить тему"
                onClicked: root.deleteRequested()
            }
        }

        StyledText {
            width: root.width
            horizontalAlignment: Text.AlignHCenter
            text: root.option.name
            elide: Text.ElideRight
            font.pixelSize: Appearance.fontSize.smaller
            font.weight: root.selected ? Font.DemiBold : Font.Normal
            color: root.selected ? Appearance.colors.primary : Appearance.colors.onSurface
        }
    }
}
