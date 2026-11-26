pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ymusic.ui

Flickable {
    id: root

    topMargin: width < 560 ? Appearance.sizes.topBarHeight : 0
    contentWidth: width
    contentHeight: column.y + column.implicitHeight + 28 + Appearance.sizes.playerBarClearance
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    ScrollBar.vertical: StyledScrollBar { topPadding: 3 + Appearance.sizes.topBarHeight }
    FastWheel { target: root }

    readonly property real margin: Appearance.sizes.pageMargin
    readonly property real innerWidth: Math.max(0, width - 2 * margin)
    readonly property bool narrow: innerWidth < 680

    readonly property var personalCards: Backend.cards.revision >= 0 ? Backend.cards.cardsForSection("personal") : []
    readonly property var newReleaseCards: Backend.cards.revision >= 0 ? Backend.cards.cardsForSection("new_releases") : []
    readonly property var newPlaylistCards: Backend.cards.revision >= 0 ? Backend.cards.cardsForSection("new_playlists") : []
    readonly property var userPlaylistCards: Backend.cards.revision >= 0 ? Backend.cards.cardsForSection("user_playlists") : []
    readonly property var userAlbumCards: Backend.cards.revision >= 0 ? Backend.cards.cardsForSection("user_albums") : []
    readonly property var uncategorizedCards: Backend.cards.revision >= 0 ? Backend.cards.cardsForSection("") : []

    component HomeSectionBlock: Column {
        id: secBlock
        property string title: ""
        property string symbol: "auto_awesome"
        property string iconShape: "sunny"
        property var items: []
        property bool showsSeeAll: false
        signal seeAllClicked()

        width: parent ? parent.width : 0
        spacing: 14
        visible: items.length > 0

        SectionHeader {
            width: parent.width
            title: secBlock.title
            symbol: secBlock.symbol
            iconShape: secBlock.iconShape
            showsSeeAll: secBlock.showsSeeAll
            onSeeAll: secBlock.seeAllClicked()
        }

        GridView {
            id: secGrid
            width: parent.width
            property real maxCardHeight: 205
            function updateMaxCardHeight() {
                let m = 0;
                const kids = contentItem ? contentItem.children : [];
                for (let i = 0; i < kids.length; ++i) {
                    const c = kids[i];
                    if (c && c.visible && c.implicitHeight > 0) {
                        m = Math.max(m, c.implicitHeight);
                    }
                }
                if (m > 0 && Math.abs(m - maxCardHeight) > 0.5) {
                    maxCardHeight = m;
                }
            }
            height: count > 0
                ? Math.max(0, Math.ceil(count / Math.max(1, Math.floor(width / cellWidth))) * cellHeight - 12)
                : 0
            clip: false
            interactive: false
            cellWidth: 194
            cellHeight: Math.ceil(maxCardHeight) + 12
            reuseItems: true
            model: secBlock.items
            onCountChanged: Qt.callLater(updateMaxCardHeight)
            onModelChanged: Qt.callLater(updateMaxCardHeight)

            displaced: Transition {
                enabled: !Appearance.performanceMode
                NumberAnimation {
                    properties: "x,y"
                    duration: Appearance.motion(320)
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.curves.expressiveDefaultSpatial
                }
            }

            delegate: CardItem {
                required property var modelData
                cardIndex: modelData.cardIndex
                cardData: modelData
                width: 178
                onImplicitHeightChanged: Qt.callLater(secGrid.updateMaxCardHeight)
                Component.onCompleted: Qt.callLater(secGrid.updateMaxCardHeight)
            }
        }
    }

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

        ModSlotHost {
            layoutMode: "column"
            width: parent.width
            visible: implicitHeight > 0
            slotName: "home.top"
            slotContext: ({ narrow: root.narrow })
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
                source: AppSettings.coversEnabled && Backend.hasCover ? Backend.nowCover : ""
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
                    id: spotlightArtBox
                    Layout.preferredWidth: root.narrow ? 124 : 152
                    Layout.preferredHeight: Layout.preferredWidth
                    Layout.alignment: root.narrow ? Qt.AlignLeft : Qt.AlignVCenter
                    scale: spotlightArtHover.hovered && Backend.hasTrack ? 1.04 : 1

                    Behavior on scale {
                        enabled: !Appearance.performanceMode
                        Bounce {}
                    }

                    transform: Scale {
                        id: spotlightPop
                        origin.x: spotlightArtBox.width / 2
                        origin.y: spotlightArtBox.height / 2
                    }

                    Connections {
                        target: Backend
                        function onTrackInstanceIdChanged() {
                            if (!Appearance.performanceMode && !Appearance.reduceMotion) {
                                spotlightPopIn.restart()
                            }
                        }
                    }

                    NumberAnimation {
                        id: spotlightPopIn
                        target: spotlightPop
                        properties: "xScale,yScale"
                        from: 0.84
                        to: 1
                        duration: Appearance.motion(520)
                        easing.type: Easing.OutBack
                        easing.overshoot: 2.0
                    }

                    ArtworkGlow {
                        anchors.fill: parent
                        source: Backend.hasCover ? Backend.nowCover : ""
                        intensity: 0.24
                        glowRadius: 24
                    }

                    ArtworkImage {
                        anchors.fill: parent
                        radius: Appearance.rounding.large
                        source: Backend.hasCover ? Backend.nowCover : ""
                        crossfade: true
                        placeholderSymbol: "music_note"
                        fallbackKey: Backend.nowTitle
                    }

                    HoverHandler {
                        id: spotlightArtHover
                        cursorShape: Backend.hasTrack ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                    TapHandler {
                        enabled: Backend.hasTrack
                        onTapped: UiState.openImmersive()
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

                        Behavior on Layout.preferredWidth {
                            enabled: !Appearance.performanceMode
                            ElementMoveSmall {}
                        }

                        Row {
                            id: statusRow
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Backend.playing ? "graphic_eq" : "music_note"
                                iconSize: 14
                                fill: 1
                                color: Appearance.colors.onPrimaryContainer
                                scale: Backend.playing && !Appearance.reduceMotion && !Appearance.performanceMode
                                    ? 1 + 0.1 * Math.sin(UiState.spin * 6) : 1
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Backend.playing ? "СЕЙЧАС ИГРАЕТ" : (Backend.hasTrack ? "НА ПАУЗЕ" : "ВАШ ВКУС")
                                font.pixelSize: Appearance.fontSize.smallest
                                font.weight: Font.Bold
                                font.letterSpacing: 0.7
                                color: Appearance.colors.onPrimaryContainer
                            }
                        }
                    }

                    TitleText {
                        Layout.fillWidth: true
                        text: Backend.hasTrack ? Backend.nowTitle : "Готовы слушать"
                        animateChange: true
                        changeDistanceY: 6
                        font.pixelSize: root.narrow ? 20 : 25
                        maximumLineCount: 2
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        font.underline: titleHover.hovered && Backend.hasTrack && Backend.nowHasAlbum
                        HoverHandler {
                            id: titleHover
                            cursorShape: Backend.hasTrack && Backend.nowHasAlbum ? Qt.PointingHandCursor : Qt.ArrowCursor
                        }
                        TapHandler {
                            enabled: Backend.hasTrack && Backend.nowHasAlbum
                            onTapped: Backend.openNowAlbum()
                        }
                    }

                    ArtistLinks {
                        Layout.fillWidth: true
                        links: Backend.hasTrack ? Backend.nowArtistLinks : []
                        fallbackText: Backend.hasTrack ? Backend.nowArtists : "Включите Мою волну или любой плейлист"
                        clickable: Backend.hasTrack
                        fallbackClickable: Backend.nowHasArtist
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
                            playing: Backend.playing
                            tooltip: Backend.hasTrack ? (Backend.playing ? "Пауза" : "Играть") : "Запустить Мою волну"
                            onClicked: {
                                if (Backend.hasTrack) Backend.toggle();
                                else Backend.startWave();
                            }
                        }

                        IconButton {
                            visible: Backend.hasTrack
                            symbol: Backend.nowLiked ? "favorite" : "favorite_border"
                            toggled: Backend.nowLiked
                            burst: "hearts"
                            size: 40
                            iconSize: 22
                            tooltip: Backend.nowLiked ? "Убрать из Мне нравится" : "Мне нравится"
                            onClicked: Backend.toggleNowLike()
                        }

                        TransportButton {
                            visible: Backend.hasTrack
                            symbol: "skip_next"
                            size: 40
                            iconSize: 24
                            effect: TransportButton.NudgeRight
                            hoverShape: "pill"
                            tooltip: "Следующий трек"
                            onClicked: Backend.next()
                        }

                        Item { Layout.fillWidth: true }

                        TextButton {
                            visible: Backend.hasTrack
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
            columns: root.narrow ? 1 : (root.innerWidth < 940 ? 2 : 3)
            columnSpacing: 14
            rowSpacing: 12

            HomeShortcut {
                Layout.fillWidth: true
                title: "Моя волна"
                subtitle: "Бесконечный поток по вашему вкусу"
                symbol: "my_wave"
                iconShape: "cookie9"
                onClicked: Backend.startWave()
            }

            HomeShortcut {
                Layout.fillWidth: true
                title: "Мне нравится"
                subtitle: "Все любимые треки в одном месте"
                symbol: "favorite"
                iconShape: "heart"
                keepsShape: true
                onClicked: Backend.loadLikes()
            }

            HomeShortcut {
                Layout.fillWidth: true
                title: "Чарт"
                subtitle: "Самые популярные треки сейчас"
                symbol: "trending_up"
                iconShape: "sunny"
                onClicked: Backend.feature({action: "open_chart"})
            }
        }

        // Recently Played Shelf
        Column {
            width: parent.width
            visible: Backend.history.count > 0
            spacing: 12

            SectionHeader {
                width: parent.width
                title: "Недавно прослушано"
                symbol: "history"
                iconShape: "clover4"
                showsSeeAll: Backend.history.count > 0
                seeAllText: "Очистить"
                seeAllSymbol: "delete_sweep"
                onSeeAll: clearHistory.open()
            }

            Item {
                width: parent.width
                height: 88

                ListView {
                    anchors.fill: parent
                    anchors.margins: -8
                    leftMargin: 8
                    rightMargin: 8
                    orientation: ListView.Horizontal
                    spacing: 12
                    clip: true
                    model: Backend.history

                delegate: Item {
                    id: historySlot
                    required property var model
                    width: 246
                    height: 104

                    Rectangle {
                        id: historyTile
                        y: 8
                        width: 246
                        height: 88
                        radius: Appearance.rounding.normal
                        color: tileHover.hovered ? Appearance.colors.surfaceContainerHigh : Appearance.colors.surfaceContainerLow
                        border.width: 1
                        border.color: Appearance.colors.outlineVariant
                        scale: tileTap.pressed ? 0.96 : (tileHover.hovered ? 1.02 : 1)

                        Behavior on color { ElementMoveFastColor {} }
                        Behavior on scale {
                            enabled: !Appearance.performanceMode
                            Bounce {}
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 12

                            ArtworkImage {
                                Layout.preferredWidth: 64
                                Layout.preferredHeight: 64
                                radius: Appearance.rounding.small
                                source: historySlot.model.coverUrl
                                placeholderSymbol: "music_note"
                                fallbackKey: historySlot.model.title
                                scale: tileHover.hovered ? 1.06 : 1

                                Behavior on scale {
                                    enabled: !Appearance.performanceMode
                                    Bounce {}
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                StyledText {
                                    Layout.fillWidth: true
                                    text: historySlot.model.title
                                    elide: Text.ElideRight
                                    font.weight: Font.DemiBold
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: historySlot.model.artists
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
                            id: tileTap
                            onTapped: Backend.feature({action: "play_history", id: historySlot.model.id})
                        }
                    }
                }
            }
            }
        }

        // Categorized Sections on Home
        HomeSectionBlock {
            title: "Умные плейлисты для вас"
            symbol: "auto_awesome"
            iconShape: "sunny"
            items: root.personalCards
        }

        HomeSectionBlock {
            title: "Новые релизы"
            symbol: "new_releases"
            iconShape: "cookie9"
            items: root.newReleaseCards
        }

        HomeSectionBlock {
            title: "Новые плейлисты"
            symbol: "library_music"
            iconShape: "bun"
            items: root.newPlaylistCards
        }

        HomeSectionBlock {
            title: "Ваши плейлисты"
            symbol: "queue_music"
            iconShape: "clover4"
            items: root.userPlaylistCards
            showsSeeAll: true
            onSeeAllClicked: Backend.loadPlaylists()
        }

        HomeSectionBlock {
            title: "Понравившиеся альбомы"
            symbol: "album"
            iconShape: "sunny"
            items: root.userAlbumCards
            showsSeeAll: true
            onSeeAllClicked: Backend.loadAlbums()
        }

        HomeSectionBlock {
            title: "Ваша коллекция"
            symbol: "library_music"
            iconShape: "sunny"
            items: root.uncategorizedCards
            showsSeeAll: true
            onSeeAllClicked: Backend.loadPlaylists()
        }

        ModSlotHost {
            layoutMode: "column"
            width: parent.width
            visible: implicitHeight > 0
            slotName: "home.sections"
            slotContext: ({ narrow: root.narrow })
        }

        EmptyState {
            width: parent.width
            height: 180
            visible: Backend.cards.count === 0
            symbol: "auto_awesome"
            title: "Подборки появятся здесь"
            description: "Музыка, плейлисты и альбомы из вашей библиотеки"
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
                    Backend.feature({action: "clear_history"});
                    clearHistory.accept();
                }
            }
        ]
    }
}
