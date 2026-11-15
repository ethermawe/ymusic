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

ShaderEffect {
    id: root

    property color color: Appearance.colors.primary
    property color trackColor: Qt.rgba(color.r, color.g, color.b, 0.24)
    property real thickness: 2.5
    property real amplitude: 2
    property real wavelength: 16
    property real progress: 1
    property real speed: 0.35

    property size itemSize: Qt.size(width, height)
    property real radius: Math.max(1, Math.min(width, height) / 2 - amplitude - thickness / 2 - 0.5)
    property real waves: appSettings.noShapes ? 0 : Math.max(5, Math.round(2 * Math.PI * radius / wavelength))
    property real phase: visible ? (waves * speed * UiState.spin) % (2 * Math.PI) : 0

    fragmentShader: "qrc:/shaders/squiggle_ring.frag.qsb"
}
