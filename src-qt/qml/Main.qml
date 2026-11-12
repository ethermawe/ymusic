import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ymusic.ui

ApplicationWindow {
    id: window

    visible: true
    width: 1200
    height: 760
    minimumWidth: 860
    minimumHeight: 560
    title: "Yandex Music"
    color: Appearance.colors.surfaceContainerLowest

    property bool immersiveOpen: false
    CreatePlaylistDialog { id: createPlaylist; parent: Overlay.overlay }
    Shortcut { sequence: "Ctrl+N"; enabled: backend.loggedIn; onActivated: createPlaylist.open() }
    Shortcut { sequence: "Ctrl+Right"; onActivated: backend.next() }
    Shortcut { sequence: "Ctrl+Left"; onActivated: backend.prev() }
    Shortcut { sequence: "Ctrl+Space"; onActivated: backend.toggle() }
    Shortcut { sequence: "Ctrl+,"; onActivated: settingsDialog.open() }
    SearchView {
        parent: sheet
        anchors.fill: parent
        anchors.margins: 24
        visible: backend.loggedIn && backend.page === 8
        z: 2
    }
    SettingsDialog {
        id: settingsDialog
        parent: Overlay.overlay
    }
    Connections {
        target: backend
        function onTrackMenuRequested(id, title, available, x, y) {
            trackMenu.x = Math.max(0, Math.min(window.contentItem.width - trackMenu.width, x));
            trackMenu.y = Math.max(8, Math.min(y, window.contentItem.height - trackMenu.implicitHeight - 8));
            trackMenu.showFor(id, title, available);
        }
    }

    TrackMenu {
        id: trackMenu
        parent: window.contentItem
    }
    readonly property bool isHome: backend.page === 0
    readonly property bool isCardsPage: (backend.page === 3 || backend.page === 4 || backend.page === 5) || (backend.page === 6 && !backend.isArtistView && backend.tracks.count === 0)
    readonly property bool isTrackListPage: backend.page === 7 || backend.page === 1 || backend.page === 2 || (backend.page === 6 && (backend.isArtistView || backend.tracks.count > 0))

    // Root layout
    Item {
        anchors.fill: parent

        // Left Sidebar
        Sidebar {
            id: sidebar
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 210
            onSettingsRequested: settingsDialog.open()
        }

        // Center Elevated Sheet
        Rectangle {
            id: sheet
            anchors.left: sidebar.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 10
            radius: Appearance.rounding.large
            color: Appearance.colors.surfaceContainer
            clip: true
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.04)

            // Swiftify Back Button on subviews (Albums / Artists detail)
            Rectangle {
                id: backButtonBox
                visible: backend.canGoBack
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 14
                width: 38
                height: 38
                radius: 19
                color: backMouse.containsMouse ? Appearance.colors.surfaceContainerHighest : Appearance.colors.surfaceContainerHigh
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)
                z: 25

                scale: backMouse.pressed ? 0.94 : (backMouse.containsMouse ? 1.05 : 1.0)
                Behavior on scale { Bounce {} }
                Behavior on color { ElementMoveFastColor {} }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: 20
                    color: Appearance.colors.onSurface
                }

                MouseArea {
                    id: backMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: backend.goBack()
                }
            }

            // Status message toast / banner
            Rectangle {
                id: statusBanner
                visible: opacity > 0
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: 12
                height: Math.max(48, statusRow.implicitHeight + 20)
                width: Math.min(parent.width - 112, Math.max(280, statusText.implicitWidth + 76))
                radius: Appearance.rounding.normal
                color: Appearance.colors.primaryContainer
                border.width: 0
                z: 30

                Timer {
                    interval: 8000
                    running: backend.statusMessage.length > 0
                    onTriggered: backend.clearStatus()
                }

                Behavior on opacity {
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
                opacity: backend.statusMessage.length > 0 ? 1 : 0

                RowLayout {
                    id: statusRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 16
                    anchors.rightMargin: 10
                    spacing: 12

                    Text {
                        id: statusText
                        Layout.fillWidth: true
                        text: backend.statusMessage
                        textFormat: Text.PlainText
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.onPrimaryContainer
                        font.pixelSize: Appearance.fontSize.smaller
                        font.weight: Font.Medium
                    }

                    IconButton {
                        symbol: "close"
                        size: 24
                        iconSize: 14
                        iconColor: Appearance.colors.onPrimaryContainer
                        onClicked: backend.clearStatus()
                    }
                }
            }

            StyledText {
                anchors.centerIn: parent
                visible: !backend.authReady && backend.page !== 7
                text: "Восстанавление сессии..."
                color: Appearance.colors.onSurfaceVariant
            }

            // View 1: Not Logged In
            Loader {
                id: loginView
                anchors.fill: parent
                active: backend.authReady && !backend.loggedIn && backend.page !== 7
                sourceComponent: LoginView {}
            }

            // View 2: Home Page (Swiftify-style spotlight, shortcuts, and recommendations)
            Loader {
                id: homeView
                anchors.fill: parent
                active: backend.loggedIn && window.isHome
                sourceComponent: HomeView {}
            }

            // View 3: Cards Grid View (Плейлисты, Альбомы, Артисты)
            Item {
                id: cardsView
                anchors.fill: parent
                visible: backend.loggedIn && window.isCardsPage

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 14

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: backend.page === 0 ? "Главная"
                                : (backend.page === 3 ? "Плейлисты"
                                : (backend.page === 4 ? "Альбомы"
                                : (backend.page === 5 ? "Любимые артисты"
                                : (backend.listTitle.length > 0 ? backend.listTitle : "Обзор"))))
                            color: Appearance.colors.onSurface
                            font.pixelSize: 28
                            font.weight: Font.Bold
                        }

                        StyledButton {
                            visible: backend.page === 3
                            text: "+ Создать плейлист"
                            palette.button: Appearance.colors.primaryContainer
                            palette.buttonText: Appearance.colors.onPrimaryContainer
                            onClicked: createPlaylist.open()
                        }

                        Text {
                            visible: backend.listSubtitle.length > 0
                            text: backend.listSubtitle
                            color: Appearance.colors.onSurfaceVariant
                            font.pixelSize: Appearance.fontSize.small
                        }
                    }

                    GridView {
                        id: cardsGrid
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        cellWidth: 194
                        cellHeight: 254
                        reuseItems: true
                        displayMarginBeginning: 200
                        displayMarginEnd: 200
                        model: cardsView.visible ? backend.cards : null

                        delegate: CardItem {
                            width: 178
                            height: 238
                        }

                        footer: Item {
                            width: cardsGrid.width
                            height: 110
                        }

                        ScrollBar.vertical: ScrollBar { active: true }
                    }
                }

                // Loading indicator for cards
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 12
                    visible: backend.cards.count === 0 && backend.listLoading

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "progress_activity"
                        iconSize: 42
                        color: Appearance.colors.primary
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Загрузка контента..."
                        color: Appearance.colors.onSurfaceVariant
                        font.pixelSize: Appearance.fontSize.normal
                    }
                }

                EmptyState {
                    anchors.centerIn: parent
                    visible: backend.cards.count === 0 && !backend.listLoading
                    symbol: "library_music"
                    title: "Здесь пока пусто"
                    description: "В этом разделе пока нет подборок"
                }
            }

            // View 4: Logged In - Track List / Collection View (Wave, Likes, Album/Artist tracks)
            Item {
                id: trackListView
                anchors.fill: parent
                visible: (backend.loggedIn || backend.page === 7) && window.isTrackListPage

                ListView {
                    id: listView
                    anchors.fill: parent
                    anchors.topMargin: 8
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    clip: true
                    reuseItems: true
                    displayMarginBeginning: 200
                    displayMarginEnd: 200
                    model: trackListView.visible ? backend.tracks : null

                    header: Loader {
                        width: listView.width
                        height: implicitHeight
                        sourceComponent: backend.page === 1 ? waveHeader : collectionHeader
                        Component { id: waveHeader; WaveHero {} }
                        Component { id: collectionHeader; CollectionHero {} }
                    }

                    delegate: TrackRow {
                        width: listView.width
                    }

                    footer: ColumnLayout {
                        width: listView.width
                        spacing: 16

                        // Artist releases section if on artist page
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            visible: backend.isArtistView && backend.cards.count > 0

                            Text {
                                text: "Альбомы и релизы"
                                color: Appearance.colors.onSurface
                                font.pixelSize: 22
                                font.weight: Font.Bold
                                leftPadding: 8
                                topPadding: 16
                            }

                            ListView {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 250
                                orientation: ListView.Horizontal
                                spacing: 16
                                clip: true
                                reuseItems: true
                                model: trackListView.visible && backend.isArtistView ? backend.cards : null
                                delegate: CardItem {
                                    width: 174
                                    height: 234
                                }
                            }
                        }

                        Item {
                            Layout.preferredHeight: 110 // Space for floating player bar
                        }
                    }

                    ScrollBar.vertical: ScrollBar { active: true }
                }

                // Loading indicator if no tracks yet and loading
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 16
                    visible: backend.tracks.count === 0 && backend.listLoading

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: backend.page === 1 ? "my_wave" : "progress_activity"
                        iconSize: 52
                        color: Appearance.colors.primary
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: backend.page === 1 ? "Настраиваем Мою волну..." : "Загрузка треков..."
                        color: Appearance.colors.onSurface
                        font.pixelSize: Appearance.fontSize.large
                        font.weight: Font.DemiBold
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: backend.page === 1 ? "Подбираем треки под ваше настроение" : "Секундочку..."
                        color: Appearance.colors.onSurfaceVariant
                        font.pixelSize: Appearance.fontSize.small
                    }
                }

                EmptyState {
                    anchors.centerIn: parent
                    visible: backend.tracks.count === 0 && !backend.listLoading
                    symbol: backend.page === 2 ? "favorite" : (backend.page === 6 ? "search_off" : "music_note")
                    title: backend.page === 7 ? "Пока ничего не загружено" : (backend.page === 2 ? "Пока нет любимых треков" : (backend.page === 6 ? "Ничего не найдено" : "Нет треков"))
                    description: backend.page === 7 ? "Откройте меню трека → Сохранить офлайн в приложении" : (backend.page === 2 ? "Отмечайте треки сердцем, чтобы найти их здесь" : (backend.page === 6 ? "Попробуйте изменить запрос" : "Треки появятся здесь, когда будут доступны"))
                }
            }
        }

        // Floating Player Bar
        FloatingPlayerBar {
            id: playerBar
            anchors.horizontalCenter: sheet.horizontalCenter
            anchors.bottom: sheet.bottom
            anchors.bottomMargin: 16
            width: Math.min(840, sheet.width - 40)
            visible: backend.loggedIn || backend.page === 7 || backend.hasTrack
            onImmersiveRequested: window.immersiveOpen = true
        }

        Rectangle {
            anchors.horizontalCenter: sheet.horizontalCenter
            anchors.bottom: playerBar.top
            anchors.bottomMargin: 12
            width: Math.min(540, sheet.width - 40)
            height: 70
            visible: backend.batch.running === true
            color: Appearance.colors.surfaceContainerHigh
            radius: 16
            z: 50
            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                ColumnLayout {
                    Layout.fillWidth: true
                    StyledText { Layout.fillWidth: true; text: backend.batch.title || "Загрузка"; elide: Text.ElideRight }
                    StyledText { text: (backend.batch.done || 0) + " / " + (backend.batch.total || 0) + " · ошибок: " + (backend.batch.failed || 0); font.pixelSize: 12 }
                }
                StyledButton { text: "Отменить"; onClicked: backend.feature({action: "cancel_download"}) }
            }
        }

        // Fullscreen Immersive Player Overlay
        Loader {
            id: immersiveOverlay
            anchors.fill: parent
            z: 100
            active: window.immersiveOpen
            sourceComponent: ImmersivePlayer {
                onCloseRequested: window.immersiveOpen = false
            }
        }
    }
}
