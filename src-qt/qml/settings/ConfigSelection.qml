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
    property alias segments: choices.segments
    property alias currentIndex: choices.currentIndex
    readonly property real choicesFullWidth: choices.naturalWidth > 0 ? choices.naturalWidth : choices.implicitWidth
    readonly property bool stacked: width > 0 && (label.implicitWidth + choicesFullWidth + 40) > width
    readonly property bool wrapped: stacked && width > 0 && choicesFullWidth > (width - 24)
    signal activated(int index)

    width: parent ? parent.width : 0
    implicitHeight: stacked
        ? Math.max(84, 10 + label.implicitHeight + 8 + choices.implicitHeight + 10)
        : Math.max(52, choices.implicitHeight + 12)
    opacity: enabled ? 1 : 0.38

    StyledText {
        id: label
        x: 12
        y: root.stacked ? 10 : Math.round((root.height - height) / 2)
        width: root.stacked
            ? Math.max(0, root.width - 24)
            : Math.max(0, choices.x - 24)
        text: root.text
        elide: Text.ElideRight
    }

    SegmentedControl {
        id: choices
        x: root.stacked ? 12 : Math.max(6, root.width - width - 6)
        y: root.stacked
            ? (10 + label.implicitHeight + 8)
            : Math.round((root.height - height) / 2)
        wrap: root.wrapped
        maxWidth: root.wrapped ? Math.max(120, root.width - 24) : 0
        segmentHeight: 32
        horizontalPadding: segments.length >= 4 ? 12 : 14
        enabled: root.enabled
        onActivated: (index) => root.activated(index)
    }
}
