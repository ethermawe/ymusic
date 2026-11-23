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
import QtQuick.Controls.Basic
import ymusic.ui

Item {
    id: root

    property bool suspended: false
    property MaterialScheme scheme: Appearance.colors
    readonly property bool hasLyrics: Boolean(UiState.lyricsLines && UiState.lyricsLines.length > 0)

    Column {
        anchors.centerIn: parent
        Reveal.shown: UiState.lyricsLoading
        spacing: 12
        LoadingSpinner { anchors.horizontalCenter: parent.horizontalCenter }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("Загрузка текста…")
            color: root.scheme.onSurfaceVariant
        }
    }

    EmptyState {
        anchors.centerIn: parent
        width: parent.width - 32
        Reveal.shown: !UiState.lyricsLoading && !root.hasLyrics
        symbol: "lyrics"
        title: qsTr("Текст недоступен")
        description: UiState.lyricsMessage.length > 0 ? UiState.lyricsMessage : qsTr("Для этого трека текст не найден")
        scheme: root.scheme
    }

    Item {
        id: headerBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 18
        anchors.rightMargin: 16
        anchors.topMargin: 14
        height: 36
        Reveal.shown: !UiState.lyricsLoading && root.hasLyrics

        StyledText {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Текст")
            font.pixelSize: Appearance.fontSize.normal
            font.weight: Font.DemiBold
            color: root.scheme.onSurface
        }

        Rectangle {
            id: jumpButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 26
            radius: 13
            width: jumpLabel.implicitWidth + 20
            visible: list.scrolledAway && UiState.lyricsSynced && UiState.activeLyricIndex >= 0
            color: jumpMouse.containsMouse ? root.scheme.primary : Qt.alpha(root.scheme.primary, 0.18)
            border.width: 1
            border.color: Qt.alpha(root.scheme.primary, 0.45)

            Behavior on color {
                ColorAnimation { duration: 140 }
            }

            StyledText {
                id: jumpLabel
                anchors.centerIn: parent
                text: qsTr("К текущей")
                font.pixelSize: 11
                font.weight: Font.DemiBold
                color: jumpMouse.containsMouse ? root.scheme.onPrimary : root.scheme.primary
            }

            MouseArea {
                id: jumpMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: list.resumeFollowing()
            }
        }
    }

    // Intro progress bar shown while playback is before the first synced lyric timestamp
    Rectangle {
        id: introProgressTrack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: headerBar.bottom
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 4
        height: visible ? 3 : 0
        radius: 1.5
        visible: !UiState.lyricsLoading && root.hasLyrics && UiState.lyricsSynced
            && UiState.activeLyricIndex < 0 && UiState.firstLyricTimeSecs > 0
        color: Qt.alpha(root.scheme.onSurface, 0.10)

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            radius: parent.radius
            width: parent.width * UiState.activeLyricProgress
            color: root.scheme.primary
        }
    }

    ListView {
        id: list
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.top: introProgressTrack.visible ? introProgressTrack.bottom : headerBar.bottom
        anchors.topMargin: 6
        Reveal.shown: !UiState.lyricsLoading && root.hasLyrics
        model: UiState.lyricsLines
        spacing: 10
        topMargin: 10
        bottomMargin: 22
        leftMargin: 14
        rightMargin: 14
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds
        cacheBuffer: 2000
        signal stepped(real delta)

        property bool autoScrolling: false
        property bool manualBrowsing: false
        property bool scrolledAway: false

        HoverHandler {
            id: pointerActivity
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            property real lastX: -1
            property real lastY: -1
            onHoveredChanged: {
                if (hovered && list.manualBrowsing) {
                    lastX = point.position.x
                    lastY = point.position.y
                    list.scheduleAutoReturn()
                }
            }
            onPointChanged: {
                if (!hovered || !list.manualBrowsing) {
                    return
                }
                const dx = point.position.x - lastX
                const dy = point.position.y - lastY
                if (dx * dx + dy * dy >= 4) {
                    lastX = point.position.x
                    lastY = point.position.y
                    list.scheduleAutoReturn()
                }
            }
        }

        Timer {
            id: autoReturnTimer
            interval: 5000
            repeat: false
            onTriggered: {
                if (!list.manualBrowsing || root.suspended || !root.visible || !UiState.lyricsSynced || !root.hasLyrics) {
                    return
                }
                if (list.dragging || list.moving || vbar.pressed || lyricsWheel.activeFlick === list
                        || pointerActivity.point.pressedButtons !== Qt.NoButton) {
                    autoReturnTimer.restart()
                    return
                }
                list.resumeFollowing()
            }
        }

        function scheduleAutoReturn() {
            if (manualBrowsing && !root.suspended && root.visible && UiState.lyricsSynced && root.hasLyrics && !dragging && !vbar.pressed) {
                autoReturnTimer.restart()
            }
        }

        function resumeFollowing() {
            autoReturnTimer.stop()
            manualBrowsing = false
            follow(true)
        }

        function updateScrolledAway() {
            const index = UiState.activeLyricIndex
            if (!UiState.lyricsSynced || index < 0) {
                scrolledAway = false
                return
            }
            const item = list.itemAtIndex(index)
            if (!item) {
                scrolledAway = true
                return
            }
            const top = item.y
            const bottom = item.y + item.height
            const viewTop = list.contentY + 8
            const viewBottom = list.contentY + list.height - 8
            scrolledAway = bottom < viewTop || top > viewBottom
        }

        onDraggingChanged: {
            if (dragging) {
                scroll.stop()
                manualBrowsing = true
                autoReturnTimer.stop()
            } else {
                scheduleAutoReturn()
            }
        }

        onContentYChanged: {
            if (!autoScrolling && !scroll.running && (moving || dragging || vbar.pressed || lyricsWheel.activeFlick === list)) {
                manualBrowsing = true
                if (!dragging && !vbar.pressed) {
                    scheduleAutoReturn()
                }
            }
            updateScrolledAway()
        }

        onHeightChanged: Qt.callLater(list.follow, false)

        ScrollBar.vertical: StyledScrollBar {
            id: vbar
            onPressedChanged: {
                if (pressed) {
                    scroll.stop()
                    list.manualBrowsing = true
                    autoReturnTimer.stop()
                } else {
                    list.scheduleAutoReturn()
                }
            }
        }
        FastWheel {
            id: lyricsWheel
            target: list
            onWheelScrolled: {
                scroll.stop()
                list.manualBrowsing = true
                list.scheduleAutoReturn()
            }
        }

        function follow(animated: bool) {
            if (root.suspended) {
                return
            }
            if (manualBrowsing) {
                updateScrolledAway()
                return
            }
            lyricsWheel.stopSmooth()
            const index = UiState.activeLyricIndex
            if (index < 0) {
                if (UiState.lyricsSynced && list.count > 0) {
                    autoScrolling = true
                    list.contentY = list.originY - list.topMargin
                    autoScrolling = false
                }
                updateScrolledAway()
                return
            }
            const item = list.itemAtIndex(index)
            if (!item) {
                scroll.stop()
                autoScrolling = true
                list.positionViewAtIndex(index, ListView.Center)
                autoScrolling = false
                updateScrolledAway()
                return
            }
            const maxY = Math.max(list.originY - list.topMargin,
                                  list.contentHeight + list.originY - list.height + list.bottomMargin)
            const target = Math.max(list.originY - list.topMargin,
                                    Math.min(item.y + item.height / 2 - list.height / 2, maxY))
            const delta = target - list.contentY
            scroll.stop()
            if (animated && !Appearance.performanceMode
                    && (Appearance.reduceMotion || Math.abs(delta) > Math.min(260, list.height * 0.45))) {
                scroll.from = list.contentY
                scroll.to = target
                scroll.start()
                return
            }
            autoScrolling = true
            list.contentY = target
            autoScrolling = false
            if (animated && !Appearance.reduceMotion && Math.abs(delta) >= 1) {
                list.stepped(delta)
            }
            updateScrolledAway()
        }

        NumberAnimation {
            id: scroll
            target: list
            property: "contentY"
            duration: 420
            easing.type: Easing.OutCubic
            onStopped: list.updateScrolledAway()
        }

        Connections {
            target: UiState
            function onActiveLyricIndexChanged() {
                if (!list.manualBrowsing) {
                    list.follow(true)
                } else {
                    list.updateScrolledAway()
                }
            }
            function onLyricsLinesChanged() {
                autoReturnTimer.stop()
                lyricsWheel.stopSmooth()
                list.manualBrowsing = false
                Qt.callLater(list.follow, false)
            }
        }
        Connections {
            target: root
            function onSuspendedChanged() {
                if (root.suspended) {
                    autoReturnTimer.stop()
                    lyricsWheel.stopSmooth()
                    list.manualBrowsing = false
                } else {
                    Qt.callLater(list.follow, false)
                }
            }
        }
        Component.onCompleted: Qt.callLater(list.follow, false)

        delegate: Item {
            id: line

            required property int index
            required property var modelData
            readonly property bool hasTime: Boolean(modelData && modelData.time !== undefined && modelData.time !== null)
            readonly property real timeSecs: hasTime ? Number(modelData.time) : -1
            readonly property bool isCurrent: UiState.lyricsSynced && UiState.activeLyricIndex === index
            readonly property bool isPast: UiState.lyricsSynced && UiState.activeLyricIndex >= 0 && index < UiState.activeLyricIndex
            readonly property bool isHovered: mouseArea.containsMouse

            width: list.width - list.leftMargin - list.rightMargin
            height: text.implicitHeight + 22

            property real lag: 0
            transform: Translate { y: line.lag }

            Connections {
                target: list
                function onStepped(delta: real) {
                    line.lag += delta
                    settle.restart()
                }
            }
            SequentialAnimation {
                id: settle
                PauseAnimation { duration: Math.min(Math.abs(line.index - UiState.activeLyricIndex), 8) * 16 }
                NumberAnimation { target: line; property: "lag"; to: 0; duration: 560; easing.type: Easing.OutBack; easing.overshoot: 0.6 }
            }

            Rectangle {
                id: highlightCard
                anchors.fill: parent
                radius: 14
                color: line.isHovered && UiState.lyricsSynced && line.hasTime
                    ? Qt.alpha(root.scheme.onSurface, 0.06)
                    : "transparent"

                Behavior on color {
                    ColorAnimation { duration: Appearance.duration(200); easing.type: Easing.InOutQuad }
                }
            }

            Item {
                id: textScaleWrap
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 18
                anchors.rightMargin: UiState.lyricsSynced && line.hasTime
                    ? Math.max(48, timeBadge.implicitWidth + 22)
                    : 14
                height: text.implicitHeight
                transformOrigin: Item.Left

                property real springing: {
                    if (!UiState.lyricsSynced) return 0.94
                    return line.isCurrent ? 1.0 : 0.90
                }
                property real eased: springing
                scale: Appearance.reduceMotion ? eased : springing

                Behavior on springing {
                    enabled: !root.suspended && !Appearance.reduceMotion
                    Bounce {}
                }
                Behavior on eased {
                    enabled: !root.suspended && Appearance.reduceMotion && !Appearance.performanceMode
                    NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
                }

                StyledText {
                    id: text
                    width: parent.width
                    text: line.modelData && line.modelData.text && line.modelData.text.length > 0 ? line.modelData.text : "♪"
                    wrapMode: Text.Wrap
                    font.pixelSize: 20
                    font.weight: line.isCurrent || !UiState.lyricsSynced ? Font.Bold : Font.DemiBold
                    color: root.scheme.onSurface
                    opacity: {
                        if (!UiState.lyricsSynced) {
                            return line.isHovered ? 1.0 : 0.86
                        }
                        if (line.isCurrent) return 1.0
                        if (line.isHovered && line.hasTime) return 0.86
                        return line.isPast ? 0.34 : 0.56
                    }

                    layer.enabled: line.isCurrent
                    layer.smooth: true
                    layer.effect: ShaderEffect {
                        property variant source
                        property color accentColor: root.scheme.primary
                        property color sungColor: root.scheme.onSurface
                        property size itemSize: Qt.size(text.width, text.height)
                        property real progress: UiState.activeLyricProgress
                        property real lineCount: Math.max(1, text.lineCount)
                        property real textWidthFrac: text.width > 0 ? Math.min(1.0, Math.max(0.06, text.contentWidth / text.width)) : 1.0
                        property real dimAlpha: 0.34
                        property real glowAmount: Appearance.performanceMode ? 0.0 : 0.85
                        fragmentShader: "qrc:/shaders/lyric_karaoke.frag.qsb"
                    }

                    Behavior on opacity {
                        enabled: !root.suspended
                        NumberAnimation { duration: Appearance.duration(260); easing.type: Easing.InOutQuad }
                    }
                }
            }

            StyledText {
                id: timeBadge
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                visible: UiState.lyricsSynced && line.hasTime
                opacity: line.isHovered ? 1 : 0
                text: UiState.formatLyricTime(line.timeSecs)
                font.pixelSize: 11
                font.weight: Font.Medium
                color: root.scheme.onSurfaceVariant

                Behavior on opacity {
                    enabled: !root.suspended && !Appearance.performanceMode
                    NumberAnimation { duration: Appearance.duration(140); easing.type: Easing.OutCubic }
                }
            }

            MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                enabled: UiState.lyricsSynced && line.hasTime && backend.durationSecs > 0
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    autoReturnTimer.stop()
                    list.manualBrowsing = false
                    backend.seek(Math.max(0.0, Math.min(1.0, line.timeSecs / backend.durationSecs)))
                }
            }
        }

        footer: Column {
            width: list.width - list.leftMargin - list.rightMargin
            topPadding: 18
            leftPadding: 14
            spacing: 4

            StyledText {
                width: parent.width - 14
                visible: UiState.lyricsWriters.length > 0
                text: qsTr("Авторы: ") + UiState.lyricsWriters
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.fontSize.smaller
                color: root.scheme.onSurfaceVariant
            }
            StyledText {
                width: parent.width - 14
                visible: UiState.lyricsMajor.length > 0
                text: "℗ " + UiState.lyricsMajor
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.fontSize.smaller
                color: root.scheme.onSurfaceVariant
            }
            StyledText {
                text: qsTr("Яндекс Музыка")
                font.pixelSize: Appearance.fontSize.smaller
                color: root.scheme.outline
            }
        }
    }
}
