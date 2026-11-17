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
import QtQuick.Layouts
import ymusic.ui

ApplicationWindow {
    id: window

    readonly property real zoom: appSettings.zoom
    readonly property real layoutWidth: width / zoom
    readonly property real layoutHeight: height / zoom
    readonly property bool compactWindow: layoutWidth < 920
    readonly property bool rightPanelFits: layoutWidth - sidebar.width - Appearance.sizes.sideSheetWidth - 32 >= 404

    readonly property bool isHome: backend.page === 0
    readonly property bool isWavePage: backend.page === 1
    readonly property bool isCardsPage: backend.page >= 3 && backend.page <= 5
    readonly property bool isSearchPage: backend.page === 8
    readonly property bool isTrackListPage: backend.page === 2 || backend.page === 7
        || (!isHome && !isWavePage && !isCardsPage && !isSearchPage)

    readonly property bool isMacOS: Qt.platform.os === "osx"
    readonly property bool isWindows: Qt.platform.os === "windows"
    readonly property bool inAppWindowControls: !isMacOS && (isWindows ? !appSettings.nativeTitleBar : appSettings.showWindowControls)
    readonly property real titleBarInset: isMacOS ? 28
        : (inAppWindowControls && !appSettings.windowControlsOnRight ? 36 : 0)

    readonly property bool onScreen: visible && visibility !== Window.Minimized

    width: 1280
    height: 800
    minimumWidth: Math.ceil(500 * zoom)
    minimumHeight: Math.ceil(420 * zoom)
    visible: true
    title: backend.hasTrack ? (backend.nowTitle + " — Yandex Music") : "Yandex Music"
    flags: isMacOS ? (Qt.Window | Qt.ExpandedClientAreaHint | Qt.NoTitleBarBackgroundHint)
         : appSettings.nativeTitleBar ? (Qt.Window | Qt.WindowTitleHint | Qt.WindowSystemMenuHint | Qt.WindowMinMaxButtonsHint | Qt.WindowCloseButtonHint)
         : (Qt.Window | Qt.FramelessWindowHint)
    color: immersiveReveal > 0 ? PlayerStyle.darkScheme.layer0 : Appearance.colors.layer0
    onColorChanged: windowController.updateTheme(window, window.color)

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

    function openSettings() {
        if (!window.visible) {
            window.show();
            window.raise();
            window.requestActivate();
        }
        if (settingsLoader.item) {
            (settingsLoader.item as SettingsDialog).open();
        } else {
            settingsLoader.active = true;
        }
    }

    onClosing: (close) => {
        backend.saveSession();
        if (trayAvailable) {
            close.accepted = false;
            window.hide();
        }
    }

    // Zoom handling across window content and overlay popups
    readonly property real zoomStep: 0.05
    function setZoom(value: real) {
        appSettings.zoom = Number(Math.min(1.3, Math.max(0.8, value)).toFixed(2));
        toast.show("Масштаб " + Math.round(appSettings.zoom * 100) + "%");
    }
    property list<Item> zoomedItems
    function fitZoomed(item: Item) {
        const scale = appSettings.zoom;
        item.transformOrigin = Item.TopLeft;
        item.scale = scale;
        if (Math.abs(item.width - width / scale) > 0.01) item.width = width / scale;
        if (Math.abs(item.height - height / scale) > 0.01) item.height = height / scale;
    }
    function fitAllZoomed() {
        for (const item of zoomedItems) fitZoomed(item);
    }
    onZoomChanged: fitAllZoomed()
    onWidthChanged: fitAllZoomed()
    onHeightChanged: fitAllZoomed()
    Instantiator {
        model: window.zoomedItems
        delegate: Connections {
            required property Item modelData
            target: modelData
            function onWidthChanged() { window.fitZoomed(modelData); }
            function onHeightChanged() { window.fitZoomed(modelData); }
        }
    }
    function findZoomedItems() {
        const rootItem = contentItem.parent ? contentItem.parent.parent : null;
        if (!rootItem) return;
        zoomedItems = rootItem.children.filter(item => item === contentItem.parent || String(item).startsWith("QQuickOverlay"));
        fitAllZoomed();
    }

    Component.onCompleted: {
        windowController.attach(window, appSettings.nativeTitleBar);
        findZoomedItems();
    }

    Connections {
        target: appSettings
        function onNativeTitleBarChanged() {
            windowController.setNativeTitleBar(window, appSettings.nativeTitleBar);
        }
    }

    Connections {
        target: backend
        function onTrackMenuRequested(id, title, available, x, y) {
            trackMenu.prepareFor(id, title, available);
            const menuH = Math.max(380, trackMenu.implicitHeight + 16);
            const clampedX = Math.max(12, Math.min(x - trackMenu.width, window.layoutWidth - trackMenu.width - 12));
            const clampedY = Math.max(12, Math.min(y, window.layoutHeight - menuH));
            trackMenu.x = clampedX;
            trackMenu.y = clampedY;
            trackMenu.popup();
        }
    }

    // Keep spinning clocks paused when window is hidden or minimized
    Binding {
        target: UiState
        property: "spinning"
        value: backend.playing && window.onScreen
    }

    Item {
        id: shell
        anchors.fill: parent
        visible: window.onScreen && window.immersiveReveal < 1

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
            compact: window.compactWindow
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
                    visible: !backend.authReady && backend.page !== 7
                    LoadingSpinner { anchors.horizontalCenter: parent.horizontalCenter }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Восстановление сессии…"
                        color: Appearance.colors.onSurfaceVariant
                    }
                }

                // View 1: Login
                Loader {
                    id: loginView
                    anchors.fill: parent
                    active: backend.authReady && !backend.loggedIn && backend.page !== 7
                    sourceComponent: LoginView {}
                }

                // View 2: Home
                Loader {
                    id: homeView
                    anchors.fill: parent
                    active: backend.loggedIn && window.isHome
                    sourceComponent: HomeView {}
                }

                // View 3: Search
                Loader {
                    id: searchView
                    anchors.fill: parent
                    active: backend.loggedIn && window.isSearchPage
                    sourceComponent: SearchView {}
                }

                // View 3.5: My Wave Dedicated Stage
                Loader {
                    id: waveStageView
                    anchors.fill: parent
                    active: backend.loggedIn && window.isWavePage
                    sourceComponent: WaveHero {}
                }

                // View 4: Cards Grid (Playlists, Albums, Artists)
                Item {
                    id: cardsView
                    anchors.fill: parent
                    visible: backend.loggedIn && window.isCardsPage

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
                        model: backend.cards

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
                                    text: backend.page === 3 ? "Плейлисты"
                                        : (backend.page === 4 ? "Альбомы"
                                        : (backend.page === 5 ? "Любимые артисты"
                                        : (backend.listTitle.length > 0 ? backend.listTitle : "Обзор")))
                                    font.pixelSize: Appearance.fontSize.huge + 2
                                    font.weight: Font.Bold
                                    elide: Text.ElideRight
                                }

                                TextButton {
                                    visible: backend.page === 3
                                    variant: TextButton.Tonal
                                    wavy: true
                                    symbol: "add"
                                    text: "Создать плейлист"
                                    onClicked: createPlaylist.open()
                                }
                            }

                            StyledText {
                                width: parent.width
                                visible: backend.listSubtitle.length > 0
                                text: backend.listSubtitle
                                color: Appearance.colors.onSurfaceVariant
                            }
                        }

                        delegate: CardItem {
                            required property int index
                            required property var model
                            cardIndex: index
                            cardData: model
                            width: 178
                            height: 252
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 12
                        visible: backend.cards.count === 0 && backend.listLoading
                        LoadingSpinner { anchors.horizontalCenter: parent.horizontalCenter }
                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Загрузка коллекции…"
                            color: Appearance.colors.onSurfaceVariant
                        }
                    }

                    EmptyState {
                        anchors.centerIn: parent
                        width: Math.min(420, parent.width - 48)
                        visible: backend.cards.count === 0 && !backend.listLoading
                        symbol: "library_music"
                        title: "Здесь пока пусто"
                        description: "В этом разделе пока нет подборок"
                    }
                }

                // View 5: Track List / Wave / Collection / Downloads
                Item {
                    id: trackListView
                    anchors.fill: parent
                    visible: (backend.loggedIn || backend.page === 7) && window.isTrackListPage

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
                        model: backend.tracks

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
                                visible: backend.isArtistView && backend.cards.count > 0

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
                                    Layout.preferredHeight: 256
                                    leftMargin: 12
                                    rightMargin: 12
                                    orientation: ListView.Horizontal
                                    spacing: 16
                                    clip: true
                                    reuseItems: true
                                    model: trackListView.visible && backend.isArtistView ? backend.cards : null
                                    delegate: CardItem {
                                        required property int index
                                        required property var model
                                        cardIndex: index
                                        cardData: model
                                        width: 174
                                        height: 234
                                    }
                                }
                            }

                            Item { Layout.preferredHeight: 24 }
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 14
                        visible: backend.tracks.count === 0 && backend.listLoading
                        LoadingSpinner { anchors.horizontalCenter: parent.horizontalCenter }
                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: backend.page === 1 ? "Настраиваем Мою волну…" : "Загрузка треков…"
                            font.pixelSize: Appearance.fontSize.large
                            font.weight: Font.DemiBold
                        }
                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: backend.page === 1 ? "Подбираем треки под ваше настроение" : "Секундочку…"
                            color: Appearance.colors.onSurfaceVariant
                        }
                    }

                    EmptyState {
                        anchors.centerIn: parent
                        width: Math.min(440, parent.width - 48)
                        visible: backend.tracks.count === 0 && !backend.listLoading
                        symbol: backend.page === 2 ? "favorite" : "music_note"
                        title: backend.page === 7 ? "Пока ничего не загружено"
                             : (backend.page === 2 ? "Пока нет любимых треков" : "Нет треков")
                        description: backend.page === 7 ? "Откройте меню трека или нажмите «Скачать всё» в коллекции"
                                   : (backend.page === 2 ? "Отмечайте треки сердцем, чтобы найти их здесь"
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
                windowControlsOnRight: window.inAppWindowControls && appSettings.windowControlsOnRight
                inspectorShown: inspector.shown
            }

            // Status / error snackbar
            Snackbar {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: topBar.bottom
                anchors.topMargin: 4
                z: 40
                message: backend.statusMessage
                onDismissed: backend.clearStatus()
            }

            // Auto-update ready banner (Windows)
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: topBar.bottom
                anchors.topMargin: 8
                width: Math.min(540, sheet.width - 40)
                height: 68
                visible: updater.updateBannerVisible
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
                            text: updater.readyToInstall
                                ? ("Обновление v" + updater.latestVersion + " готово")
                                : ("Доступна версия v" + updater.latestVersion)
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: updater.readyToInstall
                                ? "Нажмите, чтобы перезапустить и установить"
                                : "Откройте страницу релиза на GitHub для обновления"
                            font.pixelSize: Appearance.fontSize.smaller
                            color: Appearance.colors.onSurfaceVariant
                            elide: Text.ElideRight
                        }
                    }
                    TextButton {
                        variant: TextButton.Filled
                        symbol: updater.readyToInstall ? "restart_alt" : "open_in_new"
                        text: updater.readyToInstall ? "Перезапустить и обновить" : "Скачать"
                        onClicked: updater.installAndRestart()
                    }
                    IconButton {
                        Layout.alignment: Qt.AlignVCenter
                        symbol: "close"
                        size: 32
                        iconSize: 18
                        onClicked: updater.dismissBanner()
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
                visible: backend.batch.running === true
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
                        running: visible
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            text: backend.batch.title || "Скачивание коллекции"
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        StyledText {
                            text: (backend.batch.done || 0) + " / " + (backend.batch.total || 0)
                                + (backend.batch.failed > 0 ? (" · ошибок: " + backend.batch.failed) : "")
                            font.pixelSize: Appearance.fontSize.smaller
                            color: Appearance.colors.onSurfaceVariant
                        }
                    }
                    TextButton {
                        variant: TextButton.Tonal
                        symbol: "close"
                        text: "Отменить"
                        onClicked: backend.feature({action: "cancel_download"})
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
                Reveal.shown: backend.loggedIn || backend.page === 7 || backend.hasTrack
                onImmersiveRequested: UiState.openImmersive()
            }
        }

        // Right sliding inspector sheet (Lyrics / Queue)
        Item {
            id: inspector
            readonly property bool shown: (UiState.showingLyrics || UiState.showingQueue)
                && !UiState.immersiveOpen
                && window.rightPanelFits
                && (backend.loggedIn || backend.page === 7 || backend.hasTrack)
            anchors.right: parent.right
            anchors.rightMargin: shown ? 8 : 0
            anchors.top: parent.top
            anchors.topMargin: 8 + (window.inAppWindowControls && appSettings.windowControlsOnRight ? 36 : 0)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            width: shown ? Appearance.sizes.sideSheetWidth : 0
            clip: true
            visible: width > 0.5

            Behavior on width {
                enabled: !Appearance.performanceMode && window.rightPanelFits
                SpringAnimation { spring: 4; damping: 0.32; epsilon: 0.5 }
            }

            Rectangle {
                width: Appearance.sizes.sideSheetWidth
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
        const scaled = appSettings.fastImmersiveTransition ? Math.round(milliseconds * 0.42) : milliseconds;
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
                window.revealShape = appSettings.noShapes ? "circle"
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
                    to: appSettings.fastImmersiveTransition ? 1 : 0.2
                    duration: window.shapeMotion(appSettings.fastImmersiveTransition ? 420 : 260)
                    easing.type: appSettings.fastImmersiveTransition ? Easing.OutCubic : Easing.OutBack
                    easing.overshoot: 2.4
                }
                PauseAnimation { duration: appSettings.fastImmersiveTransition ? 0 : window.shapeMotion(60) }
                NumberAnimation {
                    target: window
                    property: "revealReach"
                    to: 1
                    duration: appSettings.fastImmersiveTransition ? 0 : window.shapeMotion(280)
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
        x: appSettings.windowControlsOnRight ? parent.width - width - 12 : 12
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
            enabled: !appSettings.nativeTitleBar && !window.isMacOS && !window.isWindows
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

    Loader {
        id: settingsLoader
        active: false
        asynchronous: true
        onLoaded: (item as SettingsDialog).open()
        sourceComponent: SettingsDialog {
            onClosed: Qt.callLater(() => {
                const dialog = settingsLoader.item as SettingsDialog;
                if (dialog && !dialog.visible) {
                    settingsLoader.active = false;
                }
            })
        }
    }

    CreatePlaylistDialog {
        id: createPlaylist
        parent: Overlay.overlay
    }

    TrackMenu {
        id: trackMenu
        parent: Overlay.overlay
    }

    // Global keyboard shortcuts
    Shortcut { sequence: "Space"; enabled: backend.hasTrack && !UiState.immersiveOpen; onActivated: backend.toggle() }
    Shortcut { sequence: "Ctrl+Right"; enabled: backend.hasTrack; onActivated: backend.next() }
    Shortcut { sequence: "Ctrl+Left"; enabled: backend.hasTrack; onActivated: backend.prev() }
    Shortcut {
        sequence: "Ctrl+Alt+Right"
        enabled: backend.hasTrack && backend.durationSecs > 0
        onActivated: backend.seek(Math.min(1, (backend.positionSecs + 10) / backend.durationSecs))
    }
    Shortcut {
        sequence: "Ctrl+Alt+Left"
        enabled: backend.hasTrack && backend.durationSecs > 0
        onActivated: backend.seek(Math.max(0, (backend.positionSecs - 10) / backend.durationSecs))
    }
    Shortcut { sequence: "Ctrl+Up"; onActivated: backend.setVolume(Math.min(1, backend.volume + 0.05)) }
    Shortcut { sequence: "Ctrl+Down"; onActivated: backend.setVolume(Math.max(0, backend.volume - 0.05)) }
    Shortcut { sequence: "Ctrl+Alt+M"; onActivated: backend.toggleMute() }
    Shortcut { sequence: "Ctrl+Alt+S"; enabled: backend.hasTrack; onActivated: backend.toggleShuffle() }
    Shortcut { sequence: "Ctrl+Alt+R"; enabled: backend.hasTrack; onActivated: backend.toggleRepeat() }
    Shortcut { sequence: "Ctrl+,"; onActivated: window.openSettings() }
    Shortcut { sequences: [StandardKey.Back]; enabled: backend.canGoBack && !UiState.immersiveOpen; onActivated: backend.goBack() }
    Shortcut { sequence: "Escape"; enabled: backend.canGoBack && !UiState.immersiveOpen; onActivated: backend.goBack() }
    Shortcut { sequences: [StandardKey.Find, "Ctrl+K"]; enabled: !UiState.immersiveOpen; onActivated: topBar.focusSearch() }
    Shortcut { sequences: ["Ctrl++", "Ctrl+="]; onActivated: window.setZoom(window.zoom + window.zoomStep) }
    Shortcut { sequences: ["Ctrl+-"]; onActivated: window.setZoom(window.zoom - window.zoomStep) }
    Shortcut { sequence: "Ctrl+0"; onActivated: window.setZoom(1.0) }
}
