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
    property bool shown: false
    property real lifeProgress: 1.0
    readonly property int durationMs: 2600

    readonly property string effectiveSymbol: {
        const lower = (root.text || "").toLowerCase()
        if (lower.indexOf("загруз") >= 0 || lower.indexOf("скачан") >= 0) return "download_done"
        if (lower.indexOf("скопирован") >= 0 || lower.indexOf("ссылка") >= 0) return "content_copy"
        if (lower.indexOf("перезагруж") >= 0 || lower.indexOf("сброшен") >= 0) return "refresh"
        if (lower.indexOf("не нравится") >= 0 || lower.indexOf("скрыт") >= 0) return "thumb_down"
        if (lower.indexOf("удалён") >= 0 || lower.indexOf("удален") >= 0) return "delete"
        return "check"
    }

    function show(message: string) {
        root.text = message
        root.shown = true
        progressAnim.stop()
        root.lifeProgress = 1.0
        hide.interval = root.durationMs
        hide.restart()
        if (!Appearance.performanceMode) {
            progressAnim.restart()
        }
    }

    function dismiss() {
        hide.stop()
        progressAnim.stop()
        root.shown = false
    }

    implicitWidth: Math.min(520, row.implicitWidth + 32)
    implicitHeight: 44
    visible: opacity > 0.01
    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0.94

    property real slideY: shown ? 0 : -10
    transform: Translate { y: root.slideY }

    Behavior on opacity {
        NumberAnimation { duration: Appearance.duration(root.shown ? 200 : 160); easing.type: Easing.OutCubic }
    }
    Behavior on scale {
        ElementMoveSmall {}
    }
    Behavior on slideY {
        enabled: !Appearance.performanceMode
        ElementMoveSmall {}
    }

    NumberAnimation {
        id: progressAnim
        target: root
        property: "lifeProgress"
        from: 1.0
        to: 0.0
        duration: root.durationMs
        easing.type: Easing.Linear
    }

    Timer {
        id: hide
        interval: root.durationMs
        onTriggered: root.dismiss()
    }

    SoftShadow {
        anchors.fill: card
        radius: card.radius
        blur: 20
        offset: Qt.vector2d(0, 6)
        color: Qt.rgba(0, 0, 0, Appearance.colors.dark ? 0.42 : 0.14)
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: height / 2
        color: Appearance.colors.surfaceContainerHighest
        border.width: 1
        border.color: Qt.alpha(Appearance.colors.primary, Appearance.colors.dark ? 0.28 : 0.22)
        clip: true

        // Subtle draining accent strip inset inside the pill's flat bottom edge
        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: card.radius
            anchors.rightMargin: card.radius
            anchors.bottomMargin: 3
            height: 2
            visible: !Appearance.performanceMode && root.shown

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                radius: 1
                width: parent.width * root.lifeProgress
                color: Qt.alpha(Appearance.colors.primary, 0.72)
            }
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 10

        ShapeIcon {
            anchors.verticalCenter: parent.verticalCenter
            size: 28
            iconSize: 16
            shape: "cookie6"
            symbol: root.effectiveSymbol
            color: Appearance.colors.primaryContainer
            iconColor: Appearance.colors.onPrimaryContainer
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, 440)
            elide: Text.ElideRight
            text: root.text
            color: Appearance.colors.onSurface
            font.pixelSize: Appearance.fontSize.small
            font.weight: Font.Medium
        }
    }

    HoverHandler {
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: {
            if (!root.shown) return
            if (hovered) {
                hide.stop()
                progressAnim.pause()
            } else {
                hide.interval = Math.max(600, Math.round(root.durationMs * root.lifeProgress))
                hide.restart()
                progressAnim.resume()
            }
        }
    }

    TapHandler {
        onTapped: root.dismiss()
    }
}
