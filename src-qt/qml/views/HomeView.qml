pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ymusic.ui

Flickable {
    id: root

    topMargin: Appearance.sizes.topBarHeight
    contentWidth: width
    contentHeight: column.implicitHeight + 28 + Appearance.sizes.playerBarClearance
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    ScrollBar.vertical: StyledScrollBar { topPadding: 3 + Appearance.sizes.topBarHeight }
    FastWheel { target: root }

    readonly property real margin: Appearance.sizes.pageMargin
    readonly property real innerWidth: Math.max(0, width - 2 * margin)
    readonly property bool narrow: innerWidth < 680

    Stickers {
        width: root.width
        height: 240
        key: "home-view"
        count: 5
        minimumSize: 80
        maximumSize: 220
    }

    Column {
        id: column
        x: root.margin
        y: 16
        width: root.innerWidth
        spacing: 26

        TitleText {
            width: parent.width
            text: "Главная"
            font.pixelSize: Appearance.fontSize.huge + 4
            font.weight: Font.Bold
        }

        // Now Playing Spotlight Hero
        Rectangle {
            id: spotlightCard
            width: parent.width
            implicitHeight: spotlightInner.implicitHeight + (root.narrow ? 32 : 40)
            radius: Appearance.rounding.veryLarge
            color: Appearance.colors.surfaceContainerLow
            border.width: 1
            border.color: Appearance.colors.outlineVariant
            clip: true

            Image {
                id: spotlightSource
                visible: false
                source: appSettings.coversEnabled && backend.hasCover ? backend.nowCover : ""
                sourceSize: Qt.size(64, 64)
                smooth: true
                asynchronous: true
            }

            ShaderEffect {
                anchors.fill: parent
                property variant source: spotlightSource
                property size itemSize: Qt.size(width, height)
                property real radius: spotlightCard.radius
                fragmentShader: "qrc:/shaders/artwork_backdrop.frag.qsb"
                visible: spotlightSource.status === Image.Ready
                opacity: 0.16
            }

            GridLayout {
                id: spotlightInner
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: root.narrow ? 16 : 20
                columns: root.narrow ? 1 : 2
                columnSpacing: 22
                rowSpacing: 16

                Item {
                    Layout.preferredWidth: root.narrow ? 124 : 152
                    Layout.preferredHeight: Layout.preferredWidth
                    Layout.alignment: root.narrow ? Qt.AlignLeft : Qt.AlignVCenter

                    ArtworkGlow {
                        anchors.fill: parent
                        source: backend.hasCover ? backend.nowCover : ""
                        intensity: 0.24
                        glowRadius: 24
                    }

                    ArtworkImage {
                        anchors.fill: parent
                        radius: Appearance.rounding.large
                        source: backend.hasCover ? backend.nowCover : ""
                        placeholderSymbol: "music_note"
                        fallbackKey: backend.nowTitle
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 10

                    Rectangle {
                        Layout.preferredWidth: statusRow.implicitWidth + 18
                        Layout.preferredHeight: 24
                        radius: 12
                        color: Appearance.colors.primaryContainer

                        Row {
                            id: statusRow
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: backend.playing ? "graphic_eq" : "music_note"
                                iconSize: 14
                                fill: 1
                                color: Appearance.colors.onPrimaryContainer
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: backend.playing ? "СЕЙЧАС ИГРАЕТ" : (backend.hasTrack ? "НА ПАУЗЕ" : "ВАШ ВКУС")
                                font.pixelSize: Appearance.fontSize.smallest
                                font.weight: Font.Bold
                                font.letterSpacing: 0.7
                                color: Appearance.colors.onPrimaryContainer
                            }
                        }
                    }

                    TitleText {
                        Layout.fillWidth: true
                        text: backend.hasTrack ? backend.nowTitle : "Готовы слушать"
                        font.pixelSize: root.narrow ? 20 : 25
                        maximumLineCount: 2
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        font.underline: titleHover.hovered && backend.hasTrack && backend.nowHasAlbum
                        HoverHandler {
                            id: titleHover
                            cursorShape: backend.hasTrack && backend.nowHasAlbum ? Qt.PointingHandCursor : Qt.ArrowCursor
                        }
                        TapHandler {
                            enabled: backend.hasTrack && backend.nowHasAlbum
                            onTapped: backend.openNowAlbum()
                        }
                    }

                    ArtistLinks {
                        Layout.fillWidth: true
                        links: backend.hasTrack ? backend.nowArtistLinks : []
                        fallbackText: backend.hasTrack ? backend.nowArtists : "Включите Мою волну или любой плейлист"
                        clickable: backend.hasTrack
                        fallbackClickable: backend.nowHasArtist
                        font.pixelSize: Appearance.fontSize.normal
                        color: Appearance.colors.onSurfaceVariant
                        wrapMode: Text.WordWrap
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 10

                        PlayButton {
                            size: 46
                            iconSize: 24
                            playing: backend.playing
                            tooltip: backend.hasTrack ? (backend.playing ? "Пауза" : "Играть") : "Запустить Мою волну"
                            onClicked: {
                                if (backend.hasTrack) backend.toggle();
                                else backend.startWave();
                            }
                        }

                        IconButton {
                            visible: backend.hasTrack
                            symbol: backend.nowLiked ? "favorite" : "favorite_border"
                            toggled: backend.nowLiked
                            burst: "hearts"
                            size: 40
                            iconSize: 22
                            tooltip: backend.nowLiked ? "Убрать из Мне нравится" : "Мне нравится"
                            onClicked: backend.toggleNowLike()
                        }

                        TransportButton {
                            visible: backend.hasTrack
                            symbol: "skip_next"
                            size: 40
                            iconSize: 24
                            effect: TransportButton.NudgeRight
                            hoverShape: "pill"
                            tooltip: "Следующий трек"
                            onClicked: backend.next()
                        }

                        Item { Layout.fillWidth: true }

                        TextButton {
                            visible: backend.hasTrack
                            variant: TextButton.Tonal
                            symbol: "open_in_full"
                            text: "На весь экран"
                            iconOnly: root.innerWidth < 460
                            onClicked: UiState.openImmersive()
                        }
                    }
                }
            }
        }

        // Quick Shortcuts
        GridLayout {
            width: parent.width
            columns: root.narrow ? 1 : 2
            columnSpacing: 14
            rowSpacing: 12

            HomeShortcut {
                Layout.fillWidth: true
                title: "Моя волна"
                subtitle: "Бесконечный поток по вашему вкусу"
                symbol: "my_wave"
                iconShape: "cookie9"
                onClicked: backend.startWave()
            }

            HomeShortcut {
                Layout.fillWidth: true
                title: "Мне нравится"
                subtitle: "Все любимые треки в одном месте"
                symbol: "favorite"
                iconShape: "heart"
                keepsShape: true
                onClicked: backend.loadLikes()
            }
        }

        // Recently Played Shelf
        Column {
            width: parent.width
            visible: backend.history.count > 0
            spacing: 12

            SectionHeader {
                width: parent.width
                title: "Недавно прослушано"
                symbol: "history"
                iconShape: "clover4"
                showsSeeAll: backend.history.count > 0
                seeAllText: "Очистить"
                seeAllSymbol: "delete_sweep"
                onSeeAll: clearHistory.open()
            }

            ListView {
                width: parent.width
                height: 92
                orientation: ListView.Horizontal
                spacing: 12
                clip: true
                model: backend.history

                delegate: Rectangle {
                    id: historyTile
                    required property var model
                    width: 246
                    height: 88
                    radius: Appearance.rounding.normal
                    color: tileHover.hovered ? Appearance.colors.surfaceContainerHigh : Appearance.colors.surfaceContainerLow
                    border.width: 1
                    border.color: Appearance.colors.outlineVariant

                    Behavior on color { ElementMoveFastColor {} }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 12

                        ArtworkImage {
                            Layout.preferredWidth: 64
                            Layout.preferredHeight: 64
                            radius: Appearance.rounding.small
                            source: historyTile.model.coverUrl
                            placeholderSymbol: "music_note"
                            fallbackKey: historyTile.model.title
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText {
                                Layout.fillWidth: true
                                text: historyTile.model.title
                                elide: Text.ElideRight
                                font.weight: Font.DemiBold
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: historyTile.model.artists
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.fontSize.smaller
                                color: Appearance.colors.onSurfaceVariant
                            }
                        }
                    }

                    HoverHandler {
                        id: tileHover
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: backend.feature({action: "play_history", id: historyTile.model.id})
                    }
                }
            }
        }

        // Collection Cards Grid
        Column {
            width: parent.width
            spacing: 14

            SectionHeader {
                width: parent.width
                title: "Ваши плейлисты и альбомы"
                symbol: "auto_awesome"
                iconShape: "sunny"
                showsSeeAll: backend.cards.count > 0
                onSeeAll: backend.loadPlaylists()
            }

            GridView {
                id: homeCardsGrid
                width: parent.width
                height: Math.ceil(Math.max(1, count) / Math.max(1, Math.floor(width / cellWidth))) * cellHeight
                clip: true
                interactive: false
                cellWidth: 194
                cellHeight: 254
                reuseItems: true
                model: backend.cards
                visible: count > 0

                delegate: CardItem {
                    width: 178
                    height: 238
                }
            }

            EmptyState {
                width: parent.width
                height: 180
                visible: backend.cards.count === 0
                symbol: "auto_awesome"
                title: "Подборки появятся здесь"
                description: "Музыка, плейлисты и альбомы из вашей библиотеки"
            }
        }
    }

    StyledDialog {
        id: clearHistory
        headline: "Очистить историю?"
        symbol: "delete_sweep"
        iconShape: "clover4"
        body: "Список недавно прослушанных треков на главной странице будет очищен."
        buttons: [
            TextButton {
                text: "Отмена"
                variant: TextButton.Text
                onClicked: clearHistory.close()
            },
            TextButton {
                text: "Очистить"
                variant: TextButton.Filled
                onClicked: {
                    backend.feature({action: "clear_history"});
                    clearHistory.accept();
                }
            }
        ]
    }
}
