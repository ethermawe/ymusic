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

    property bool shown: true
    readonly property real bass: flows ? clock.energy.y : 0

    readonly property bool flows: appSettings.livingBackdrop && !Appearance.reduceMotion
    readonly property real sigma: appSettings.backdropBlur
    readonly property real renderScale: sigma > 2 ? Math.max(1 / 8, 2 / sigma) : 1
    readonly property size textureSize: Qt.size(Math.max(1, Math.ceil(width * renderScale)),
                                                Math.max(1, Math.ceil(height * renderScale)))

    function shade(index: int): color {
        const palette = PlayerStyle.palette;
        return palette.length > 0 ? palette[index % palette.length] : Appearance.colors.primary;
    }

    BackdropClock {
        id: clock
        running: root.flows && root.shown && root.visible
        playing: backend.playing
        reactivity: appSettings.backdropReactivity
    }

    Rectangle {
        anchors.fill: parent
        color: "#020203"
    }

    ShaderEffect {
        id: field
        anchors.fill: parent

        property size itemSize: Qt.size(width, height)
        property real time: root.flows ? (37 + clock.time) : 37
        property vector4d energy: root.flows ? clock.energy : Qt.vector4d(0, 0, 0, 0)
        property real lead: root.flows ? clock.lead : 0
        property color c0: root.shade(0)
        property color c1: root.shade(1)
        property color c2: root.shade(2)
        property color c3: root.shade(3)
        property color c4: root.shade(4)

        fragmentShader: "qrc:/shaders/liquid_backdrop.frag.qsb"
    }

    ShaderEffectSource {
        id: fieldTexture
        anchors.fill: parent
        sourceItem: field
        hideSource: true
        visible: false
        smooth: true
        textureSize: root.textureSize
    }

    ShaderEffect {
        id: across
        anchors.fill: parent

        property variant source: fieldTexture
        property vector2d texelStep: Qt.vector2d(1 / root.textureSize.width, 0)
        property real sigma: root.sigma * root.renderScale

        fragmentShader: "qrc:/shaders/backdrop_blur.frag.qsb"
    }

    ShaderEffectSource {
        id: acrossTexture
        anchors.fill: parent
        sourceItem: across
        hideSource: true
        visible: false
        smooth: true
        textureSize: root.textureSize
    }

    ShaderEffect {
        id: down
        anchors.fill: parent

        property variant source: acrossTexture
        property vector2d texelStep: Qt.vector2d(0, 1 / root.textureSize.height)
        property real sigma: root.sigma * root.renderScale

        fragmentShader: "qrc:/shaders/backdrop_blur.frag.qsb"
    }

    ShaderEffectSource {
        id: blurred
        anchors.fill: parent
        sourceItem: down
        hideSource: true
        visible: false
        smooth: true
        textureSize: root.textureSize
    }

    ShaderEffect {
        anchors.fill: parent

        property variant source: blurred

        fragmentShader: "qrc:/shaders/backdrop_composite.frag.qsb"
    }
}
