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
import QtQuick.Effects
import ymusic.ui

Item {
    id: root

    property MaterialScheme scheme: PlayerStyle.darkScheme
    readonly property color glow: Qt.rgba(PlayerStyle.primary.r, PlayerStyle.primary.g, PlayerStyle.primary.b, 0.5)
    readonly property bool hasLyrics: UiState.lyricsLines && UiState.lyricsLines.length > 0

    onVisibleChanged: {
        if (!visible) {
            autoReturnTimer.stop()
            lyricsWheel.stopSmooth()
            list.manualBrowsing = false
        } else {
            Qt.callLater(list.follow, false)
        }
    }

    Column {
        anchors.centerIn: parent
        Reveal.shown: UiState.lyricsLoading
        spacing: 14

        LoadingSpinner {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 36
            height: 36
            color: root.scheme.primary
            trackColor: Qt.rgba(1, 1, 1, 0.12)
        }
        StyledText {
            text: "Загружаем текст…"
            color: Qt.rgba(1, 1, 1, 0.7)
        }
    }

    EmptyState {
        anchors.centerIn: parent
        Reveal.shown: !UiState.lyricsLoading && !root.hasLyrics
        scheme: root.scheme
        symbol: "lyrics"
        title: "Текст недоступен"
        description: UiState.lyricsMessage.length > 0 ? UiState.lyricsMessage : "Для этого трека текст пока не найден"
    }

    ModSlotHost {
        layoutMode: "row"
        spacing: 6
        z: 3
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: 20
        anchors.topMargin: 8
        height: 30
        visible: implicitWidth > 0 && !UiState.lyricsLoading && root.hasLyrics
        slotName: "immersive.lyrics.header"
        slotContext: ({
            scheme: root.scheme,
            trackId: UiState.lyricsTrackId,
            synced: UiState.lyricsSynced
        })
    }

    Item {
        id: statusHeader
        z: 2
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.topMargin: 8
        height: 32
        visible: !UiState.lyricsLoading && root.hasLyrics && list.scrolledAway && UiState.lyricsSynced && UiState.activeLyricIndex >= 0

        Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 26
            radius: 13
            width: immersiveJumpText.implicitWidth + 22
            visible: parent.visible
            color: immersiveJumpMouse.containsMouse
                ? PlayerStyle.primary
                : Qt.rgba(PlayerStyle.primary.r, PlayerStyle.primary.g, PlayerStyle.primary.b, 0.26)
            border.width: 1
            border.color: Qt.rgba(PlayerStyle.primary.r, PlayerStyle.primary.g, PlayerStyle.primary.b, 0.65)

            Behavior on color {
                ColorAnimation { duration: 140 }
            }

            StyledText {
                id: immersiveJumpText
                anchors.centerIn: parent
                text: "К текущей строке"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: "white"
            }

            MouseArea {
                id: immersiveJumpMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: list.resumeFollowing()
            }
        }
    }

    Rectangle {
        id: introBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.topMargin: 8
        height: visible ? 3 : 0
        radius: 1.5
        visible: !UiState.lyricsLoading && root.hasLyrics && UiState.lyricsSynced
            && UiState.activeLyricIndex < 0 && UiState.firstLyricTimeSecs > 0
        color: Qt.rgba(1, 1, 1, 0.12)

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            radius: parent.radius
            width: parent.width * UiState.activeLyricProgress
            color: PlayerStyle.primary
        }
    }

    ListView {
        id: list
        objectName: "immersiveLyricsList"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.top: introBar.visible ? introBar.bottom : parent.top
        anchors.topMargin: 4
        Reveal.shown: !UiState.lyricsLoading && root.hasLyrics
        model: UiState.lyricsLines
        spacing: 18
        topMargin: 20
        bottomMargin: 30
        leftMargin: 8
        rightMargin: 8
        boundsBehavior: Flickable.DragAndOvershootBounds
        cacheBuffer: 1200
        clip: true
        FastWheel {
            id: lyricsWheel
            target: list
            onWheelScrolled: {
                scroll.stop()
                list.manualBrowsing = true
                list.scheduleAutoReturn()
            }
        }

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

        signal stepped(real delta)

        property bool autoScrolling: false
        property bool manualBrowsing: false
        property bool scrolledAway: false

        Timer {
            id: autoReturnTimer
            interval: 5000
            repeat: false
            onTriggered: {
                if (!list.manualBrowsing || !UiState.lyricsSynced || !root.hasLyrics || !root.visible) {
                    return
                }
                if (list.dragging || list.moving || lyricsWheel.activeFlick === list
                        || pointerActivity.point.pressedButtons !== Qt.NoButton) {
                    autoReturnTimer.restart()
                    return
                }
                list.resumeFollowing()
            }
        }

        function scheduleAutoReturn() {
            if (manualBrowsing && UiState.lyricsSynced && root.hasLyrics && root.visible && !dragging) {
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
            const viewTop = list.contentY + 12
            const viewBottom = list.contentY + list.height - 12
            scrolledAway = (item.y + item.height) < viewTop || item.y > viewBottom
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
            if (!autoScrolling && !scroll.running && (moving || dragging || lyricsWheel.activeFlick === list)) {
                manualBrowsing = true
                if (!dragging) {
                    scheduleAutoReturn()
                }
            }
            updateScrolledAway()
        }

        onHeightChanged: Qt.callLater(list.follow, false)

        layer.enabled: true
        layer.effect: ShaderEffect {
            property variant source
            property real edge: 0.08
            fragmentShader: "qrc:/shaders/edge_fade.frag.qsb"
        }

        function follow(animated: bool) {
            if (manualBrowsing) {
                updateScrolledAway();
                return;
            }
            lyricsWheel.stopSmooth();
            const index = UiState.activeLyricIndex;
            if (index < 0) {
                if (UiState.lyricsSynced && list.count > 0) {
                    autoScrolling = true;
                    list.contentY = list.originY - list.topMargin;
                    autoScrolling = false;
                }
                updateScrolledAway();
                return;
            }
            const item = list.itemAtIndex(index);
            if (!item) {
                scroll.stop();
                autoScrolling = true;
                list.positionViewAtIndex(index, ListView.Center);
                autoScrolling = false;
                updateScrolledAway();
                return;
            }
            const maxY = Math.max(list.originY - list.topMargin,
                                  list.contentHeight + list.originY - list.height + list.bottomMargin);
            const target = Math.max(list.originY - list.topMargin,
                                    Math.min(item.y + item.height / 2 - list.height / 2, maxY));
            const delta = target - list.contentY;
            scroll.stop();
            if (animated && !Appearance.performanceMode
                    && (Appearance.reduceMotion || Math.abs(delta) > Math.min(260, list.height * 0.45))) {
                scroll.from = list.contentY;
                scroll.to = target;
                scroll.start();
                return;
            }
            autoScrolling = true;
            list.contentY = target;
            autoScrolling = false;
            if (animated && !Appearance.reduceMotion && Math.abs(delta) >= 1) {
                list.stepped(delta);
            }
            updateScrolledAway();
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
                    list.follow(true);
                } else {
                    list.updateScrolledAway();
                }
            }
            function onLyricsLinesChanged() {
                autoReturnTimer.stop();
                lyricsWheel.stopSmooth();
                list.manualBrowsing = false;
                Qt.callLater(list.follow, false);
            }
        }
        Component.onCompleted: {
            UiState.ensureLyrics(true);
            Qt.callLater(list.follow, false);
        }

        delegate: Item {
            id: line

            required property int index
            required property var modelData
            readonly property string words: String(modelData && modelData.text !== undefined ? modelData.text : "")
            readonly property var wordList: (modelData && modelData.words) ? modelData.words : []
            readonly property bool hasTime: Boolean(modelData && modelData.time !== undefined && modelData.time !== null)
            readonly property real timeSecs: hasTime ? Number(modelData.time) : -1
            readonly property bool isCurrent: UiState.lyricsSynced && UiState.activeLyricIndex === index
            readonly property bool isPast: UiState.lyricsSynced && UiState.activeLyricIndex >= 0 && index < UiState.activeLyricIndex
            readonly property bool active: isCurrent
            readonly property bool isHovered: mouseArea.containsMouse
            readonly property string modSubtitle: ModManager.lyricSubtitlesRevision >= 0
                ? ModManager.lyricSubtitleFor(UiState.lyricsTrackId, index)
                : ""
            property bool highlighted: false
            property real glowStrength: !UiState.lyricsSynced ? 0.5 : (active ? 1.0 : 0.0)

            Behavior on glowStrength {
                NumberAnimation { duration: Appearance.duration(320); easing.type: Easing.InOutQuad }
            }

            width: list.width - list.leftMargin - list.rightMargin
            height: label.implicitHeight + (immersiveSubtitle.visible ? immersiveSubtitle.implicitHeight + 6 : 0) + 28

            property real lag: 0
            transform: Translate { y: line.lag }

            Connections {
                target: list
                function onStepped(delta: real) {
                    line.lag += delta;
                    settle.restart();
                }
            }
            SequentialAnimation {
                id: settle
                PauseAnimation { duration: Math.min(Math.abs(line.index - UiState.activeLyricIndex), 8) * 16 }
                NumberAnimation { target: line; property: "lag"; to: 0; duration: 560; easing.type: Easing.OutBack; easing.overshoot: 0.6 }
            }

            property real springing: {
                if (!UiState.lyricsSynced) return 0.96;
                return isCurrent ? 1.0 : (isPast ? 0.93 : 0.95);
            }
            property real eased: springing
            scale: Appearance.reduceMotion ? eased : springing
            transformOrigin: Item.Left

            Behavior on springing {
                enabled: !Appearance.reduceMotion
                Bounce {}
            }
            Behavior on eased {
                enabled: Appearance.reduceMotion && !Appearance.performanceMode
                NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
            }

            WavyPill {
                objectName: "lyricHighlight"
                anchors.fill: parent
                cornerRadius: 26
                hovered: line.isHovered
                color: line.isHovered && UiState.lyricsSynced && line.hasTime
                    ? Qt.rgba(1, 1, 1, 0.08)
                    : Qt.rgba(1, 1, 1, 0)

                Behavior on color {
                    ColorAnimation { duration: Appearance.duration(220); easing.type: Easing.InOutQuad }
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: 22
                color: Qt.rgba(1, 1, 1, line.highlighted ? 0.15 : 0)

                Behavior on color {
                    ColorAnimation { duration: Appearance.duration(180); easing.type: Easing.OutQuad }
                }
            }

            Item {
                id: glowWrap
                anchors.fill: parent

                layer.enabled: !Appearance.performanceMode && line.glowStrength > 0.01
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: root.glow
                    shadowOpacity: line.glowStrength
                    shadowBlur: 1
                    blurMax: 24
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                }

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 26
                    anchors.rightMargin: immersiveTimeBadge.visible ? immersiveTimeBadge.implicitWidth + 30 : 24
                    spacing: 6

                    KaraokeLyricLine {
                        id: label
                        objectName: "lyricText"
                        width: parent.width
                        lineText: line.words
                        wordTimings: line.wordList
                        wordKaraokeActive: line.isCurrent && UiState.lyricsWordSynced && appSettings.lyricsWordKaraoke && line.wordList.length > 0
                        isCurrent: line.isCurrent
                        synced: UiState.lyricsSynced
                        isPast: line.isPast
                        isHovered: line.isHovered
                        hasTime: line.hasTime
                        fontPixelSize: 28
                        fontWeight: Font.Bold
                        textColor: "white"
                        accentColor: PlayerStyle.primary
                        dimAlpha: 0.28
                        glowAmount: Appearance.performanceMode ? 0.0 : line.glowStrength
                    }

                    StyledText {
                        id: immersiveSubtitle
                        width: parent.width
                        visible: line.modSubtitle.length > 0
                        text: line.modSubtitle
                        wrapMode: Text.WordWrap
                        font.pixelSize: 16
                        font.weight: Font.Medium
                        color: line.isCurrent ? Qt.rgba(1, 1, 1, 0.80) : Qt.rgba(1, 1, 1, 0.42)
                    }
                }
            }

            StyledText {
                id: immersiveTimeBadge
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                visible: UiState.lyricsSynced && line.hasTime && line.isHovered
                text: UiState.formatLyricTime(line.timeSecs)
                font.pixelSize: 13
                font.weight: Font.Medium
                color: Qt.rgba(1, 1, 1, 0.72)
            }

            Timer {
                id: flash
                interval: 80
                onTriggered: line.highlighted = false
            }

            MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                enabled: UiState.lyricsSynced && line.hasTime && backend.durationSecs > 0
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    line.highlighted = true;
                    flash.restart();
                    autoReturnTimer.stop();
                    list.manualBrowsing = false;
                    backend.seek(Math.max(0, Math.min(1, line.timeSecs / backend.durationSecs)));
                }
            }
        }
    }
}
