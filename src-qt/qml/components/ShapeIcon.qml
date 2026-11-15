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

    property string shape: "cookie9"
    property bool keepsShape: false
    property string hoverShape
    property bool hovered: false
    property string symbol
    property real size: 40
    property real iconSize: Math.round(size * 0.5)
    property real fill: 1
    property color color: Appearance.colors.secondaryContainer
    property color iconColor: Appearance.colors.onSecondaryContainer

    readonly property string target: hovered && hoverShape.length > 0 ? hoverShape : shape
    readonly property bool concentricHearts: target === "heart" && symbol === "favorite" && fill >= 0.5
    property string fromShape: target
    property real progress: 1
    property bool settled: false

    implicitWidth: size
    implicitHeight: size

    Component.onCompleted: settled = true

    onTargetChanged: {
        if (!settled || Appearance.performanceMode) {
            fromShape = target
            progress = 1
            return
        }
        fromShape = progress >= 0.5 ? body.morphTo : body.shape
        progress = 0
        settle.restart()
    }

    NumberAnimation {
        id: settle
        target: root
        property: "progress"
        to: 1
        duration: 460
        easing.type: Easing.OutBack
        easing.overshoot: 2.2
    }

    MaterialShape {
        id: body
        anchors.fill: parent
        keepsShape: root.keepsShape
        shape: root.fromShape
        morphTo: root.target
        morph: root.progress
        color: root.color
        extent: 0.92
        spinAngle: root.hovered ? 24 : 0

        Behavior on spinAngle {
            enabled: !Appearance.performanceMode
            Bounce {}
        }
        Behavior on color {
            ElementMoveFastColor {}
        }
    }

    MaterialShape {
        visible: root.concentricHearts
        anchors.centerIn: parent
        // Shift slightly down toward the widest cavity so top cleft, sides, and tip keep uniform thickness.
        anchors.verticalCenterOffset: root.size * 0.055
        width: root.size * 0.54
        height: root.size * 0.54
        keepsShape: true
        shape: "heart"
        color: root.iconColor
        extent: 0.92
        spinAngle: root.hovered ? -10 : 0

        Behavior on spinAngle {
            enabled: !Appearance.performanceMode
            Bounce {}
        }
        Behavior on color {
            ElementMoveFastColor {}
        }
    }

    MaterialSymbol {
        visible: !root.concentricHearts
        anchors.centerIn: parent
        // Heart's deep top cleft places its visual pocket slightly below geometric center.
        anchors.verticalCenterOffset: root.target === "heart" ? Math.round(root.size * 0.07) : 0
        text: root.symbol
        iconSize: root.iconSize
        fill: root.fill
        color: root.iconColor
        rotation: root.hovered ? -10 : 0

        Behavior on rotation {
            enabled: !Appearance.performanceMode
            Bounce {}
        }
    }
}
