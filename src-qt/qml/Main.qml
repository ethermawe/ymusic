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
import QtQml
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Templates as T
import ymusic.ui

ApplicationWindow {
    id: window

    readonly property real zoom: AppSettings.zoom
    readonly property real layoutWidth: width / zoom
    readonly property real layoutHeight: height / zoom
    readonly property bool compactWindow: layoutWidth < 920
    property bool sidebarResizing: false
    property bool sidebarDragCompact: false
    property real liveSidebarWidth: AppSettings.sidebarWidth
    property bool inspectorResizing: false
    property real liveRightPanelWidth: AppSettings.rightPanelWidth
    readonly property real maxSidebarWidth: Math.max(160, Math.min(340, layoutWidth - 650))
    readonly property real desiredRightPanelWidth: inspectorResizing ? liveRightPanelWidth : AppSettings.rightPanelWidth
    readonly property real maxRightPanelWidth: Math.max(200, Math.min(520, layoutWidth - sidebar.width - 436))
    readonly property real activeRightPanelWidth: Math.max(200, Math.min(desiredRightPanelWidth, maxRightPanelWidth))
    readonly property bool rightPanelFits: layoutWidth - sidebar.width - 200 - 32 >= 404

    readonly property bool isModPage: UiState.activeModPageId.length > 0
    readonly property bool isHome: !isModPage && Backend.page === 0
    readonly property bool isWavePage: !isModPage && Backend.page === 1
    readonly property bool isCardsPage: !isModPage && Backend.page >= 3 && Backend.page <= 5
    readonly property bool isSearchPage: !isModPage && Backend.page === 8
    readonly property bool isTrackListPage: !isModPage && (Backend.page === 2 || Backend.page === 7
        || (!isHome && !isWavePage && !isCardsPage && !isSearchPage))

    readonly property bool isMacOS: Qt.platform.os === "osx"
    readonly property bool isWindows: Qt.platform.os === "windows"
    readonly property bool inAppWindowControls: !isMacOS && (isWindows ? !AppSettings.nativeTitleBar : AppSettings.showWindowControls)
    readonly property real titleBarInset: isMacOS ? 28
        : (inAppWindowControls && !AppSettings.windowControlsOnRight ? 36 : 0)

    readonly property bool onScreen: visible && visibility !== Window.Minimized

    width: 1280
    height: 800
    minimumWidth: Math.ceil(500 * zoom)
    minimumHeight: Math.ceil(420 * zoom)
    visible: true
    title: Backend.hasTrack ? (Backend.nowTitle + " — Yandex Music") : "Yandex Music"
    flags: isMacOS ? (Qt.Window | Qt.ExpandedClientAreaHint | Qt.NoTitleBarBackgroundHint)
         : AppSettings.nativeTitleBar ? (Qt.Window | Qt.WindowTitleHint | Qt.WindowSystemMenuHint | Qt.WindowMinMaxButtonsHint | Qt.WindowCloseButtonHint)
         : (Qt.Window | Qt.FramelessWindowHint)
    color: immersiveReveal > 0 ? PlayerStyle.darkScheme.layer0 : Appearance.colors.layer0
    onColorChanged: WindowController.updateTheme(window, window.color)

    function closeCrowdedPanels() {
        if (!rightPanelFits) {
            UiState.showingLyrics = false;
            UiState.showingQueue = false;
        }
    }
    onRightPanelFitsChanged: closeCrowdedPanels()

    Connections {
        target: UiState
        function onShowingLyricsChanged() { window.closeCrowdedPanels(); }
        function onShowingQueueChanged() { window.closeCrowdedPanels(); }
        function onToastRequested(message: string) { toast.show(message); }
        function onCreatePlaylistRequested() { createPlaylist.open(); }
        function onSettingsRequested() { window.openSettings(); }
    }

    Connections {
        target: ModManager
        function onToastRequested(message: string) { toast.show(message); }
        function onImmersiveRequested(open: bool) {
            if (open) UiState.openImmersive();
            else UiState.closeImmersive();
        }
        function onSettingsRequested() { window.openSettings(); }
        function onCreatePlaylistRequested() { createPlaylist.open(); }
    }

    function openSettings() {
        if (!window.visible) {
            window.show();
            window.raise();
            window.requestActivate();
        }
        const dialog = settingsLoader.item as T.Popup;
        if (dialog) {
            dialog.open();
        } else {
            settingsLoader.active = true;
        }
    }

    onClosing: (close) => {
        Backend.saveSession();
        if (WindowController.trayAvailable && AppSettings.minimizeToTray) {
            close.accepted = false;
            window.hide();
        }
    }

    // Zoom handling across window content and overlay popups
    readonly property real zoomStep: 0.05
    function setZoom(value: real) {
        AppSettings.zoom = Number(Math.min(1.3, Math.max(0.8, value)).toFixed(2));
        toast.show("Масштаб " + Math.round(AppSettings.zoom * 100) + "%");
    }
    function syncOverlayZoom() {
        const overlay = Overlay.overlay;
        if (!overlay) return;
        const s = window.zoom;
        overlay.transformOrigin = Item.TopLeft;
        overlay.scale = s;
        if (Math.abs(overlay.width - window.width / s) > 0.01) overlay.width = window.width / s;
        if (Math.abs(overlay.height - window.height / s) > 0.01) overlay.height = window.height / s;
    }
    onZoomChanged: syncOverlayZoom()
    onWidthChanged: syncOverlayZoom()
    onHeightChanged: syncOverlayZoom()
    Connections {
        target: Overlay.overlay
        function onWidthChanged() { Qt.callLater(window.syncOverlayZoom); }
        function onHeightChanged() { Qt.callLater(window.syncOverlayZoom); }
    }

    Component.onCompleted: {
        WindowController.attach(window, AppSettings.nativeTitleBar);
        syncOverlayZoom();
        Qt.callLater(window.syncOverlayZoom);
        Qt.callLater(() => {
            const current = Updater.currentVersion;
            if (!current || current.length === 0) return;
            const seen = AppSettings.lastSeenVersion;
            if (seen.length === 0) {
                AppSettings.lastSeenVersion = current;
            } else if (seen !== current && whatsNewDialog.items.length > 0) {
                whatsNewDialog.open();
            }
        });
    }

    Connections {
        target: AppSettings
        function onNativeTitleBarChanged() {
            WindowController.setNativeTitleBar(window, AppSettings.nativeTitleBar);
        }
    }

    Connections {
        target: Backend
        function onTrackMenuRequested(id, title, available, x, y) {
            trackMenu.prepareFor(id, title, available);
            const s = Math.max(0.01, window.zoom);
            const lx = x / s;
            const ly = y / s;
            const menuW = Math.max(240, trackMenu.implicitWidth);
            const menuH = Math.max(260, trackMenu.implicitHeight);
            const fitsRight = lx + menuW <= window.layoutWidth - 12;
            const clampedX = Math.max(12, Math.min(fitsRight ? lx : lx - menuW, window.layoutWidth - menuW - 12));
            const fitsDown = ly + menuH <= window.layoutHeight - 12;
            const clampedY = Math.max(12, Math.min(fitsDown ? ly : ly - menuH, window.layoutHeight - menuH - 12));
            trackMenu.popup(null, clampedX, clampedY);
        }
    }

    // Keep spinning clocks paused when window is hidden or minimized
    Binding {
        target: UiState
        property: "spinning"
        value: Backend.playing && window.onScreen
    }

    // Two-phase organic shape mask transition for Immersive Player
    property real immersiveReveal: 0
    property real revealReach: 0
    property real revealSpin: 0
    readonly property bool immersiveFades: Appearance.reduceMotion && !Appearance.performanceMode
    property real immersiveFade: 1
    property real revealSpinStart: 0
    property string revealShape: "cookie9"
    readonly property list<string> revealShapes: [
        "cookie9", "cookie6", "clover4", "clover8", "sunny", "verySunny",
        "softBurst", "burst", "flower", "puffy", "pentagon", "gem"
    ]

    function shapeMotion(milliseconds: int): int {
        if (immersiveFades) return 0;
        const scaled = AppSettings.fastImmersiveTransition ? Math.round(milliseconds * 0.42) : milliseconds;
        return Appearance.motion(scaled);
    }

    function finishOpening() {
        if (!immersiveFades) {
            immersiveReveal = 1;
        } else if (immersiveLoader.status === Loader.Ready) {
            fadeInMotion.restart();
        }
    }

    Connections {
        target: UiState
        function onImmersiveOpenChanged() {
            if (UiState.immersiveOpen) {
                window.revealShape = AppSettings.noShapes ? "circle"
                    : window.revealShapes[Math.floor(Math.random() * window.revealShapes.length)];
            }
            openMotion.stop();
            fadeInMotion.stop();
            closeMotion.stop();
            window.revealSpinStart = window.revealSpin % (2 * Math.PI);
            window.revealSpin = window.revealSpinStart;
            if (UiState.immersiveOpen) {
                openMotion.start();
            } else {
                closeMotion.start();
            }
        }
    }

    SequentialAnimation {
        id: openMotion
        PropertyAction { target: window; property: "immersiveFade"; value: window.immersiveFades ? 0 : 1 }
        PropertyAction { target: window; property: "immersiveReveal"; value: 0.01 }
        ParallelAnimation {
            NumberAnimation {
                target: window
                property: "revealSpin"
                to: window.revealSpinStart + 1.6 * Math.PI
                duration: window.shapeMotion(600)
                easing.type: Easing.Linear
            }
            SequentialAnimation {
                NumberAnimation {
                    target: window
                    property: "revealReach"
                    to: AppSettings.fastImmersiveTransition ? 1 : 0.2
                    duration: window.shapeMotion(AppSettings.fastImmersiveTransition ? 420 : 260)
                    easing.type: AppSettings.fastImmersiveTransition ? Easing.OutCubic : Easing.OutBack
                    easing.overshoot: 2.4
                }
                PauseAnimation { duration: AppSettings.fastImmersiveTransition ? 0 : window.shapeMotion(60) }
                NumberAnimation {
                    target: window
                    property: "revealReach"
                    to: 1
                    duration: AppSettings.fastImmersiveTransition ? 0 : window.shapeMotion(280)
                    easing.type: Easing.InBack
                    easing.overshoot: 1.2
                }
            }
        }
        ScriptAction { script: window.finishOpening() }
    }

    SequentialAnimation {
        id: fadeInMotion
        NumberAnimation {
            target: window
            property: "immersiveFade"
            to: 1
            duration: 240
            easing.type: Easing.OutCubic
        }
        PropertyAction { target: window; property: "immersiveReveal"; value: 1 }
    }

    SequentialAnimation {
        id: closeMotion
        PropertyAction { target: window; property: "immersiveReveal"; value: Math.min(window.immersiveReveal, 0.99) }
        NumberAnimation {
            target: window
            property: "immersiveFade"
            to: window.immersiveFades ? 0 : 1
            duration: window.immersiveFades ? 200 : 0
            easing.type: Easing.InCubic
        }
        ParallelAnimation {
            NumberAnimation {
                target: window
                property: "immersiveReveal"
                to: 0
                duration: window.shapeMotion(520)
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: window
                property: "revealReach"
                to: 0
                duration: window.shapeMotion(520)
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: window
                property: "revealSpin"
                to: window.revealSpinStart + 1.4
                duration: window.shapeMotion(520)
                easing.type: Easing.OutCubic
            }
        }
        PropertyAction { target: window; property: "immersiveFade"; value: 1 }
    }

    Item {
        id: zoomRoot
        x: 0
        y: 0
        width: window.layoutWidth
        height: window.layoutHeight
        transformOrigin: Item.TopLeft
        scale: window.zoom

        Item {
            id: shell
        anchors.fill: parent
        visible: window.onScreen && window.immersiveReveal < 1

        ModSlotHost {
            anchors.fill: parent
            z: -1
            slotName: "window.backdrop"
        }

        ModSlotHost {
            width: 0
            height: 0
            visible: false
            slotName: "background.host"
        }

        // Dismiss active search focus / suggestions when clicking empty space or another control.
        MouseArea {
            anchors.fill: parent
            z: 1000
            enabled: topBar.searchEditing
            acceptedButtons: Qt.AllButtons
            propagateComposedEvents: true
            onPressed: (mouse) => {
                if (!topBar.isSearchInteractiveAt(shell, mouse.x, mouse.y)) {
                    topBar.dismissSearch();
                }
                mouse.accepted = false;
            }
        }

        // Top window drag & maximize strip under window controls and panels
        Item {
            width: parent.width
            height: Math.max(window.titleBarInset, window.inAppWindowControls ? 36 : 0) + 8

            DragHandler {
                target: null
                onActiveChanged: if (active) window.startSystemMove()
            }
            TapHandler {
                onDoubleTapped: window.visibility === Window.Maximized ? window.showNormal() : window.showMaximized()
            }
        }

        Sidebar {
            id: sidebar
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: 8 + window.titleBarInset
            anchors.leftMargin: 8
            anchors.bottomMargin: 8
            compact: window.compactWindow || (window.sidebarResizing ? window.sidebarDragCompact : AppSettings.sidebarCollapsed)
            expandedWidth: window.sidebarResizing
                ? window.liveSidebarWidth
                : Math.max(160, Math.min(AppSettings.sidebarWidth, window.maxSidebarWidth))
            resizing: window.sidebarResizing
            toggleVisible: !window.compactWindow
            onToggleCompactRequested: AppSettings.sidebarCollapsed = !AppSettings.sidebarCollapsed
            onSettingsRequested: window.openSettings()
        }

        Rectangle {
            id: sheet
            anchors.left: sidebar.right
            anchors.leftMargin: 8
            anchors.right: inspector.left
            anchors.rightMargin: 8
            anchors.top: parent.top
            anchors.topMargin: 8
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            radius: Appearance.rounding.large
            color: Appearance.colors.layer1

            Item {
                id: pageContent
                anchors.fill: parent
                clip: true

                // Restoring session splash
                Column {
                    anchors.centerIn: parent
                    spacing: 14
                    visible: !Backend.authReady && Backend.page !== 7
                    LoadingSpinner { anchors.horizontalCenter: parent.horizontalCenter }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Восстановление сессии…"
                        color: Appearance.colors.onSurfaceVariant
                    }
                }

                // View 1: Login
                PageTransition {
                    id: loginPage
                    anchors.fill: parent
                    shown: Backend.authReady && !Backend.loggedIn && Backend.page !== 7

                    Loader {
                        id: loginView
                        anchors.fill: parent
                        active: loginPage.shown
                        sourceComponent: LoginView {}
                    }
                }

                // View 2: Home
                PageTransition {
                    id: homePage
                    anchors.fill: parent
                    shown: Backend.loggedIn && window.isHome

                    Loader {
                        id: homeView
                        anchors.fill: parent
                        active: Backend.loggedIn && homePage.everShown
                        sourceComponent: HomeView {}
                    }
                }

                // Custom Mod Page (from Sidebar)
                PageTransition {
                    id: modPage
                    anchors.fill: parent
                    shown: window.isModPage
                    transitionKey: UiState.activeModPageId

                    ModSlotHost {
                        anchors.fill: parent
                        anchors.topMargin: Appearance.sizes.topBarHeight + 6
                        anchors.bottomMargin: Appearance.sizes.playerBarClearance
                        slotName: "sidebar.page"
                        filterEntryId: UiState.activeModPageId
                    }
                }

                // View 3: Search
                PageTransition {
                    id: searchPage
                    anchors.fill: parent
                    shown: Backend.loggedIn && window.isSearchPage
                    transitionKey: Backend.searchQuery

                    Loader {
                        id: searchView
                        anchors.fill: parent
                        active: Backend.loggedIn && searchPage.visible
                        sourceComponent: SearchView {}
                    }
                }

                // View 3.5: My Wave Dedicated Stage
                PageTransition {
                    id: wavePage
                    anchors.fill: parent
                    shown: Backend.loggedIn && window.isWavePage

                    Loader {
                        id: waveStageView
                        anchors.fill: parent
                        active: Backend.loggedIn && wavePage.visible
                        sourceComponent: WaveHero {}
                    }
                }

                // View 4: Cards Grid (Playlists, Albums, Artists)
                PageTransition {
                    id: cardsView
                    anchors.fill: parent
                    shown: Backend.loggedIn && window.isCardsPage
                    transitionKey: String(Backend.page)

                    GridView {
                        id: cardsGrid
                        anchors.fill: parent
                        anchors.leftMargin: Appearance.sizes.pageMargin
                        anchors.rightMargin: Appearance.sizes.pageMargin
                        topMargin: Appearance.sizes.topBarHeight + 12
                        bottomMargin: Appearance.sizes.playerBarClearance
                        clip: true
                        cellWidth: 194
                        cellHeight: 264
                        reuseItems: true
                        maximumFlickVelocity: 5000
                        flickDeceleration: 2400
                        displayMarginBeginning: 200
                        displayMarginEnd: 200
                        model: Backend.cards

                        displaced: Transition {
                            enabled: !Appearance.performanceMode
                            NumberAnimation {
                                properties: "x,y"
                                duration: Appearance.motion(320)
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.curves.expressiveDefaultSpatial
                            }
                        }

                        FastWheel { target: cardsGrid }
                        ScrollBar.vertical: StyledScrollBar { topPadding: 3 + Appearance.sizes.topBarHeight }

                        header: Column {
                            width: cardsGrid.width
                            spacing: 10
                            bottomPadding: 18

                            RowLayout {
                                width: parent.width
                                spacing: 12

                                TitleText {
                                    Layout.fillWidth: true
                                    text: Backend.page === 3 ? "Плейлисты"
                                        : (Backend.page === 4 ? "Альбомы"
                                        : (Backend.page === 5 ? "Любимые артисты"
                                        : (Backend.listTitle.length > 0 ? Backend.listTitle : "Обзор")))
                                    font.pixelSize: Appearance.fontSize.huge + 2
                                    font.weight: Font.Bold
                                    elide: Text.ElideRight
                                }

                                TextButton {
                                    visible: Backend.page === 3
                                    variant: TextButton.Tonal
                                    wavy: true
                                    symbol: "add"
                                    text: "Создать плейлист"
                                    onClicked: createPlaylist.open()
                                }
                            }

                            StyledText {
                                width: parent.width
                                visible: Backend.listSubtitle.length > 0
                                text: Backend.listSubtitle
                                color: Appearance.colors.onSurfaceVariant
                            }
                        }

                        delegate: CardItem {
                            required property int index
                            required property var model
                            cardIndex: index
                            cardData: model
                            width: 178
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 12
                        visible: Backend.cards.count === 0 && Backend.listLoading
                        LoadingSpinner {
                            anchors.horizontalCenter: parent.horizontalCenter
                            running: visible
                        }
                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Загрузка коллекции…"
                            color: Appearance.colors.onSurfaceVariant
                        }
                    }

                    EmptyState {
                        anchors.centerIn: parent
                        width: Math.min(420, parent.width - 48)
                        visible: Backend.cards.count === 0 && !Backend.listLoading
                        symbol: "library_music"
                        title: "Здесь пока пусто"
                        description: "В этом разделе пока нет подборок"
                    }
                }

                // View 5: Track List / Wave / Collection / Downloads
                PageTransition {
                    id: trackListView
                    anchors.fill: parent
                    shown: (Backend.loggedIn || Backend.page === 7) && window.isTrackListPage
                    transitionKey: String(Backend.page) + ":" + Backend.activePlaylistKey

                    ListView {
                        id: listView
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        topMargin: Appearance.sizes.topBarHeight + 6
                        bottomMargin: Appearance.sizes.playerBarClearance
                        clip: true
                        reuseItems: true
                        maximumFlickVelocity: 5000
                        flickDeceleration: 2400
                        displayMarginBeginning: 200
                        displayMarginEnd: 200
                        model: Backend.tracks

                        displaced: Transition {
                            enabled: !Appearance.performanceMode
                            NumberAnimation {
                                properties: "x,y"
                                duration: Appearance.motion(300)
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.curves.expressiveDefaultSpatial
                            }
                        }

                        FastWheel { target: listView }
                        ScrollBar.vertical: StyledScrollBar { topPadding: 3 + Appearance.sizes.topBarHeight }

                        header: CollectionHero {
                            width: listView.width
                        }

                        delegate: TrackRow {
                            width: listView.width
                        }

                        footer: ColumnLayout {
                            width: listView.width
                            spacing: 16

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 18
                                spacing: 12
                                visible: Backend.isArtistView && Backend.cards.count > 0

                                SectionHeader {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 12
                                    Layout.rightMargin: 12
                                    title: "Альбомы и релизы"
                                    symbol: "album"
                                    iconShape: "sunny"
                                }

                                ListView {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 268
                                    leftMargin: 12
                                    rightMargin: 12
                                    orientation: ListView.Horizontal
                                    spacing: 16
                                    clip: true
                                    reuseItems: true
                                    model: trackListView.shown && Backend.isArtistView ? Backend.cards : null
                                    delegate: Item {
                                        id: artistAlbumSlot
                                        required property int index
                                        required property var model
                                        width: 174
                                        height: artistAlbumCard.implicitHeight + 16
                                        CardItem {
                                            id: artistAlbumCard
                                            y: 8
                                            cardIndex: artistAlbumSlot.index
                                            cardData: artistAlbumSlot.model
                                            width: 174
                                        }
                                    }
                                }
                            }

                            Item { Layout.preferredHeight: 24 }
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 14
                        visible: Backend.tracks.count === 0 && Backend.listLoading
                        LoadingSpinner {
                            anchors.horizontalCenter: parent.horizontalCenter
                            running: visible
                        }
                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Backend.page === 1 ? "Настраиваем Мою волну…" : "Загрузка треков…"
                            font.pixelSize: Appearance.fontSize.large
                            font.weight: Font.DemiBold
                        }
                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Backend.page === 1 ? "Подбираем треки под ваше настроение" : "Секундочку…"
                            color: Appearance.colors.onSurfaceVariant
                        }
                    }

                    EmptyState {
                        anchors.centerIn: parent
                        width: Math.min(440, parent.width - 48)
                        visible: Backend.tracks.count === 0 && !Backend.listLoading
                        symbol: Backend.page === 2 ? "favorite" : "music_note"
                        title: Backend.page === 7 ? "Пока ничего не загружено"
                             : (Backend.page === 2 ? "Пока нет любимых треков" : "Нет треков")
                        description: Backend.page === 7 ? "Откройте меню трека или нажмите «Скачать всё» в коллекции"
                                   : (Backend.page === 2 ? "Отмечайте треки сердцем, чтобы найти их здесь"
                                   : "Треки появятся здесь, когда будут доступны")
                    }
                }
            }

            // Flying artwork transitions between grid cards and collection heroes
            Item {
                anchors.fill: parent
                clip: true

                HeroFlight {
                    anchors.fill: parent
                }
            }

            // Rounded mask corners over scrolled content
            CornerCaps {
                anchors.fill: parent
                radius: sheet.radius
                color: window.color
            }

            // Floating transparent TopBar with live blur on SearchField
            TopBar {
                id: topBar
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                window: window
                backdropSource: pageContent
                windowControlsOnRight: window.inAppWindowControls && AppSettings.windowControlsOnRight
                inspectorShown: inspector.shown
            }

            // Status / error snackbar
            Snackbar {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: topBar.bottom
                anchors.topMargin: 4
                z: 40
                message: Backend.statusMessage
                onDismissed: Backend.clearStatus()
            }

            // Auto-update ready banner (Windows)
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: topBar.bottom
                anchors.topMargin: 8
                width: Math.min(540, sheet.width - 40)
                height: 68
                Reveal.shown: Updater.updateBannerVisible
                Reveal.scaleFrom: 0.92
                Reveal.overshoot: 1.8
                color: Appearance.colors.surfaceContainerHigh
                border.width: 1
                border.color: Appearance.colors.outlineVariant
                radius: Appearance.rounding.normal
                z: 39

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    anchors.topMargin: 10
                    anchors.bottomMargin: 10
                    spacing: 12

                    ShapeIcon {
                        Layout.alignment: Qt.AlignVCenter
                        size: 36
                        iconSize: 20
                        shape: "cookie9"
                        symbol: "system_update"
                        color: Appearance.colors.primaryContainer
                        iconColor: Appearance.colors.onPrimaryContainer
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            text: Updater.readyToInstall
                                ? ("Обновление v" + Updater.latestVersion + " готово")
                                : ("Доступна версия v" + Updater.latestVersion)
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Updater.readyToInstall
                                ? "Нажмите, чтобы перезапустить и установить"
                                : "Откройте страницу релиза на GitHub для обновления"
                            font.pixelSize: Appearance.fontSize.smaller
                            color: Appearance.colors.onSurfaceVariant
                            elide: Text.ElideRight
                        }
                    }
                    TextButton {
                        variant: TextButton.Filled
                        symbol: Updater.readyToInstall ? "restart_alt" : "open_in_new"
                        text: Updater.readyToInstall ? "Перезапустить и обновить" : "Скачать"
                        onClicked: Updater.installAndRestart()
                    }
                    IconButton {
                        Layout.alignment: Qt.AlignVCenter
                        symbol: "close"
                        size: 32
                        iconSize: 18
                        onClicked: Updater.dismissBanner()
                    }
                }
            }

            // Batch offline download progress pill
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: playerBar.top
                anchors.bottomMargin: 12
                width: Math.min(540, sheet.width - 40)
                height: 70
                Reveal.shown: Backend.batch.running === true
                Reveal.scaleFrom: 0.92
                Reveal.overshoot: 1.8
                color: Appearance.colors.surfaceContainerHigh
                border.width: 1
                border.color: Appearance.colors.outlineVariant
                radius: Appearance.rounding.normal
                z: 50

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    LoadingSpinner {
                        Layout.alignment: Qt.AlignVCenter
                        width: 24
                        height: 24
                        running: Backend.batch.running === true
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            text: Backend.batch.title || "Скачивание коллекции"
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        StyledText {
                            text: (Backend.batch.done || 0) + " / " + (Backend.batch.total || 0)
                                + (Backend.batch.failed > 0 ? (" · ошибок: " + Backend.batch.failed) : "")
                            font.pixelSize: Appearance.fontSize.smaller
                            color: Appearance.colors.onSurfaceVariant
                        }
                    }
                    TextButton {
                        variant: TextButton.Tonal
                        symbol: "close"
                        text: "Отменить"
                        onClicked: Backend.feature({action: "cancel_download"})
                    }
                }
            }

            // Floating Pill Player Bar
            FloatingPlayerBar {
                id: playerBar
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: window.compactWindow ? 10 : 14
                width: Math.max(0, Math.min(760, sheet.width - (window.compactWindow ? 24 : 36)))
                Reveal.shown: Backend.loggedIn || Backend.page === 7 || Backend.hasTrack
                onImmersiveRequested: UiState.openImmersive()
            }
        }

        // Right sliding inspector sheet (Lyrics / Queue)
        Item {
            id: inspector
            readonly property bool shown: (UiState.showingLyrics || UiState.showingQueue)
                && !UiState.immersiveOpen
                && window.rightPanelFits
                && (Backend.loggedIn || Backend.page === 7 || Backend.hasTrack)
            anchors.right: parent.right
            anchors.rightMargin: shown ? 8 : 0
            anchors.top: parent.top
            anchors.topMargin: 8 + (window.inAppWindowControls && AppSettings.windowControlsOnRight ? 36 : 0)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            width: shown ? window.activeRightPanelWidth : 0
            clip: true
            visible: width > 0.5

            Behavior on width {
                enabled: !Appearance.performanceMode && window.rightPanelFits && !window.inspectorResizing
                SpringAnimation { spring: 4; damping: 0.32; epsilon: 0.5 }
            }

            Rectangle {
                width: window.activeRightPanelWidth
                height: parent.height
                radius: Appearance.rounding.large
                color: Appearance.colors.layer1

                LyricsPanel {
                    anchors.fill: parent
                    Reveal.shown: UiState.showingLyrics
                    suspended: UiState.immersiveOpen || !inspector.visible
                }
                QueuePanel {
                    anchors.fill: parent
                    Reveal.shown: UiState.showingQueue
                }
            }
        }

        // Left sidebar mouse resize handle (with drag-to-collapse threshold)
        Item {
            id: sidebarHandle
            visible: !window.compactWindow && sidebar.visible
            x: sidebar.x + sidebar.width - 2
            y: sidebar.y
            width: 12
            height: sidebar.height
            z: 20

            Rectangle {
                anchors.centerIn: parent
                width: sidebarDrag.pressed ? 3 : 2
                height: sidebarDrag.pressed ? Math.min(84, parent.height * 0.20) : 44
                radius: width / 2
                color: sidebarDrag.pressed ? Appearance.colors.primary : Appearance.colors.outlineVariant
                opacity: (sidebarDrag.containsMouse || sidebarDrag.pressed) ? 0.92 : 0

                Behavior on opacity {
                    NumberAnimation { duration: Appearance.duration(140) }
                }
                Behavior on height {
                    enabled: !Appearance.performanceMode
                    ElementMoveFast {}
                }
            }

            MouseArea {
                id: sidebarDrag
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.SizeHorCursor
                property real startMouseX: 0
                property real startWidth: 220

                onPressed: (mouse) => {
                    startMouseX = mapToItem(shell, mouse.x, mouse.y).x;
                    startWidth = sidebar.width;
                    window.sidebarDragCompact = sidebar.isCompact;
                    window.liveSidebarWidth = startWidth;
                    window.sidebarResizing = true;
                }
                onPositionChanged: (mouse) => {
                    if (!pressed) return;
                    const curX = mapToItem(shell, mouse.x, mouse.y).x;
                    const raw = startWidth + (curX - startMouseX);
                    if (raw <= 122) {
                        window.sidebarDragCompact = true;
                        window.liveSidebarWidth = 72;
                    } else {
                        window.sidebarDragCompact = false;
                        window.liveSidebarWidth = Math.max(160, Math.min(window.maxSidebarWidth, raw));
                    }
                }
                onReleased: {
                    AppSettings.sidebarCollapsed = window.sidebarDragCompact;
                    if (!window.sidebarDragCompact) {
                        AppSettings.sidebarWidth = window.liveSidebarWidth;
                    }
                    window.sidebarResizing = false;
                }
                onCanceled: window.sidebarResizing = false
                onDoubleClicked: {
                    window.sidebarResizing = false;
                    AppSettings.sidebarCollapsed = false;
                    AppSettings.sidebarWidth = 220;
                }
            }
        }

        // Right lyrics/queue panel mouse resize handle (no collapse button)
        Item {
            id: inspectorHandle
            visible: inspector.shown && inspector.width > 1
            x: inspector.x - 10
            y: inspector.y
            width: 12
            height: inspector.height
            z: 20

            Rectangle {
                anchors.centerIn: parent
                width: inspectorDrag.pressed ? 3 : 2
                height: inspectorDrag.pressed ? Math.min(84, parent.height * 0.20) : 44
                radius: width / 2
                color: inspectorDrag.pressed ? Appearance.colors.primary : Appearance.colors.outlineVariant
                opacity: (inspectorDrag.containsMouse || inspectorDrag.pressed) ? 0.92 : 0

                Behavior on opacity {
                    NumberAnimation { duration: Appearance.duration(140) }
                }
                Behavior on height {
                    enabled: !Appearance.performanceMode
                    ElementMoveFast {}
                }
            }

            MouseArea {
                id: inspectorDrag
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.SizeHorCursor
                property real startMouseX: 0
                property real startWidth: 320

                onPressed: (mouse) => {
                    startMouseX = mapToItem(shell, mouse.x, mouse.y).x;
                    startWidth = inspector.width;
                    window.liveRightPanelWidth = startWidth;
                    window.inspectorResizing = true;
                }
                onPositionChanged: (mouse) => {
                    if (!pressed) return;
                    const curX = mapToItem(shell, mouse.x, mouse.y).x;
                    const raw = startWidth - (curX - startMouseX);
                    window.liveRightPanelWidth = Math.max(200, Math.min(window.maxRightPanelWidth, raw));
                }
                onReleased: {
                    AppSettings.rightPanelWidth = window.liveRightPanelWidth;
                    window.inspectorResizing = false;
                }
                onCanceled: window.inspectorResizing = false
                onDoubleClicked: {
                    window.inspectorResizing = false;
                    AppSettings.rightPanelWidth = 320;
                }
            }
        }
    }

    Loader {
        id: immersiveLoader
        anchors.fill: parent
        visible: window.onScreen && window.immersiveReveal > 0
        active: window.immersiveReveal > 0
        asynchronous: true
        focus: UiState.immersiveOpen
        opacity: window.immersiveFade
        z: 100
        onLoaded: {
            if (window.immersiveFades && UiState.immersiveOpen && !openMotion.running && window.immersiveReveal < 1) {
                fadeInMotion.restart();
            }
        }

        layer.enabled: window.immersiveReveal > 0 && window.immersiveReveal < 1
        layer.effect: ShaderEffect {
            property variant source
            property size itemSize: Qt.size(width, height)
            property vector4d shape: {
                const picked = Shapes.params(window.revealShape);
                return Qt.vector4d(Math.min(picked.x, 5), picked.y, picked.z, picked.w);
            }
            property real reach: Math.max(0, window.revealReach) * Math.hypot(width, height) / 2
                                 / (shape.w > 0.5 ? 1 : 1 - shape.y) + 2
            property real spin: window.revealSpin
            fragmentShader: "qrc:/shaders/shape_mask.frag.qsb"
        }

        sourceComponent: ImmersivePlayer {
            windowControlsTopInset: window.inAppWindowControls ? appWindowControls.y + appWindowControls.height : 0
            focus: true
            onCloseRequested: UiState.closeImmersive()
        }
    }

    WindowControls {
        id: appWindowControls
        objectName: "appWindowControls"
        z: 150
        x: AppSettings.windowControlsOnRight ? parent.width - width - 12 : 12
        y: 8
        visible: window.inAppWindowControls && window.visibility !== Window.FullScreen
        compact: true
        scheme: window.immersiveReveal > 0 ? PlayerStyle.darkScheme : Appearance.colors
        window: window
    }

    // Frameless edge/corner resize handles for platforms without native WM hit-test
    Repeater {
        model: [
            { edge: Qt.LeftEdge, cursor: Qt.SizeHorCursor, lx: 0, ly: 8, lw: 5, lh: -16 },
            { edge: Qt.RightEdge, cursor: Qt.SizeHorCursor, rx: 0, ly: 8, lw: 5, lh: -16 },
            { edge: Qt.TopEdge, cursor: Qt.SizeVerCursor, lx: 8, ly: 0, lw: -16, lh: 5 },
            { edge: Qt.BottomEdge, cursor: Qt.SizeVerCursor, lx: 8, by: 0, lw: -16, lh: 5 },
            { edge: Qt.TopEdge | Qt.LeftEdge, cursor: Qt.SizeFDiagCursor, lx: 0, ly: 0, lw: 10, lh: 10 },
            { edge: Qt.TopEdge | Qt.RightEdge, cursor: Qt.SizeBDiagCursor, rx: 0, ly: 0, lw: 10, lh: 10 },
            { edge: Qt.BottomEdge | Qt.LeftEdge, cursor: Qt.SizeBDiagCursor, lx: 0, by: 0, lw: 10, lh: 10 },
            { edge: Qt.BottomEdge | Qt.RightEdge, cursor: Qt.SizeFDiagCursor, rx: 0, by: 0, lw: 10, lh: 10 }
        ]

        delegate: MouseArea {
            required property var modelData
            z: 250
            enabled: !AppSettings.nativeTitleBar && !window.isMacOS && !window.isWindows
                && window.visibility === Window.Windowed
            visible: enabled
            cursorShape: modelData.cursor
            x: modelData.rx !== undefined ? parent.width - modelData.lw : modelData.lx
            y: modelData.by !== undefined ? parent.height - modelData.lh : modelData.ly
            width: modelData.lw < 0 ? parent.width + modelData.lw : modelData.lw
            height: modelData.lh < 0 ? parent.height + modelData.lh : modelData.lh
            onPressed: window.startSystemResize(modelData.edge)
        }
    }

    Toast {
        id: toast
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 16
        z: 200
    }

    Item {
        id: bursts
        anchors.fill: parent
        z: 210

        function sceneOf(item: Item): Item {
            let top = item;
            while (top.parent !== null) top = top.parent;
            return top;
        }

        Connections {
            target: UiState
            function onBurstRequested(item: Item, kind: string) {
                if (bursts.sceneOf(item) !== bursts.sceneOf(bursts)) return;
                const at = item.mapToItem(bursts, item.width / 2, item.height / 2);
                burstComponent.createObject(bursts, { x: at.x, y: at.y, kind: kind });
            }
        }

        Component {
            id: burstComponent
            ShapeBurst {}
        }
    }
    }

    Loader {
        id: settingsLoader
        active: false
        asynchronous: true
        onLoaded: {
            const dialog = item as T.Popup;
            if (dialog) dialog.open();
        }
        sourceComponent: SettingsDialog {
            onClosed: Qt.callLater(() => {
                const dialog = settingsLoader.item as T.Popup;
                if (dialog && !dialog.visible && ModManager.pendingRestartPrompt) {
                    restartModsDialog.open();
                }
            })
        }
    }

    StyledDialog {
        id: restartModsDialog
        parent: Overlay.overlay
        headline: "Перезапустить приложение?"
        symbol: "restart_alt"
        iconShape: "cookie9"
        body: ModManager.overridesNeedRestart
            ? "Вы изменили моды с подменой вёрстки. Перезапустите клиент, чтобы все изменения применились полностью."
            : "Вы изменили список активных модов. Перезапустить клиент сейчас для чистого применения всех изменений?"
        buttons: [
            TextButton {
                text: "Позже"
                variant: TextButton.Text
                onClicked: {
                    ModManager.dismissRestartPrompt();
                    restartModsDialog.close();
                }
            },
            TextButton {
                text: "Перезапустить"
                variant: TextButton.Filled
                symbol: "restart_alt"
                onClicked: {
                    restartModsDialog.accept();
                    Backend.saveSession();
                    ModManager.requestAppRestart();
                }
            }
        ]
    }

    CreatePlaylistDialog {
        id: createPlaylist
        parent: Overlay.overlay
    }

    WhatsNewDialog {
        id: whatsNewDialog
        parent: Overlay.overlay
    }

    TrackMenu {
        id: trackMenu
        parent: Overlay.overlay
    }

    // Global keyboard shortcuts
    Shortcut { sequence: "Space"; enabled: Backend.hasTrack && !UiState.immersiveOpen; onActivated: Backend.toggle() }
    Shortcut { sequence: "Ctrl+Right"; enabled: Backend.hasTrack; onActivated: Backend.next() }
    Shortcut { sequence: "Ctrl+Left"; enabled: Backend.hasTrack; onActivated: Backend.prev() }
    Shortcut {
        sequence: "Ctrl+Alt+Right"
        enabled: Backend.hasTrack && Backend.durationSecs > 0
        onActivated: Backend.seek(Math.min(1, (Backend.positionSecs + 10) / Backend.durationSecs))
    }
    Shortcut {
        sequence: "Ctrl+Alt+Left"
        enabled: Backend.hasTrack && Backend.durationSecs > 0
        onActivated: Backend.seek(Math.max(0, (Backend.positionSecs - 10) / Backend.durationSecs))
    }
    Shortcut { sequence: "Ctrl+Up"; onActivated: Backend.setVolume(Math.min(1, Backend.volume + AppSettings.volumeStep)) }
    Shortcut { sequence: "Ctrl+Down"; onActivated: Backend.setVolume(Math.max(0, Backend.volume - AppSettings.volumeStep)) }
    Shortcut { sequence: "Ctrl+Alt+M"; onActivated: Backend.toggleMute() }
    Shortcut { sequence: "Ctrl+Alt+S"; enabled: Backend.hasTrack; onActivated: Backend.toggleShuffle() }
    Shortcut { sequence: "Ctrl+Alt+R"; enabled: Backend.hasTrack; onActivated: Backend.toggleRepeat() }
    Shortcut { sequence: "Ctrl+,"; onActivated: window.openSettings() }
    Shortcut { sequences: [StandardKey.Back]; enabled: Backend.canGoBack && !UiState.immersiveOpen; onActivated: Backend.goBack() }
    Shortcut { sequence: "Escape"; enabled: Backend.canGoBack && !UiState.immersiveOpen; onActivated: Backend.goBack() }
    Shortcut { sequences: [StandardKey.Find, "Ctrl+K"]; enabled: !UiState.immersiveOpen; onActivated: topBar.focusSearch() }
    Shortcut { sequences: ["Ctrl++", "Ctrl+="]; onActivated: window.setZoom(window.zoom + window.zoomStep) }
    Shortcut { sequences: ["Ctrl+-"]; onActivated: window.setZoom(window.zoom - window.zoomStep) }
    Shortcut { sequence: "Ctrl+0"; onActivated: window.setZoom(1.0) }
    Shortcut {
        sequence: "Ctrl+Shift+R"
        enabled: ModManager.modsEnabled
        onActivated: {
            ModManager.reloadMods();
            toast.show("Моды перезагружены");
        }
    }

    Instantiator {
        model: ModManager.shortcuts
        delegate: Shortcut {
            required property var modelData
            sequence: modelData.sequence || ""
            enabled: ModManager.modsEnabled && sequence.length > 0
            onActivated: ModManager.triggerShortcut(modelData.modId, modelData.actionId)
        }
    }
}
