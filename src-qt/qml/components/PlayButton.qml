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

ShapeButton {
    id: root

    property real size: 48
    property bool playing: backend.playing
    property color iconColor: Appearance.colors.onPrimary
    property real iconSize: Math.round((width > 0 ? Math.min(width, height) : size) * 0.25) * 2

    implicitWidth: size
    implicitHeight: size

    shape: "softCookie"
    morphTo: "cookie9"
    morphed: playing
    spinRate: 25
    tooltip: playing ? qsTr("Пауза") : qsTr("Воспроизвести")

    onPlayingChanged: if (!Appearance.performanceMode) pop.restart()
    onClicked: if (!playing) UiState.burst(root, "play")

    contentItem: Item {
        MaterialSymbol {
            id: glyph
            anchors.fill: parent
            text: root.playing ? "pause" : "play_arrow"
            iconSize: root.iconSize
            fill: 1
            color: root.iconColor
        }
    }

    NumberAnimation {
        id: pop
        target: glyph
        property: "scale"
        from: 0.55
        to: 1
        duration: 480
        easing.type: Easing.OutBack
        easing.overshoot: 2.6
    }
}
