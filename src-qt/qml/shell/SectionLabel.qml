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
import ymusic.ui

Item {
    id: root

    property string text
    property bool compact: false
    property alias trailing: trailingSlot.data

    implicitHeight: compact ? 20 : 34
    implicitWidth: label.implicitWidth + 32

    StyledText {
        id: label
        visible: !root.compact
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        font.pixelSize: Appearance.fontSize.smaller
        font.weight: Font.DemiBold
        color: Appearance.colors.onSurfaceVariant
    }

    WavyLine {
        anchors.left: root.compact ? parent.left : label.right
        anchors.leftMargin: root.compact ? 12 : 10
        anchors.right: (!root.compact && trailingSlot.width > 0) ? trailingSlot.left : parent.right
        anchors.rightMargin: (!root.compact && trailingSlot.width > 0) ? 6 : 12
        anchors.verticalCenter: parent.verticalCenter
        color: Appearance.colors.outlineVariant
    }

    Row {
        id: trailingSlot
        visible: !root.compact
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
    }
}
