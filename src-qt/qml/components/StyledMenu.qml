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

T.Menu {
    id: root

    property MaterialScheme scheme: UiState.immersiveOpen ? PlayerStyle.darkScheme : Appearance.colors

    popupType: T.Popup.Item
    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            contentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             contentHeight + topPadding + bottomPadding)
    padding: 8
    margins: 8
    overlap: 4

    delegate: StyledMenuItem {}

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Appearance.duration(160); easing.type: Easing.OutCubic }
        NumberAnimation {
            property: "scale"
            from: Appearance.performanceMode || Appearance.reduceMotion ? 1 : 0.9
            to: 1
            duration: Appearance.motion(260)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.curves.expressiveFastSpatial
        }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; to: 0; duration: Appearance.duration(110); easing.type: Easing.InCubic }
        NumberAnimation {
            property: "scale"
            to: Appearance.performanceMode || Appearance.reduceMotion ? 1 : 0.94
            duration: Appearance.duration(110)
            easing.type: Easing.InCubic
        }
    }

    contentItem: ListView {
        implicitWidth: {
            let widest = 0
            for (let index = 0; index < root.count; ++index) {
                const entry = root.itemAt(index)
                if (entry && entry.visible) {
                    widest = Math.max(widest, entry.implicitWidth)
                }
            }
            return Math.min(widest, 440)
        }
        implicitHeight: contentHeight
        model: root.contentModel
        interactive: Window.window ? contentHeight + root.topPadding + root.bottomPadding > Window.window.height / AppSettings.zoom : false
        clip: true
        currentIndex: root.currentIndex
        spacing: 2
    }

    background: Item {
        implicitWidth: 220

        SoftShadow {
            anchors.fill: panel
            radius: panel.radius
            blur: 22
            offset: Qt.vector2d(0, 8)
            color: Qt.rgba(0, 0, 0, root.scheme.dark ? 0.38 : 0.16)
        }

        Rectangle {
            id: panel
            anchors.fill: parent
            radius: Appearance.rounding.normal
            color: root.scheme.surfaceContainerHigh
            border.width: 1
            border.color: root.scheme.layer0Border
        }
    }
}
