pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Templates as T
import ymusic.ui

Flickable {
    id: root

    topMargin: width < 560 ? Appearance.sizes.topBarHeight : 0
    contentWidth: width
    contentHeight: column.y + column.implicitHeight + 32 + Appearance.sizes.playerBarClearance
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    ScrollBar.vertical: StyledScrollBar { topPadding: 4 + Appearance.sizes.topBarHeight }
    FastWheel { target: root }

    property real lastContentY: 0
    onVisibleChanged: lastContentY = contentY
    onContentYChanged: {
        const dy = contentY - lastContentY;
        lastContentY = contentY;
        if (visible && contentHeight > height + 40 && Math.abs(dy) < 400) {
            UiState.reportScroll(dy, contentY <= originY + 8);
        }
    }

    readonly property real margin: Appearance.sizes.pageMargin
    readonly property real innerWidth: Math.max(0, width - 2 * margin)
    readonly property bool narrow: innerWidth < 680
    readonly property bool wideHero: innerWidth >= 860

    // M3 Expressive corner tokens scaled by user roundingScale
    readonly property int heroOuterRadius: Math.max(0, Math.round(32 * AppSettings.roundingScale))
    readonly property int cardOuterRadius: Math.max(0, Math.round(20 * AppSettings.roundingScale))

    readonly property var personalCards: Backend.cards.revision >= 0 ? Backend.cards.cardsForSection("personal") : []
    readonly property var newReleaseCards: Backend.cards.revision >= 0 ? Backend.cards.cardsForSection("new_releases") : []
    readonly property var newPlaylistCards: Backend.cards.revision >= 0 ? Backend.cards.cardsForSection("new_playlists") : []
    readonly property var userPlaylistCards: Backend.cards.revision >= 0 ? Backend.cards.cardsForSection("user_playlists") : []
    readonly property var userAlbumCards: Backend.cards.revision >= 0 ? Backend.cards.cardsForSection("user_albums") : []
    readonly property var uncategorizedCards: Backend.cards.revision >= 0 ? Backend.cards.cardsForSection("") : []

    component HomeQuickTile: T.AbstractButton {
        id: quickTile

        property string title: ""
        property string subtitle: ""
        property string symbol: "music_note"
        property string iconShape: "cookie9"
        property bool keepsShape: false
        property color badgeColor: Appearance.colors.secondaryContainer
        property color badgeIconColor: Appearance.colors.onSecondaryContainer

        implicitHeight: 68
        hoverEnabled: true
        focusPolicy: Qt.TabFocus
        scale: down ? 0.985 : 1.0

        Behavior on scale {
            enabled: !Appearance.performanceMode
            NumberAnimation {
                duration: Appearance.duration(120)
                easing.type: Easing.OutCubic
            }
        }

        background: Rectangle {
            radius: root.cardOuterRadius
            color: quickTile.hovered
                ? Appearance.colors.surfaceContainerHighest
                : Appearance.colors.surfaceContainerHigh
            border.width: quickTile.visualFocus ? 2 : 0
            border.color: Appearance.colors.primary

            Behavior on color { ElementMoveFastColor {} }
        }

        contentItem: RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 16
            anchors.topMargin: 12
            anchors.bottomMargin: 12
            spacing: 14

            ShapeIcon {
                Layout.alignment: Qt.AlignVCenter
                size: 44
                iconSize: 22
                shape: quickTile.iconShape
                keepsShape: quickTile.keepsShape
                symbol: quickTile.symbol
                color: quickTile.badgeColor
                iconColor: quickTile.badgeIconColor
                hovered: quickTile.hovered
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: quickTile.title
                    elide: Text.ElideRight
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: Appearance.colors.onSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: quickTile.subtitle
                    elide: Text.ElideRight
                    font.pixelSize: 12
                    color: Appearance.colors.onSurfaceVariant
                }
            }

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: "chevron_right"
                iconSize: 18
                color: Appearance.colors.onSurfaceVariant
                opacity: quickTile.hovered ? 1.0 : 0.6

                Behavior on opacity {
                    enabled: !Appearance.performanceMode
                    NumberAnimation { duration: Appearance.duration(150); easing.type: Easing.OutCubic }
                }
            }
        }

        HoverHandler {
            cursorShape: Qt.PointingHandCursor
        }
    }

    component HomeSectionBlock: Column {
        id: secBlock
        property string title: ""
        property string symbol: "auto_awesome"
        property string iconShape: "sunny"
        property var items: []
        property bool showsSeeAll: false
        signal seeAllClicked()

        width: parent ? parent.width : 0
        spacing: 16
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
            readonly property int gap: 16
            readonly property int minCardWidth: root.narrow ? 148 : 168
            readonly property int columns: Math.max(2, Math.floor((secBlock.width + gap) / (minCardWidth + gap)))
            readonly property real cardWidth: Math.max(120, Math.floor((secBlock.width - (columns - 1) * gap) / columns))

            width: secBlock.width + gap
            property real maxCardHeight: cardWidth + 52
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
                ? Math.max(0, Math.ceil(count / Math.max(1, columns)) * cellHeight - gap)
                : 0
            clip: false
            interactive: false
            cellWidth: cardWidth + gap
            cellHeight: Math.ceil(maxCardHeight) + gap
            reuseItems: true
            model: secBlock.items
            onCountChanged: Qt.callLater(updateMaxCardHeight)
            onModelChanged: Qt.callLater(updateMaxCardHeight)
            onCardWidthChanged: Qt.callLater(updateMaxCardHeight)

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
                width: secGrid.cardWidth
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
        spacing: 32

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

        // Hero Moment: Asymmetric Spotlight + Quick Launch Rail
        GridLayout {
            id: heroGrid
            width: parent.width
            columns: root.wideHero ? 2 : 1
            columnSpacing: 16
            rowSpacing: 16

            // Left: M3 Expressive Now Playing / Wave Hero Player
            Rectangle {
                id: spotlightCard
                readonly property int innerPad: root.narrow ? 16 : 20
                readonly property int artRadius: Math.max(8, root.heroOuterRadius - innerPad)

                Layout.fillWidth: true
                Layout.preferredWidth: root.wideHero ? Math.round((root.innerWidth - 16) * 0.64) : root.innerWidth
                Layout.fillHeight: root.wideHero
                implicitHeight: Math.max(root.wideHero ? 244 : 0, spotlightInner.implicitHeight + innerPad * 2)
                radius: root.heroOuterRadius
                color: Appearance.colors.surfaceContainerHigh
                clip: true

                Image {
                    id: spotlightSource
                    visible: false
                    source: AppSettings.coversEnabled && Backend.hasCover ? Backend.nowCover : ""
                    sourceSize: Qt.size(64, 64)
                    smooth: true
                    asynchronous: true
                }

                // Dynamic ambient artwork tint (M3 Expressive content-based color)
                ShaderEffect {
                    anchors.fill: parent
                    property variant source: spotlightSource
                    property size itemSize: Qt.size(width, height)
                    property real radius: spotlightCard.radius
                    fragmentShader: "qrc:/shaders/artwork_backdrop.frag.qsb"
                    visible: !Appearance.performanceMode && spotlightSource.status === Image.Ready
                    opacity: Appearance.colors.dark ? 0.34 : 0.22
                }

                // Tonal legibility scrim keeping text contrast crisp across any cover art
                Rectangle {
                    anchors.fill: parent
                    radius: spotlightCard.radius
                    visible: !Appearance.performanceMode && spotlightSource.status === Image.Ready
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.alpha(Appearance.colors.surfaceContainerHigh, 0.25) }
                        GradientStop { position: 0.45; color: Qt.alpha(Appearance.colors.surfaceContainerHigh, 0.58) }
                        GradientStop { position: 1.0; color: Qt.alpha(Appearance.colors.surfaceContainerHigh, 0.80) }
                    }
                }

                GridLayout {
                    id: spotlightInner
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: spotlightCard.innerPad
                    anchors.rightMargin: spotlightCard.innerPad
                    columns: root.narrow ? 1 : 2
                    columnSpacing: 24
                    rowSpacing: 16

                    Item {
                        id: spotlightArtBox
                        Layout.preferredWidth: root.narrow ? 128 : 188
                        Layout.preferredHeight: Layout.preferredWidth
                        Layout.alignment: root.narrow ? Qt.AlignLeft : Qt.AlignVCenter
                        scale: spotlightArtTap.pressed && Backend.hasTrack ? 0.97 : 1.0

                        Behavior on scale {
                            enabled: !Appearance.performanceMode
                            NumberAnimation {
                                duration: Appearance.duration(120)
                                easing.type: Easing.OutCubic
                            }
                        }

                        SoftShadow {
                            anchors.fill: parent
                            radius: spotlightCard.artRadius
                            blur: 18
                            offset: Qt.vector2d(0, 6)
                            color: Qt.rgba(0, 0, 0, Appearance.colors.dark ? 0.34 : 0.16)
                        }

                        ArtworkImage {
                            anchors.fill: parent
                            radius: spotlightCard.artRadius
                            source: Backend.hasCover ? Backend.nowCover : ""
                            crossfade: true
                            placeholderSymbol: "music_note"
                            fallbackKey: Backend.nowTitle
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: spotlightCard.artRadius
                            color: Qt.rgba(0, 0, 0, spotlightArtHover.hovered && Backend.hasTrack ? 0.32 : 0)

                            Behavior on color { ElementMoveFastColor {} }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "open_in_full"
                                iconSize: 28
                                fill: 1
                                color: "white"
                                opacity: spotlightArtHover.hovered && Backend.hasTrack ? 1.0 : 0.0

                                Behavior on opacity {
                                    enabled: !Appearance.performanceMode
                                    NumberAnimation { duration: Appearance.duration(150); easing.type: Easing.OutCubic }
                                }
                            }
                        }

                        HoverHandler {
                            id: spotlightArtHover
                            cursorShape: Backend.hasTrack ? Qt.PointingHandCursor : Qt.ArrowCursor
                        }
                        TapHandler {
                            id: spotlightArtTap
                            enabled: Backend.hasTrack
                            onTapped: UiState.openImmersive()
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 8

                        TitleText {
                            Layout.fillWidth: true
                            text: Backend.hasTrack ? Backend.nowTitle : "Готово к прослушиванию"
                            animateChange: true
                            changeDistanceY: 6
                            font.pixelSize: root.narrow ? 22 : 28
                            font.weight: Font.Bold
                            maximumLineCount: 1
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
                            fallbackText: Backend.hasTrack ? Backend.nowArtists : "Запустите Мою волну или выберите подборку ниже"
                            clickable: Backend.hasTrack
                            fallbackClickable: Backend.nowHasArtist
                            font.pixelSize: 15
                            color: Appearance.colors.onSurfaceVariant
                        }

                        // Built-in M3 Expressive Wavy SeekBar + tabular timings
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 6
                            spacing: 2
                            visible: Backend.hasTrack

                            SeekBar {
                                id: spotlightSeek
                                Layout.fillWidth: true
                                Layout.preferredHeight: 22
                                restThickness: 4
                                expandedThickness: 6
                            }

                            RowLayout {
                                Layout.fillWidth: true

                                StyledText {
                                    text: Format.playbackTime(spotlightSeek.displayPositionMs)
                                    tabularNumbers: true
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    color: Appearance.colors.onSurfaceVariant
                                }

                                Item { Layout.fillWidth: true }

                                StyledText {
                                    text: Format.playbackTime(spotlightSeek.durationMs)
                                    tabularNumbers: true
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    color: Appearance.colors.onSurfaceVariant
                                }
                            }
                        }

                        // M3 Expressive Media Control Group (size & tonal hierarchy)
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: Backend.hasTrack ? 4 : 12
                            spacing: 10

                            TransportButton {
                                visible: Backend.hasTrack
                                variant: IconButton.Tonal
                                symbol: "skip_previous"
                                size: 44
                                iconSize: 22
                                alwaysFilled: true
                                effect: TransportButton.NudgeLeft
                                hoverShape: "arrow"
                                hoverAngle: -90
                                tooltip: "Предыдущий трек"
                                onClicked: Backend.prev()
                            }

                            PlayButton {
                                size: 56
                                iconSize: 28
                                playing: Backend.playing
                                color: Appearance.colors.primary
                                hoverColor: Appearance.colors.primaryHover
                                iconColor: Appearance.colors.onPrimary
                                tooltip: Backend.hasTrack ? (Backend.playing ? "Пауза" : "Играть") : "Запустить Мою волну"
                                onClicked: {
                                    if (Backend.hasTrack) Backend.toggle();
                                    else Backend.startWave();
                                }
                            }

                            TransportButton {
                                visible: Backend.hasTrack
                                variant: IconButton.Tonal
                                symbol: "skip_next"
                                size: 44
                                iconSize: 22
                                alwaysFilled: true
                                effect: TransportButton.NudgeRight
                                hoverShape: "arrow"
                                hoverAngle: 90
                                tooltip: "Следующий трек"
                                onClicked: Backend.next()
                            }

                            Item {
                                visible: Backend.hasTrack
                                Layout.preferredWidth: 4
                            }

                            IconButton {
                                visible: Backend.hasTrack
                                variant: IconButton.Tonal
                                symbol: "favorite"
                                toggled: Backend.nowLiked
                                fillWhenToggled: true
                                burst: Backend.nowLiked ? "" : "hearts"
                                size: 44
                                iconSize: 20
                                tooltip: Backend.nowLiked ? "Убрать из Мне нравится" : "Мне нравится"
                                onClicked: Backend.toggleNowLike()
                            }

                            Item { Layout.fillWidth: true }
                        }
                    }
                }
            }

            // Right (or below on narrow screens): Quick Launch Tiles
            GridLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: root.wideHero
                    ? Math.max(260, root.innerWidth - 16 - spotlightCard.Layout.preferredWidth)
                    : root.innerWidth
                Layout.fillHeight: root.wideHero
                columns: root.wideHero ? 1 : (root.narrow ? 1 : 3)
                columnSpacing: 12
                rowSpacing: 12

                HomeQuickTile {
                    Layout.fillWidth: true
                    Layout.fillHeight: root.wideHero
                    title: "Моя волна"
                    subtitle: "Бесконечный поток по вашему вкусу"
                    symbol: "my_wave"
                    iconShape: "cookie9"
                    badgeColor: Appearance.colors.primaryContainer
                    badgeIconColor: Appearance.colors.onPrimaryContainer
                    onClicked: Backend.startWave()
                }

                HomeQuickTile {
                    Layout.fillWidth: true
                    Layout.fillHeight: root.wideHero
                    title: "Мне нравится"
                    subtitle: "Любимые треки в одном месте"
                    symbol: "favorite"
                    iconShape: "heart"
                    keepsShape: true
                    badgeColor: Appearance.colors.tertiaryContainer
                    badgeIconColor: Appearance.colors.onTertiaryContainer
                    onClicked: Backend.loadLikes()
                }

                HomeQuickTile {
                    Layout.fillWidth: true
                    Layout.fillHeight: root.wideHero
                    title: "Чарт"
                    subtitle: "Популярные треки прямо сейчас"
                    symbol: "trending_up"
                    iconShape: "sunny"
                    badgeColor: Appearance.colors.secondaryContainer
                    badgeIconColor: Appearance.colors.onSecondaryContainer
                    onClicked: Backend.feature({action: "open_chart"})
                }
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

            ListView {
                id: historyList
                width: parent.width
                height: 80
                orientation: ListView.Horizontal
                spacing: 12
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: Backend.history

                delegate: Rectangle {
                    id: historyTile
                    required property var model
                    readonly property int innerPad: 8
                    readonly property int artRadius: Math.max(4, root.cardOuterRadius - innerPad)

                    width: 248
                    height: 80
                    radius: root.cardOuterRadius
                    color: tileHover.hovered
                        ? Appearance.colors.surfaceContainerHighest
                        : Appearance.colors.surfaceContainerHigh
                    scale: tileTap.pressed ? 0.98 : 1.0

                    Behavior on color { ElementMoveFastColor {} }
                    Behavior on scale {
                        enabled: !Appearance.performanceMode
                        NumberAnimation { duration: Appearance.duration(120); easing.type: Easing.OutCubic }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: historyTile.innerPad
                        spacing: 12

                        Item {
                            Layout.preferredWidth: 64
                            Layout.preferredHeight: 64

                            ArtworkImage {
                                anchors.fill: parent
                                radius: historyTile.artRadius
                                source: historyTile.model.coverUrl
                                placeholderSymbol: "music_note"
                                fallbackKey: historyTile.model.title
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: historyTile.artRadius
                                color: Qt.rgba(0, 0, 0, 0.42)
                                opacity: tileHover.hovered ? 1.0 : 0.0

                                Behavior on opacity {
                                    enabled: !Appearance.performanceMode
                                    NumberAnimation { duration: Appearance.duration(150); easing.type: Easing.OutCubic }
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "play_arrow"
                                    iconSize: 26
                                    fill: 1
                                    color: "white"
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.rightMargin: 4
                            spacing: 2

                            StyledText {
                                Layout.fillWidth: true
                                text: historyTile.model.title
                                elide: Text.ElideRight
                                font.pixelSize: 14
                                font.weight: Font.Medium
                                color: Appearance.colors.onSurface
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: historyTile.model.artists
                                elide: Text.ElideRight
                                font.pixelSize: 12
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
                        onTapped: Backend.feature({action: "play_history", id: historyTile.model.id})
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
