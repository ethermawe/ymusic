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

FocusScope {
    id: root

    signal closeRequested()

    property MaterialScheme scheme: PlayerStyle.darkScheme
    property real windowControlsTopInset: 0

    readonly property list<string> panels: ["", "lyrics", "queue", "sleep", "audio"]
    property string panel: ""
    property string shownPanel: ""
    property real panelOpacity: 1
    property real panelShift: 0
    property bool layoutMoving: false

    property bool distractionFree: false
    property bool controlsHidden: false
    property int savedVisibility: Window.Windowed
    property real lastMouseX: -1
    property real lastMouseY: -1
    property real controlsOpacity: 1
    readonly property bool panelRetainedInDistractionFree: shownPanel === "lyrics" || shownPanel === "queue"
    readonly property real panelDistractionFreeOpacity: panelRetainedInDistractionFree ? 1 : controlsOpacity

    NumberAnimation {
        id: hideControlsAnimation
        target: root
        property: "controlsOpacity"
        to: 0
        duration: Appearance.duration(400)
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: showControlsAnimation
        target: root
        property: "controlsOpacity"
        to: 1
        duration: Appearance.duration(200)
        easing.type: Easing.OutCubic
    }

    onControlsHiddenChanged: {
        if (distractionFree && controlsHidden) {
            showControlsAnimation.stop();
            hideControlsAnimation.restart();
            if (!panelRetainedInDistractionFree && usesPanelLayout) {
                layoutMoving = true;
                settle.restart();
            }
        } else {
            hideControlsAnimation.stop();
            showControlsAnimation.restart();
            if (!panelRetainedInDistractionFree && usesPanelLayout) {
                layoutMoving = true;
                settle.restart();
            }
        }
    }

    Timer {
        id: inactivityTimer
        interval: 5000
        running: root.distractionFree && !root.controlsHidden
        onTriggered: root.controlsHidden = true
    }

    function registerActivity() {
        if (!distractionFree) return;
        controlsHidden = false;
        inactivityTimer.restart();
    }

    function toggleDistractionFree() {
        setDistractionFree(!distractionFree);
    }

    function setDistractionFree(enable: bool) {
        if (distractionFree === enable) return;
        distractionFree = enable;
        const win = root.Window.window;
        if (enable) {
            if (win) {
                if (win.visibility !== Window.FullScreen) {
                    savedVisibility = win.visibility;
                }
                win.showFullScreen();
            }
            lastMouseX = -1;
            lastMouseY = -1;
            controlsHidden = false;
            hideControlsAnimation.stop();
            showControlsAnimation.stop();
            controlsOpacity = 1;
            inactivityTimer.restart();
        } else {
            inactivityTimer.stop();
            controlsHidden = false;
            hideControlsAnimation.stop();
            showControlsAnimation.stop();
            controlsOpacity = 1;
            if (win && win.visibility === Window.FullScreen) {
                if (savedVisibility === Window.Maximized) win.showMaximized();
                else win.showNormal();
            }
        }
    }

    Component.onDestruction: {
        if (root.distractionFree) {
            root.setDistractionFree(false);
        }
    }

    readonly property bool usesPanelLayout: panel.length > 0
    readonly property bool showsSpectrum: appSettings.visualizersEnabled && appSettings.immersiveVisualizer && !appSettings.circularVisualizer
    readonly property bool effectiveUsesPanelLayout: distractionFree && controlsHidden ? panelRetainedInDistractionFree : usesPanelLayout

    readonly property real metadataWidth: Math.max(300, Math.min(400, width * 0.32))
    readonly property real horizontalPadding: Math.max(28, Math.min(64, width * 0.05))
    readonly property real rowSpace: Math.min(1250, width - 2 * horizontalPadding)
    readonly property real gap: Math.max(32, Math.min(72, width * 0.055))
    readonly property bool sideBySide: effectiveUsesPanelLayout && rowSpace >= 900
    readonly property bool panelOnly: effectiveUsesPanelLayout && !sideBySide
    readonly property real panelWidth: sideBySide ? Math.min(540, (rowSpace - gap) / 2) : rowSpace
    readonly property real nowPlayingWidth: sideBySide ? Math.min(500, rowSpace - gap - panelWidth) : Math.min(620, rowSpace)
    readonly property real rowWidth: sideBySide ? nowPlayingWidth + gap + panelWidth : nowPlayingWidth
    readonly property real panelHeight: Math.min(520, immersiveLayout.contentHeight)
    readonly property real panelX: sideBySide ? (width - rowWidth) / 2 + nowPlayingWidth + gap : (width - panelWidth) / 2
    readonly property real panelSlide: Math.min(140, panelWidth * 0.3)

    component LayoutMotion: NumberAnimation {
        duration: Appearance.motion(500)
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.curves.expressiveDefaultSpatial
    }

    function resolvedPanel(preference: string): string {
        if (preference === "artwork" || panels.indexOf(preference) < 0) return "";
        return preference;
    }

    property string pendingPanel
    property bool pendingRemembers: true

    function swapPanel(next: string, remembers: bool) {
        if (next === panel && !swap.running && !leavePanel.running) return;
        pendingPanel = next;
        pendingRemembers = remembers;
        swap.stop();
        enterPanel.stop();
        leavePanel.stop();
        if (next.length > 0 && panel.length === 0) {
            commitPanel();
            if (shownPanel !== next) {
                shownPanel = next;
                panelOpacity = 0;
                panelShift = 1;
            }
            enterPanel.start();
        } else if (next.length === 0) {
            commitPanel();
            leavePanel.start();
        } else {
            swap.start();
        }
    }

    function commitPanel() {
        if (pendingRemembers) {
            appSettings.immersivePlayerPanel = pendingPanel.length > 0 ? pendingPanel : "artwork";
        }
        if (pendingPanel.length > 0 !== usesPanelLayout) {
            layoutMoving = true;
            settle.restart();
        }
        panel = pendingPanel;
        if (panel === "lyrics") {
            UiState.ensureLyrics(true);
        }
    }

    ParallelAnimation {
        id: enterPanel
        LayoutMotion { target: root; property: "panelShift"; to: 0 }
        NumberAnimation { target: root; property: "panelOpacity"; to: 1; duration: Appearance.duration(320); easing.type: Easing.OutCubic }
    }

    SequentialAnimation {
        id: leavePanel
        ParallelAnimation {
            LayoutMotion { target: root; property: "panelShift"; to: 1 }
            NumberAnimation { target: root; property: "panelOpacity"; to: 0; duration: Appearance.duration(260); easing.type: Easing.OutQuad }
        }
        ScriptAction { script: if (root.panel.length === 0) root.shownPanel = "" }
    }

    SequentialAnimation {
        id: swap
        NumberAnimation { target: root; property: "panelOpacity"; to: 0; duration: Appearance.duration(160); easing.type: Easing.OutQuad }
        ScriptAction {
            script: {
                root.commitPanel();
                root.shownPanel = root.pendingPanel;
                root.panelShift = 0;
            }
        }
        NumberAnimation {
            target: root
            property: "panelOpacity"
            to: 1
            duration: Appearance.duration(380)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.curves.emphasizedDecel
        }
    }

    Timer {
        id: settle
        interval: 520
        onTriggered: root.layoutMoving = false
    }

    Component.onCompleted: {
        panel = resolvedPanel(appSettings.immersivePlayerPanel);
        shownPanel = panel;
        if (panel === "lyrics") UiState.ensureLyrics(true);
        forceActiveFocus();
    }

    Keys.onPressed: (event) => {
        root.registerActivity();
        switch (event.key) {
        case Qt.Key_Space:
            backend.toggle();
            break;
        case Qt.Key_Escape:
            if (root.distractionFree) root.setDistractionFree(false);
            else root.closeRequested();
            break;
        case Qt.Key_Left:
            if (backend.durationSecs > 0)
                backend.seek(Math.max(0, (backend.positionSecs - 10) / backend.durationSecs));
            break;
        case Qt.Key_Right:
            if (backend.durationSecs > 0)
                backend.seek(Math.min(1, (backend.positionSecs + 10) / backend.durationSecs));
            break;
        case Qt.Key_Up:
            backend.setVolume(Math.min(backend.volume + 0.05, 1));
            break;
        case Qt.Key_Down:
            backend.setVolume(Math.max(backend.volume - 0.05, 0));
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    ImmersiveLayout {
        id: immersiveLayout
        windowWidth: root.width
        windowHeight: root.height - Math.max(0, topBar.height - 70)
        showsSpectrum: root.showsSpectrum
        showsPanel: root.sideBySide
        circular: appSettings.visualizersEnabled && appSettings.immersiveVisualizer && appSettings.circularVisualizer
    }

    LiquidBackdrop {
        id: backdrop
        anchors.fill: parent
        shown: root.visible
    }

    Stickers {
        anchors.fill: parent
        key: (backend.nowId || "immersive") + "-" + backend.nowAlbum
        count: 6
        minimumSize: Math.max(150, Math.round(Math.min(root.width, root.height) * 0.24))
        maximumSize: Math.max(280, Math.round(Math.min(root.width, root.height) * 0.46))
        scheme: root.scheme
        strength: 0.35
    }

    HoverHandler {
        cursorShape: (root.distractionFree && root.controlsHidden) ? Qt.BlankCursor : Qt.ArrowCursor
        onPointChanged: {
            const px = point.position.x;
            const py = point.position.y;
            if (root.lastMouseX < 0 && root.lastMouseY < 0) {
                root.lastMouseX = px;
                root.lastMouseY = py;
                return;
            }
            if (Math.abs(px - root.lastMouseX) > 2 || Math.abs(py - root.lastMouseY) > 2) {
                root.lastMouseX = px;
                root.lastMouseY = py;
                root.registerActivity();
            }
        }
    }

    Item {
        anchors.fill: parent
        z: 9999
        visible: root.distractionFree && root.controlsHidden
        HoverHandler { cursorShape: Qt.BlankCursor }
    }

    TapHandler {
        onTapped: {
            root.forceActiveFocus();
            root.registerActivity();
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.AllDevices
        onWheel: (event) => {
            if (panelHost.visible && (root.shownPanel === "lyrics" || root.shownPanel === "queue" || root.shownPanel === "audio")) {
                const pos = root.mapToItem(panelHost, event.x, event.y);
                if (pos.x >= 0 && pos.x <= panelHost.width && pos.y >= 0 && pos.y <= panelHost.height) {
                    event.accepted = false;
                    return;
                }
            }
            const deltaUnits = event.angleDelta.y !== 0 ? event.angleDelta.y : event.pixelDelta.y;
            if (deltaUnits === 0) {
                event.accepted = false;
                return;
            }
            root.registerActivity();
            backend.setVolume(Math.max(0, Math.min(1, backend.volume + (deltaUnits / 120.0) * 0.05)));
            event.accepted = true;
        }
    }

    Item {
        id: topBar
        width: parent.width
        height: Math.max(immersiveLayout.topBarHeight, immersiveClose.y + immersiveClose.height + 2)
        opacity: root.controlsOpacity
        visible: opacity > 0
        enabled: opacity > 0

        DragHandler {
            target: null
            grabPermissions: PointerHandler.CanTakeOverFromAnything
            onActiveChanged: if (active) root.Window.window.startSystemMove()
        }
        TapHandler {
            acceptedButtons: Qt.LeftButton
            onDoubleTapped: {
                if (root.distractionFree) {
                    root.setDistractionFree(false);
                } else {
                    const win = root.Window.window;
                    win.visibility === Window.Maximized ? win.showNormal() : win.showMaximized();
                }
            }
        }

        IconButton {
            id: immersiveClose
            anchors.left: parent.left
            anchors.leftMargin: 24
            y: Math.max(18, (appSettings.windowControlsOnRight ? 0 : root.windowControlsTopInset) + 6)
            scheme: root.scheme
            symbol: "close"
            size: 34
            iconSize: 18
            iconColor: "white"
            colBackground: Qt.rgba(1, 1, 1, 0.12)
            colBackgroundHover: Qt.rgba(1, 1, 1, 0.2)
            colRipple: Qt.rgba(1, 1, 1, 0.24)
            backgroundItem.border.width: 1
            backgroundItem.border.color: Qt.rgba(1, 1, 1, 0.14)
            tooltip: "Закрыть полный экран"
            onClicked: {
                if (root.distractionFree) root.setDistractionFree(false);
                root.closeRequested();
            }
        }

        IconButton {
            id: immersiveDistractionFree
            anchors.left: immersiveClose.right
            anchors.leftMargin: 8
            y: immersiveClose.y
            scheme: root.scheme
            symbol: root.distractionFree ? "fullscreen_exit" : "fullscreen"
            size: 34
            iconSize: 18
            iconColor: "white"
            colBackground: root.distractionFree ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(1, 1, 1, 0.12)
            colBackgroundHover: Qt.rgba(1, 1, 1, 0.2)
            colRipple: Qt.rgba(1, 1, 1, 0.24)
            backgroundItem.border.width: 1
            backgroundItem.border.color: Qt.rgba(1, 1, 1, 0.14)
            tooltip: root.distractionFree ? "Выйти из полноэкранного режима" : "На весь экран"
            onClicked: root.toggleDistractionFree()
        }

        SegmentedControl {
            id: switcher
            anchors.right: parent.right
            anchors.rightMargin: 24
            y: Math.max(18, (appSettings.windowControlsOnRight ? root.windowControlsTopInset : 0) + 6)
            scheme: root.scheme
            segmentHeight: 30
            horizontalPadding: 12
            iconSize: 19
            trackColor: Qt.rgba(1, 1, 1, 0.12)
            indicatorColor: Qt.rgba(1, 1, 1, 0.92)
            contentColor: Qt.rgba(1, 1, 1, 0.86)
            selectedContentColor: "#141414"
            currentIndex: Math.max(0, root.panels.indexOf(root.panel))
            segments: [
                Segment { symbol: "image"; tooltip: "Обложка" },
                Segment { symbol: "lyrics"; tooltip: "Текст песни" },
                Segment { symbol: "queue_music"; tooltip: "Очередь" },
                Segment { symbol: "bedtime"; tooltip: "Таймер сна" },
                Segment { symbol: "tune"; tooltip: "Звук и спектр" }
            ]
            onActivated: (index) => {
                const next = root.panels[index];
                root.swapPanel(next, true);
            }
        }

        LoadingSpinner {
            anchors.horizontalCenter: switcher.horizontalCenter
            anchors.bottom: switcher.top
            anchors.bottomMargin: 2
            width: 12
            height: 12
            Reveal.shown: UiState.lyricsLoading
            running: visible
            color: "white"
            trackColor: Qt.rgba(1, 1, 1, 0.16)
        }
    }

    Item {
        id: content
        y: topBar.height
        width: parent.width
        height: immersiveLayout.contentHeight

        ImmersiveNowPlaying {
            id: nowPlaying
            Reveal.shown: backend.hasTrack && !root.panelOnly
            layout: immersiveLayout
            metadataWidth: Math.min(root.metadataWidth, root.nowPlayingWidth)
            animateLayout: root.layoutMoving
            scheme: root.scheme
            controlsOpacity: root.controlsOpacity
            width: root.nowPlayingWidth
            x: (content.width - root.rowWidth) / 2
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: root.distractionFree ? (1.0 - root.controlsOpacity) * nowPlaying.controlsShift : 0

            Behavior on x {
                enabled: root.layoutMoving || root.distractionFree
                LayoutMotion {}
            }
            Behavior on width {
                enabled: root.layoutMoving || root.distractionFree
                LayoutMotion {}
            }
        }

        Loader {
            id: panelHost
            visible: backend.hasTrack && root.shownPanel.length > 0 && opacity > 0
            x: root.panelX + root.panelShift * root.panelSlide
            width: root.panelWidth
            height: root.panelHeight
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.panelOpacity * root.panelDistractionFreeOpacity
            active: backend.hasTrack && root.shownPanel.length > 0
            sourceComponent: {
                switch (root.shownPanel) {
                case "lyrics": return lyrics;
                case "queue": return queue;
                case "sleep": return sleep;
                case "audio": return sound;
                default: return null;
                }
            }
        }

        EmptyState {
            anchors.centerIn: parent
            Reveal.shown: !backend.hasTrack
            scheme: root.scheme
            symbol: "music_note"
            title: "Ничего не играет"
            description: "Выберите трек или включите Мою волну"
        }
    }

    Component { id: lyrics; ImmersiveLyrics { scheme: root.scheme } }
    Component { id: queue; ImmersiveQueue { scheme: root.scheme } }
    Component { id: sleep; SleepTimerPanel { scheme: root.scheme } }
    Component {
        id: sound
        Flickable {
            id: soundScroll
            contentHeight: soundPanel.implicitHeight + 24
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            FastWheel { target: soundScroll }

            SoundPanel {
                id: soundPanel
                y: 12
                width: soundScroll.width
                scheme: root.scheme
            }
        }
    }

    SpectrumView {
        visible: opacity > 0
        x: 42
        y: content.y + content.height + immersiveLayout.spectrumSpacing
        width: parent.width - 84
        height: immersiveLayout.spectrumHeight
        kind: SpectrumView.Immersive
        wave: appSettings.visualizerShape === "wave"
        continuous: appSettings.continuousVisualizer
        sensitivity: appSettings.visualizerSensitivity
        active: backend.playing && root.showsSpectrum
        opacity: !root.showsSpectrum ? 0 : (root.usesPanelLayout ? 0.74 : 1)

        Behavior on opacity {
            NumberAnimation { duration: Appearance.duration(240); easing.type: Easing.OutQuad }
        }
    }
}
