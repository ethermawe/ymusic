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

FrameAnimation {
    id: root

    property bool active: false
    property real speed: 1
    property real period: 2 * Math.PI
    property real value: 0
    property real rate: active && !Appearance.reduceMotion && !UiState.pointerResting ? speed : 0

    Behavior on rate {
        NumberAnimation { duration: 650; easing.type: Easing.InOutSine }
    }

    running: Math.abs(rate) > 0.0001
    onTriggered: value = (value + rate * frameTime) % period
}
