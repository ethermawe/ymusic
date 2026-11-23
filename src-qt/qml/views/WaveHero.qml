/*
 * ymusic — native Yandex Music desktop client
 * Copyright (C) 2026  ethermawe
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
import QtQuick.Layouts
import QtQuick.Templates as T
import ymusic.ui

FocusScope {
    id: root
    focus: true

    property var selected: ({})
    property bool fetching: true
    property bool applying: false
    property string errorMessage: ""
    property bool settingsOpen: false
    onSettingsOpenChanged: {
        if (settingsOpen && !settingsPopup.opened) settingsPopup.open();
        else if (!settingsOpen && settingsPopup.opened) settingsPopup.close();
    }
    onVisibleChanged: {
        if (!visible) {
            if (settingsOpen) settingsOpen = false;
            waveAutoReturnTimer.stop();
            waveWheel.stopSmooth();
            waveTrackList.manualBrowsing = false;
        } else {
            if (root.groups.length === 0 && !root.fetching && backend.loggedIn) {
                root.reload();
            }
            Qt.callLater(waveTrackList.follow, false);
        }
    }

    readonly property var groups: backend.waveSettings.groups || []
    readonly property bool inWave: backend.tracks.currentIndex >= 0
    readonly property bool wavePlaying: inWave && backend.playing
    readonly property bool compact: width < 820
    readonly property real topInset: Appearance.sizes.topBarHeight + 8
    readonly property real bottomInset: Appearance.sizes.playerBarClearance + 8
    readonly property real usableHeight: Math.max(320, height - topInset - bottomInset)
    readonly property real stageOrbDiameter: compact
        ? Math.min(350, Math.max(240, usableHeight * 0.56))
        : Math.min(540, Math.max(360, Math.min(usableHeight - 108, rightStage.width * 0.80)))
    readonly property bool showsRing: appSettings.visualizersEnabled && appSettings.waveVisualizer && !Appearance.performanceMode
    readonly property bool auroraActive: appSettings.waveAurora && !Appearance.performanceMode
    readonly property bool showsOrbCover: appSettings.waveOrbArtwork && root.inWave && backend.hasCover
    property real auroraIdleTime: 0
    readonly property real innerOrbSize: showsRing ? stageOrbDiameter * ring.innerRadiusRatio : stageOrbDiameter * 0.76
    readonly property real beatEnergy: root.wavePlaying && !Appearance.reduceMotion && !Appearance.performanceMode
        ? Math.min(1.5, clock.energy.x * 0.65 + clock.energy.y * 0.35) : 0
    property real smoothMidEnergy: 0
    property real smoothOuterEnergy: 0
    Behavior on smoothMidEnergy {
        enabled: !root.wavePlaying && !Appearance.performanceMode
        NumberAnimation { duration: 260; easing.type: Easing.OutQuad }
    }
    Behavior on smoothOuterEnergy {
        enabled: !root.wavePlaying && !Appearance.performanceMode
        NumberAnimation { duration: 420; easing.type: Easing.OutQuad }
    }
    onWavePlayingChanged: {
        if (!wavePlaying) {
            smoothMidEnergy = 0;
            smoothOuterEnergy = 0;
        }
    }
    readonly property real orbBeatScale: 1.0 + root.beatEnergy * 0.048
    property real orbVisualScale: coreMouse.pressed ? 0.93 : (coreHover.hovered ? 1.05 : 1.0)
    Behavior on orbVisualScale { enabled: !Appearance.performanceMode; Bounce {} }

    readonly property bool changed: JSON.stringify(selected) !== JSON.stringify(backend.waveSettings.selected || {})
    readonly property int activeFilterCount: Object.keys(selected).length

    readonly property color accentPrimary: (inWave && PlayerStyle.palette.length > 0)
        ? PlayerStyle.primary : Appearance.colors.primary
    readonly property color accentSecondary: (inWave && PlayerStyle.palette.length > 1)
        ? PlayerStyle.secondary : Appearance.colors.tertiary

    readonly property var activeFilterItems: {
        const out = [];
        const sel = root.selected || {};
        const grps = root.groups || [];
        for (let i = 0; i < grps.length; ++i) {
            const g = grps[i];
            const chosenSeed = sel[g.key];
            if (!chosenSeed) continue;
            const choices = g.choices || [];
            for (let j = 0; j < choices.length; ++j) {
                if (choices[j].seed === chosenSeed) {
                    out.push({ key: g.key, name: choices[j].name, seed: chosenSeed });
                    break;
                }
            }
        }
        return out;
    }

    readonly property var quickPresetItems: {
        const grps = root.groups || [];
        if (grps.length === 0) return [];
        const first = grps[0];
        const choices = first.choices || [];
        const out = [];
        for (let i = 0; i < Math.min(3, choices.length); ++i) {
            out.push({ key: first.key, name: choices[i].name, seed: choices[i].seed });
        }
        return out;
    }

    Keys.onEscapePressed: (event) => {
        if (root.settingsOpen) {
            root.settingsOpen = false;
            event.accepted = true;
        }
    }

    function select(key: string, seed: string) {
        const next = Object.assign({}, selected);
        if (seed.length > 0) next[key] = seed;
        else delete next[key];
        selected = next;
    }

    function selectAndApply(key: string, seed: string) {
        select(key, seed);
        applying = true;
        errorMessage = "";
        backend.feature({action: "wave_apply", selected: selected});
    }

    function reload() {
        fetching = true;
        errorMessage = "";
        backend.feature({action: "wave_settings"});
    }

    function toggleWavePlayback() {
        if (root.inWave) backend.toggle();
        else if (backend.tracks.count > 0) backend.play(0);
        else backend.startWave();
    }

    Component.onCompleted: {
        selected = Object.assign({}, backend.waveSettings.selected || {});
        reload();
    }

    BackdropClock {
        id: clock
        running: root.wavePlaying && root.visible && !Appearance.reduceMotion && !Appearance.performanceMode
        playing: root.wavePlaying
        reactivity: appSettings.waveReactivity
        onFrame: {
            if (!root.wavePlaying || Appearance.reduceMotion || Appearance.performanceMode) return;
            const targetMid = Math.min(1.5, clock.energy.z * 0.45 + clock.energy.w * 0.55);
            const targetOuter = Math.min(1.5, clock.lead * 0.55 + clock.energy.w * 0.45);
            root.smoothMidEnergy += (targetMid - root.smoothMidEnergy) * 0.22;
            root.smoothOuterEnergy += (targetOuter - root.smoothOuterEnergy) * 0.09;
        }
    }

    FrameAnimation {
        running: root.visible && root.auroraActive && !root.wavePlaying && !Appearance.reduceMotion
        onTriggered: root.auroraIdleTime += frameTime * 0.65
    }

    function paletteShade(index: int, fallback: color): color {
        const pal = PlayerStyle.palette;
        if (root.inWave && pal && pal.length > 0) {
            return pal[index % pal.length];
        }
        return fallback;
    }

    Image {
        id: waveBackdropSource
        width: 64
        height: 64
        source: appSettings.coversEnabled && root.inWave && backend.hasCover ? backend.nowCover : ""
        sourceSize: Qt.size(64, 64)
        smooth: true
        asynchronous: true
    }

    ShaderEffectSource {
        id: waveBackdropTex
        sourceItem: waveBackdropSource
        hideSource: true
        visible: false
        live: true
    }

    // Experimental ambient cover wash matching HomeView spotlight card
    ShaderEffect {
        anchors.fill: parent
        property variant source: waveBackdropTex
        property size itemSize: Qt.size(width, height)
        property real radius: Appearance.rounding.large
        fragmentShader: "qrc:/shaders/artwork_backdrop.frag.qsb"
        visible: !root.auroraActive && waveBackdropSource.status === Image.Ready
        opacity: 0.25
    }

    // 3D silk-plasma sphere + acoustic wave fronts spanning behind the split stage
    ShaderEffect {
        id: waveAurora
        anchors.fill: parent
        visible: root.auroraActive
        fragmentShader: "qrc:/shaders/wave_aurora.frag.qsb"

        property size itemSize: Qt.size(width, height)
        property point orbCenter: Qt.point(
            splitContainer.x + rightStage.x + orbColumn.x + coreStage.x + coreStage.width * 0.5,
            splitContainer.y + rightStage.y + orbColumn.y + coreStage.y + coreStage.height * 0.5
        )
        property real radius: 0
        property real time: Appearance.reduceMotion ? 0 : (clock.time + root.auroraIdleTime)
        property vector4d energy: root.wavePlaying ? clock.energy : Qt.vector4d(0, 0, 0, 0)
        property real lead: root.wavePlaying ? clock.lead : 0
        property real waveActive: root.wavePlaying ? 1.0 : 0.0
        Behavior on waveActive {
            enabled: !Appearance.reduceMotion
            NumberAnimation { duration: 480; easing.type: Easing.InOutQuad }
        }
        property color bgColor: Appearance.colors.layer1
        property color c0: root.paletteShade(0, Appearance.colors.primary)
        property color c1: root.paletteShade(1, Appearance.colors.tertiary)
        property color c2: root.paletteShade(2, Appearance.colors.secondary)
        property real orbSize: (coreButton.width * 0.5) * root.orbVisualScale
        property real tintStrength: appSettings.visualizersEnabled ? 0.95 : 0.72
        property real hasCover: root.showsOrbCover ? 1.0 : 0.0
        Behavior on hasCover {
            enabled: !Appearance.reduceMotion
            NumberAnimation { duration: 280; easing.type: Easing.InOutQuad }
        }
    }

    component Chip: Button {
        id: chip
        property bool chosen: false
        implicitHeight: 36
        implicitWidth: chipRow.implicitWidth + (chip.chosen ? 24 : 28)
        leftPadding: chip.chosen ? 11 : 14
        rightPadding: 14
        hoverEnabled: true
        opacity: enabled ? 1 : 0.5
        scale: down ? 0.95 : (hovered ? 1.03 : 1)
        Behavior on scale { enabled: !Appearance.performanceMode; Bounce {} }

        contentItem: Row {
            id: chipRow
            spacing: 6
            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                visible: chip.chosen
                text: "check"
                iconSize: 16
                fill: 1
                color: Appearance.colors.onPrimary
            }
            StyledText {
                id: label
                anchors.verticalCenter: parent.verticalCenter
                text: chip.text
                font.pixelSize: Appearance.fontSize.smaller
                font.weight: chip.chosen ? Font.DemiBold : Font.Medium
                color: chip.chosen ? Appearance.colors.onPrimary : Appearance.colors.onSurface
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
            }
        }
        background: Rectangle {
            radius: 18
            color: chip.chosen
                ? Appearance.colors.primary
                : (chip.hovered
                    ? Qt.rgba(Appearance.colors.surfaceContainerHighest.r,
                              Appearance.colors.surfaceContainerHighest.g,
                              Appearance.colors.surfaceContainerHighest.b, 0.92)
                    : Qt.rgba(Appearance.colors.surfaceContainerHigh.r,
                              Appearance.colors.surfaceContainerHigh.g,
                              Appearance.colors.surfaceContainerHigh.b, 0.72))
            border.width: chip.visualFocus ? 2 : 1
            border.color: chip.visualFocus
                ? Appearance.colors.primary
                : Qt.rgba(Appearance.colors.outlineVariant.r,
                          Appearance.colors.outlineVariant.g,
                          Appearance.colors.outlineVariant.b, 0.45)
            Behavior on color { ElementMoveFastColor {} }
        }
    }

    // Deterministic Split-Screen Stage (no whole-page scrolling, no RowLayout width stretching)
    Item {
        id: splitContainer
        anchors.fill: parent
        anchors.topMargin: root.topInset
        anchors.bottomMargin: root.bottomInset
        anchors.leftMargin: Appearance.sizes.pageMargin
        anchors.rightMargin: Appearance.sizes.pageMargin

        // ====================================================================
        // LEFT COLUMN: Fixed-Height Scrollable Wave Queue Card
        // ====================================================================
        Rectangle {
            id: leftQueuePane
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: root.compact
                ? Math.round(parent.width * 0.45)
                : Math.min(500, Math.max(360, Math.round(parent.width * 0.41)))
            radius: 22
            color: Qt.rgba(Appearance.colors.surfaceContainerLow.r,
                           Appearance.colors.surfaceContainerLow.g,
                           Appearance.colors.surfaceContainerLow.b, 0.56)
            border.width: 1
            border.color: Qt.rgba(Appearance.colors.outlineVariant.r,
                                  Appearance.colors.outlineVariant.g,
                                  Appearance.colors.outlineVariant.b, 0.25)

            // Queue Header + Quick Wave Feedback Buttons
            Item {
                id: queueHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 14
                anchors.leftMargin: 16
                anchors.rightMargin: 14
                height: 42

                ShapeIcon {
                    id: headerIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    size: 36
                    iconSize: 19
                    shape: "sunny"
                    hoverShape: "cookie9"
                    symbol: "my_wave"
                    color: Appearance.colors.primaryContainer
                    iconColor: Appearance.colors.onPrimaryContainer
                }

                // Quick Wave Actions (Dislike / Like / Next)
                Row {
                    id: headerActions
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    IconButton {
                        symbol: "thumb_down"
                        size: 34
                        iconSize: 18
                        tooltip: "Меньше такого"
                        enabled: root.inWave
                        onClicked: backend.dislikeNow()
                    }
                    IconButton {
                        symbol: backend.nowLiked && root.inWave ? "favorite" : "favorite_border"
                        size: 34
                        iconSize: 19
                        toggled: backend.nowLiked && root.inWave
                        burst: "hearts"
                        tooltip: "Мне нравится"
                        enabled: root.inWave
                        onClicked: backend.toggleNowLike()
                    }
                    TransportButton {
                        symbol: "skip_next"
                        size: 34
                        iconSize: 21
                        iconColor: Appearance.colors.primary
                        effect: TransportButton.NudgeRight
                        hoverShape: "pill"
                        tooltip: "Следующий трек"
                        enabled: root.inWave
                        onClicked: backend.next()
                    }
                }

                Column {
                    anchors.left: headerIcon.right
                    anchors.leftMargin: 10
                    anchors.right: headerActions.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    TitleText {
                        width: parent.width
                        text: "Поток волны"
                        font.pixelSize: 19
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }
                    StyledText {
                        width: parent.width
                        text: root.inWave
                            ? ("Сейчас: " + backend.nowTitle)
                            : "Очередь персональных рекомендаций"
                        font.pixelSize: Appearance.fontSize.smallest
                        color: Appearance.colors.onSurfaceVariant
                        elide: Text.ElideRight
                    }
                }
            }

            // Fixed-height scrollable track list with soft top/bottom edge fade
            Item {
                anchors.top: queueHeader.bottom
                anchors.topMargin: 6
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                anchors.bottomMargin: 8

                ListView {
                    id: waveTrackList
                    anchors.fill: parent
                    topMargin: 10
                    bottomMargin: 14
                    clip: true
                    reuseItems: true
                    boundsBehavior: Flickable.StopAtBounds
                    maximumFlickVelocity: 5000
                    flickDeceleration: 2400
                    model: root.visible ? backend.tracks : null

                    property bool autoScrolling: false
                    property bool manualBrowsing: false
                    property bool scrolledAway: false

                    FastWheel {
                        id: waveWheel
                        target: waveTrackList
                        onWheelScrolled: {
                            waveScroll.stop();
                            waveTrackList.manualBrowsing = true;
                            waveTrackList.scheduleAutoReturn();
                        }
                    }

                    HoverHandler {
                        id: wavePointerActivity
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        property real lastX: -1
                        property real lastY: -1
                        onHoveredChanged: {
                            if (hovered && waveTrackList.manualBrowsing) {
                                lastX = point.position.x;
                                lastY = point.position.y;
                                waveTrackList.scheduleAutoReturn();
                            }
                        }
                        onPointChanged: {
                            if (!hovered || !waveTrackList.manualBrowsing) return;
                            const dx = point.position.x - lastX;
                            const dy = point.position.y - lastY;
                            if (dx * dx + dy * dy >= 4) {
                                lastX = point.position.x;
                                lastY = point.position.y;
                                waveTrackList.scheduleAutoReturn();
                            }
                        }
                    }

                    Timer {
                        id: waveAutoReturnTimer
                        interval: 5000
                        repeat: false
                        onTriggered: {
                            if (!waveTrackList.manualBrowsing || !root.inWave || !root.visible || backend.tracks.count === 0) {
                                return;
                            }
                            if (waveTrackList.dragging || waveTrackList.moving || waveBar.pressed
                                    || waveWheel.activeFlick === waveTrackList
                                    || wavePointerActivity.point.pressedButtons !== Qt.NoButton) {
                                waveAutoReturnTimer.restart();
                                return;
                            }
                            waveTrackList.resumeFollowing();
                        }
                    }

                    function scheduleAutoReturn() {
                        if (manualBrowsing && root.inWave && root.visible && backend.tracks.count > 0 && !dragging && !waveBar.pressed) {
                            waveAutoReturnTimer.restart();
                        }
                    }

                    function resumeFollowing() {
                        waveAutoReturnTimer.stop();
                        manualBrowsing = false;
                        follow(true);
                    }

                    function updateScrolledAway() {
                        const index = backend.tracks.currentIndex;
                        if (!root.inWave || index < 0 || index >= backend.tracks.count) {
                            scrolledAway = false;
                            return;
                        }
                        const item = waveTrackList.itemAtIndex(index);
                        if (!item) {
                            scrolledAway = true;
                            return;
                        }
                        const viewTop = waveTrackList.contentY + 8;
                        const viewBottom = waveTrackList.contentY + waveTrackList.height - 8;
                        scrolledAway = (item.y + item.height) < viewTop || item.y > viewBottom;
                    }

                    function follow(animated: bool) {
                        if (manualBrowsing || !root.visible) {
                            updateScrolledAway();
                            return;
                        }
                        waveWheel.stopSmooth();
                        const index = backend.tracks.currentIndex;
                        if (!root.inWave || index < 0 || index >= backend.tracks.count) {
                            updateScrolledAway();
                            return;
                        }
                        let item = waveTrackList.itemAtIndex(index);
                        if (!item) {
                            waveScroll.stop();
                            autoScrolling = true;
                            waveTrackList.positionViewAtIndex(index, ListView.Beginning);
                            autoScrolling = false;
                            item = waveTrackList.itemAtIndex(index);
                            if (!item) {
                                updateScrolledAway();
                                return;
                            }
                        }
                        const minY = waveTrackList.originY - waveTrackList.topMargin;
                        const maxY = Math.max(minY,
                            waveTrackList.contentHeight + waveTrackList.originY - waveTrackList.height + waveTrackList.bottomMargin);
                        const anchorOffset = Math.min(72, Math.max(0, waveTrackList.height * 0.22));
                        const target = Math.max(minY, Math.min(item.y - anchorOffset, maxY));
                        waveScroll.stop();
                        if (animated && !Appearance.performanceMode && !Appearance.reduceMotion
                                && Math.abs(target - waveTrackList.contentY) >= 2) {
                            waveScroll.from = waveTrackList.contentY;
                            waveScroll.to = target;
                            waveScroll.start();
                            return;
                        }
                        autoScrolling = true;
                        waveTrackList.contentY = target;
                        autoScrolling = false;
                        updateScrolledAway();
                    }

                    NumberAnimation {
                        id: waveScroll
                        target: waveTrackList
                        property: "contentY"
                        duration: 380
                        easing.type: Easing.OutCubic
                        onStopped: waveTrackList.updateScrolledAway()
                    }

                    onDraggingChanged: {
                        if (dragging) {
                            waveScroll.stop();
                            manualBrowsing = true;
                            waveAutoReturnTimer.stop();
                        } else {
                            scheduleAutoReturn();
                        }
                    }

                    onContentYChanged: {
                        if (!autoScrolling && !waveScroll.running
                                && (moving || dragging || waveBar.pressed || waveWheel.activeFlick === waveTrackList)) {
                            manualBrowsing = true;
                            if (!dragging && !waveBar.pressed) {
                                scheduleAutoReturn();
                            }
                        }
                        updateScrolledAway();
                    }

                    onHeightChanged: Qt.callLater(waveTrackList.follow, false)

                    Connections {
                        target: backend.tracks
                        function onCurrentIndexChanged() {
                            if (!waveTrackList.manualBrowsing) {
                                Qt.callLater(waveTrackList.follow, true);
                            } else {
                                waveTrackList.updateScrolledAway();
                            }
                        }
                        function onCountChanged() {
                            Qt.callLater(waveTrackList.updateScrolledAway);
                        }
                    }

                    ScrollBar.vertical: StyledScrollBar {
                        id: waveBar
                        onPressedChanged: {
                            if (pressed) {
                                waveScroll.stop();
                                waveTrackList.manualBrowsing = true;
                                waveAutoReturnTimer.stop();
                            } else {
                                waveTrackList.scheduleAutoReturn();
                            }
                        }
                    }

                    layer.enabled: true
                    layer.effect: ShaderEffect {
                        property variant source
                        property real edge: 0.05
                        fragmentShader: "qrc:/shaders/edge_fade.frag.qsb"
                    }

                    delegate: TrackRow {
                        width: waveTrackList.width
                    }
                }

                Rectangle {
                    id: waveJumpPill
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: 12
                    anchors.bottomMargin: 10
                    z: 5
                    height: 28
                    radius: 14
                    width: waveJumpText.implicitWidth + 22
                    visible: root.inWave && waveTrackList.scrolledAway && backend.tracks.count > 0
                    color: waveJumpMouse.containsMouse
                        ? Appearance.colors.primary
                        : Appearance.colors.surfaceContainerHighest
                    border.width: 1
                    border.color: waveJumpMouse.containsMouse
                        ? Appearance.colors.primary
                        : Appearance.colors.outlineVariant

                    Behavior on color { ElementMoveFastColor {} }
                    Behavior on border.color { ElementMoveFastColor {} }

                    StyledText {
                        id: waveJumpText
                        anchors.centerIn: parent
                        text: "К текущему"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: waveJumpMouse.containsMouse ? Appearance.colors.onPrimary : Appearance.colors.onSurface
                    }

                    MouseArea {
                        id: waveJumpMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: waveTrackList.resumeFollowing()
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 12
                    visible: backend.tracks.count === 0 && backend.listLoading
                    LoadingSpinner { anchors.horizontalCenter: parent.horizontalCenter }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Настраиваем Мою волну…"
                        color: Appearance.colors.onSurfaceVariant
                    }
                }

                EmptyState {
                    anchors.centerIn: parent
                    width: Math.min(320, parent.width - 24)
                    visible: backend.tracks.count === 0 && !backend.listLoading
                    symbol: "my_wave"
                    title: "Поток готов к запуску"
                    description: "Нажмите на сферу справа, чтобы запустить Мою волну"
                }
            }
        }

        // ====================================================================
        // RIGHT COLUMN: Living Wave Orb Stage + Horizontal Vibe Pills
        // ====================================================================
        Item {
            id: rightStage
            anchors.left: leftQueuePane.right
            anchors.leftMargin: root.compact ? 16 : 28
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            // Expressive M3 shapes framing the open right stage (kept cleanly in-bounds)
            Item {
                id: waveM3Backdrop
                anchors.fill: parent
                visible: !appSettings.noShapes

                readonly property var shapeSpecs: [
                    { nx: 0.12, ny: 0.16, sizeRatio: 0.19, shape: "clover4",    tone: 0, alpha: 0.22, angle: 18,  pace: 14 },
                    { nx: 0.86, ny: 0.17, sizeRatio: 0.22, shape: "sunny",      tone: 1, alpha: 0.20, angle: 42,  pace: -16 },
                    { nx: 0.90, ny: 0.56, sizeRatio: 0.16, shape: "cookie9",    tone: 2, alpha: 0.22, angle: 110, pace: 18 },
                    { nx: 0.10, ny: 0.78, sizeRatio: 0.21, shape: "softBurst",  tone: 1, alpha: 0.20, angle: 205, pace: -13 },
                    { nx: 0.82, ny: 0.86, sizeRatio: 0.24, shape: "flower",     tone: 0, alpha: 0.22, angle: 280, pace: 12 },
                    { nx: 0.24, ny: 0.44, sizeRatio: 0.13, shape: "gem",        tone: 2, alpha: 0.18, angle: 65,  pace: 21 },
                    { nx: 0.74, ny: 0.36, sizeRatio: 0.14, shape: "puffy",      tone: 0, alpha: 0.18, angle: 150, pace: -19 }
                ]

                function shapeTint(toneIdx: int, alphaVal: real): color {
                    const c = toneIdx === 0
                        ? root.accentPrimary
                        : (toneIdx === 1 ? root.accentSecondary : Appearance.colors.tertiary);
                    return Qt.alpha(c, alphaVal);
                }

                Repeater {
                    model: appSettings.noShapes ? 0 : waveM3Backdrop.shapeSpecs.length

                    MaterialShape {
                        required property int index
                        readonly property var spec: waveM3Backdrop.shapeSpecs[index]
                        readonly property real baseDim: Math.min(rightStage.width, rightStage.height)

                        width: Math.max(76, Math.round(baseDim * spec.sizeRatio))
                        height: width
                        x: spec.nx * rightStage.width - width * 0.5
                        y: spec.ny * rightStage.height - height * 0.5
                        shape: spec.shape
                        color: waveM3Backdrop.shapeTint(spec.tone, spec.alpha)
                        spinAngle: spec.angle
                        spinRate: Appearance.reduceMotion ? 0 : spec.pace
                    }
                }
            }

            // Outer ambient halo decoupled from orb scale: blooms lazily from vocal/lead bands
            ArtworkGlow {
                id: outerWaveGlow
                visible: !root.auroraActive
                x: orbColumn.x + coreStage.x + (coreStage.width - width) * 0.5
                y: orbColumn.y + coreStage.y + (coreStage.height - height) * 0.5
                width: root.stageOrbDiameter * 1.24
                height: width
                intensity: root.wavePlaying ? (0.34 + root.smoothOuterEnergy * 0.28) : 0.24
                glowRadius: 96
                cornerRadius: width / 2
                circular: true
                primary: root.accentSecondary
                secondary: Appearance.colors.tertiary
                scale: root.wavePlaying && !Appearance.reduceMotion && !Appearance.performanceMode
                    ? 1.0 + root.smoothOuterEnergy * 0.16 + 0.03 * Math.sin(clock.time * 1.2) : 1.0
                rotation: root.wavePlaying && !Appearance.reduceMotion && !Appearance.performanceMode
                    ? (clock.time * 8) % 360 : 0
            }

            // Mid halo: reacts smoothly to upper-bass / vocal with gentle counter-rotation
            ArtworkGlow {
                id: innerWaveGlow
                visible: !root.auroraActive
                x: orbColumn.x + coreStage.x + (coreStage.width - width) * 0.5
                y: orbColumn.y + coreStage.y + (coreStage.height - height) * 0.5
                width: root.innerOrbSize * 1.08
                height: width
                intensity: root.wavePlaying ? (0.56 + root.smoothMidEnergy * 0.24) : 0.38
                glowRadius: 54
                cornerRadius: width / 2
                circular: true
                primary: root.accentPrimary
                secondary: root.accentSecondary
                scale: root.wavePlaying && !Appearance.reduceMotion && !Appearance.performanceMode
                    ? 1.0 + root.smoothMidEnergy * 0.08 : 1.0
                rotation: root.wavePlaying && !Appearance.reduceMotion && !Appearance.performanceMode
                    ? (clock.time * -12) % 360 : 0
            }

            Column {
                id: orbColumn
                anchors.centerIn: parent
                width: parent.width
                spacing: root.compact ? 18 : 26

                // 1. Immersive-style Wave Orb + Ring Spectrum
                Item {
                    id: coreStage
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.stageOrbDiameter
                    height: root.stageOrbDiameter
                    scale: root.orbVisualScale * root.orbBeatScale

                    transform: Scale {
                        id: orbPop
                        origin.x: coreStage.width / 2
                        origin.y: coreStage.height / 2
                    }

                    Connections {
                        target: backend
                        function onNowPlayingChanged() {
                            if (root.inWave && !Appearance.performanceMode) {
                                orbPopIn.restart();
                            }
                        }
                    }

                    NumberAnimation {
                        id: orbPopIn
                        target: orbPop
                        properties: "xScale,yScale"
                        from: 0.9
                        to: 1
                        duration: 640
                        easing.type: Easing.OutBack
                        easing.overshoot: 2
                    }

                    SpectrumView {
                        id: ring
                        anchors.fill: parent
                        Reveal.shown: root.showsRing && (root.wavePlaying || !root.auroraActive)
                        kind: SpectrumView.Ring
                        wave: appSettings.waveVisualizerShape === "wave"
                        sensitivity: appSettings.waveVisualizerSensitivity
                        active: root.visible && root.wavePlaying && root.showsRing
                        cutWaves: orbCover.showsSquiggle ? orbCover.squiggleWaves : 0
                        cutRadius: orbCover.squiggleMiddle
                        cutAmplitude: orbCover.squiggleAmplitude
                        cutPhase: orbCover.squigglePhase
                    }

                    Item {
                        id: coreButton
                        anchors.centerIn: parent
                        width: root.innerOrbSize
                        height: width

                        ArtworkImage {
                            id: orbCover
                            anchors.fill: parent
                            circular: true
                            showArtwork: appSettings.waveOrbArtwork
                            borderWidth: root.auroraActive && root.showsOrbCover ? 1.5 : 0
                            borderColor: Qt.rgba(1, 1, 1, 0.22)
                            opacity: root.showsOrbCover ? 1.0 : (root.auroraActive ? 0.0 : 1.0)
                            Behavior on opacity {
                                enabled: !Appearance.reduceMotion
                                NumberAnimation { duration: 300; easing.type: Easing.InOutQuad }
                            }
                            blankTopColor: Qt.rgba(root.accentPrimary.r * 0.28 + 0.06, root.accentPrimary.g * 0.28 + 0.06, root.accentPrimary.b * 0.28 + 0.08, 1)
                            blankBottomColor: Qt.rgba(root.accentSecondary.r * 0.22 + 0.04, root.accentSecondary.g * 0.22 + 0.04, root.accentSecondary.b * 0.22 + 0.06, 1)
                            squiggly: appSettings.waveOrbSquiggle && !root.auroraActive
                            squiggleFollowsPlayback: true
                            squiggleAmplitudeBoost: 1.25 + root.beatEnergy * 1.15
                            squiggleColor: root.accentPrimary
                            dim: coreHover.hovered ? 0.24 : 0.34
                            Behavior on dim { ElementMoveFast {} }
                            source: appSettings.waveOrbArtwork && root.inWave && backend.hasCover ? backend.nowCover : ""
                            placeholderSymbol: "my_wave"
                            fallbackKey: backend.listTitle || "Моя волна"
                            crossfade: true
                            revealDuration: 360
                        }

                        HoverHandler {
                            id: coreHover
                            cursorShape: Qt.PointingHandCursor
                        }

                        MouseArea {
                            id: coreMouse
                            anchors.fill: parent
                            enabled: !root.applying && !backend.listLoading
                            onClicked: {
                                if (!root.wavePlaying) UiState.burst(coreButton, "play");
                                root.toggleWavePlayback();
                            }
                        }

                        Column {
                            anchors.centerIn: parent
                            width: parent.width * 0.84
                            spacing: root.compact ? 6 : 8

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: root.compact ? 54 : 66
                                height: width
                                radius: width * 0.5
                                color: Qt.rgba(1, 1, 1, coreHover.hovered ? 0.28 : 0.18)
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.42)
                                Behavior on color { ElementMoveFastColor {} }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: root.applying || backend.listLoading ? "hourglass_top"
                                        : (root.wavePlaying ? "pause" : "play_arrow")
                                    iconSize: root.compact ? 28 : 36
                                    fill: 1
                                    color: "white"
                                }
                            }

                            TitleText {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: backend.listTitle || "Моя волна"
                                font.pixelSize: root.compact ? 22 : 29
                                font.weight: Font.Bold
                                color: "white"
                                style: Text.Raised
                                styleColor: Qt.rgba(0, 0, 0, 0.42)
                                elide: Text.ElideRight
                            }

                            StyledText {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: root.applying ? "Настраиваем поток…"
                                    : (root.wavePlaying ? "В эфире"
                                    : (root.inWave ? "На паузе" : "Запустить поток"))
                                font.pixelSize: Appearance.fontSize.smaller
                                font.weight: Font.Medium
                                color: Qt.rgba(1, 1, 1, 0.88)
                                style: Text.Raised
                                styleColor: Qt.rgba(0, 0, 0, 0.42)
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                // 2. Horizontal Row of Vibe / Active Filter Pills + "Настроить волну"
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width
                    spacing: 10

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8

                        // Active selected filters (with one-click removal)
                        Repeater {
                            model: root.activeFilterItems
                            delegate: Button {
                                id: activePill
                                required property var modelData
                                implicitHeight: 36
                                implicitWidth: activePillRow.implicitWidth + 24
                                hoverEnabled: true
                                enabled: !root.applying && !root.fetching
                                scale: down ? 0.95 : (hovered ? 1.03 : 1)
                                Behavior on scale { enabled: !Appearance.performanceMode; Bounce {} }
                                onClicked: root.selectAndApply(modelData.key, "")

                                contentItem: Row {
                                    id: activePillRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: activePill.modelData.name
                                        font.pixelSize: Appearance.fontSize.smaller
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.onPrimary
                                    }
                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "close"
                                        iconSize: 15
                                        color: Appearance.colors.onPrimary
                                    }
                                }
                                background: Rectangle {
                                    radius: 18
                                    color: Appearance.colors.primary
                                }
                            }
                        }

                        // Quick preset chips in one horizontal row when no filter is active
                        Repeater {
                            model: root.activeFilterCount === 0 ? root.quickPresetItems : []
                            delegate: Chip {
                                required property var modelData
                                text: modelData.name
                                chosen: false
                                enabled: !root.applying && !root.fetching
                                onClicked: root.selectAndApply(modelData.key, modelData.seed)
                            }
                        }
                    }

                    // "Настроить волну" Pill Button centered underneath
                    Button {
                        id: tuneBtn
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitHeight: 38
                        implicitWidth: tuneRow.implicitWidth + 32
                        hoverEnabled: true
                        scale: down ? 0.95 : (hovered ? 1.03 : 1)
                        Behavior on scale { enabled: !Appearance.performanceMode; Bounce {} }
                        onClicked: root.settingsOpen = true

                        contentItem: Row {
                            id: tuneRow
                            anchors.centerIn: parent
                            spacing: 7
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "tune"
                                iconSize: 18
                                color: Appearance.colors.onSecondaryContainer
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.activeFilterCount > 0
                                    ? ("Настроить волну · " + root.activeFilterCount)
                                    : "Настроить волну"
                                font.pixelSize: Appearance.fontSize.smaller
                                font.weight: Font.DemiBold
                                color: Appearance.colors.onSecondaryContainer
                            }
                        }
                        background: Rectangle {
                            radius: 19
                            color: tuneBtn.hovered
                                ? Appearance.colors.secondaryContainerHover
                                : Appearance.colors.secondaryContainer
                            Behavior on color { ElementMoveFastColor {} }
                        }
                    }
                }
            }
        }
    }

    // ========================================================================
    // Overlay Sheet: Frequency Tuner ("Настроить Мою волну")
    // ========================================================================
    T.Popup {
        id: settingsPopup
        parent: T.Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(820, parent ? parent.width - 48 : 820)
        height: Math.min(tunerHeader.implicitHeight + tunerFlick.contentHeight + tunerFooter.implicitHeight + 76,
                         parent ? parent.height - 48 : 680)
        modal: true
        focus: true
        closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutside
        padding: 0
        popupType: T.Popup.Item
        onOpened: root.settingsOpen = true
        onClosed: root.settingsOpen = false

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Appearance.duration(150) }
            NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: Appearance.motion(380); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.curves.expressiveFastSpatial }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; to: 0; duration: Appearance.duration(120) }
            NumberAnimation { property: "scale"; to: 0.97; duration: Appearance.duration(120) }
        }

        T.Overlay.modal: Rectangle {
            color: Appearance.colors.scrimOverlay
        }

        background: Rectangle {
            radius: 28
            color: Appearance.colors.surfaceContainer
            border.width: 1
            border.color: Appearance.colors.outlineVariant
            clip: true
        }

        contentItem: Item {
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 22
                spacing: 14

                RowLayout {
                    id: tunerHeader
                    Layout.fillWidth: true
                    spacing: 10

                    ShapeIcon {
                        size: 36
                        iconSize: 19
                        shape: "sunny"
                        symbol: "tune"
                        color: Appearance.colors.primaryContainer
                        iconColor: Appearance.colors.onPrimaryContainer
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        TitleText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: "Настроить Мою волну"
                            font.pixelSize: 21
                        }
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: "Выберите настроение, характер или язык потока"
                            font.pixelSize: Appearance.fontSize.smaller
                            color: Appearance.colors.onSurfaceVariant
                        }
                    }

                    IconButton {
                        symbol: "refresh"
                        tooltip: "Обновить список частот"
                        enabled: !root.fetching && !root.applying
                        onClicked: root.reload()
                    }

                    IconButton {
                        symbol: "close"
                        tooltip: "Закрыть"
                        onClicked: settingsPopup.close()
                    }
                }

                Flickable {
                    id: tunerFlick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: groupsCol.implicitHeight + 8
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: StyledScrollBar {}
                    FastWheel { target: tunerFlick }

                    ColumnLayout {
                        id: groupsCol
                        width: tunerFlick.width
                        spacing: 16

                        Repeater {
                            model: root.groups
                            delegate: ColumnLayout {
                                id: group
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 8

                                StyledText {
                                    text: group.modelData.name
                                    font.pixelSize: Appearance.fontSize.smaller
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.onSurfaceVariant
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 7

                                    Chip {
                                        text: "Любой"
                                        chosen: !root.selected[group.modelData.key]
                                        enabled: !root.applying && !root.fetching
                                        onClicked: root.select(group.modelData.key, "")
                                    }

                                    Repeater {
                                        model: group.modelData.choices
                                        delegate: Chip {
                                            required property var modelData
                                            text: modelData.name
                                            chosen: root.selected[group.modelData.key] === modelData.seed
                                            enabled: !root.applying && !root.fetching
                                            onClicked: root.select(group.modelData.key, modelData.seed)
                                        }
                                    }
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: root.fetching || (!root.fetching && root.groups.length === 0)
                            text: root.fetching ? "Загружаем частоты…" : "Фильтры пока недоступны."
                            color: Appearance.colors.onSurfaceVariant
                            wrapMode: Text.WordWrap
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: root.errorMessage.length > 0
                            text: root.errorMessage
                            color: Appearance.colors.error
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                RowLayout {
                    id: tunerFooter
                    Layout.fillWidth: true
                    spacing: 10

                    TextButton {
                        variant: TextButton.Tonal
                        symbol: "restart_alt"
                        text: "Сбросить"
                        enabled: !root.applying && !root.fetching && root.activeFilterCount > 0
                        onClicked: root.selected = ({})
                    }

                    Item { Layout.fillWidth: true }

                    TextButton {
                        id: applyWaveButton
                        variant: TextButton.Filled
                        wavy: applyWaveButton.enabled
                        symbol: "my_wave"
                        text: root.applying ? "Настраиваем…" : "Поймать волну"
                        enabled: !root.applying && !root.fetching
                        onClicked: {
                            root.applying = true;
                            root.errorMessage = "";
                            backend.feature({action: "wave_apply", selected: root.selected});
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: backend
        function onLoggedInChanged() {
            if (backend.loggedIn && root.groups.length === 0 && !root.fetching) {
                root.reload();
            }
        }
        function onFeatureResult(result) {
            if (result.type === "wave_settings") {
                root.fetching = false;
                root.errorMessage = "";
                root.selected = Object.assign({}, result.selected || {});
            } else if (result.type === "wave_error") {
                root.fetching = false;
                root.applying = false;
                root.errorMessage = result.message;
            } else if (result.type === "wave_applied") {
                root.applying = false;
                root.settingsOpen = false;
                root.selected = Object.assign({}, result.selected || {});
            }
        }
    }
}
