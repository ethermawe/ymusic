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
    readonly property var filterValues: ["all", "track", "album", "artist", "playlist"]
    readonly property bool hasQuery: Backend.searchQuery.trim().length > 0
    readonly property bool hasBest: !Backend.listLoading && hasQuery && Boolean(Backend.searchBest && Backend.searchBest.title)

    Stickers {
        width: root.width
        height: 220
        key: "search"
        count: 4
    }

    Column {
        id: column
        x: root.margin
        y: 16
        width: Math.max(0, root.width - 2 * root.margin)
        spacing: 18

        TitleText {
            width: parent.width
            text: root.hasQuery ? ("Поиск: " + Backend.searchQuery) : "Поиск музыки"
            elide: Text.ElideRight
            font.pixelSize: Appearance.fontSize.huge
            font.weight: Font.Bold
        }

        SegmentedControl {
            id: filters
            currentIndex: Math.max(0, root.filterValues.indexOf(Backend.searchFilter))
            segments: [
                Segment { text: "Всё" },
                Segment { text: "Треки" },
                Segment { text: "Альбомы" },
                Segment { text: "Артисты" },
                Segment { text: "Плейлисты" }
            ]
            onActivated: (index) => {
                Backend.feature({action: "search", query: Backend.searchQuery, filter: root.filterValues[index]});
            }
        }

        ModSlotHost {
            layoutMode: "column"
            width: parent.width
            visible: implicitHeight > 0
            slotName: "search.top"
            slotContext: ({
                query: Backend.searchQuery,
                filter: Backend.searchFilter,
                loading: Backend.listLoading
            })
        }

        // Недавние поисковые запросы, когда строка поиска пуста
        Column {
            width: parent.width
            spacing: 10
            visible: !root.hasQuery && Backend.searchHistory.length > 0 && !Backend.listLoading

            RowLayout {
                width: parent.width
                StyledText {
                    text: "Недавние запросы"
                    font.pixelSize: Appearance.fontSize.normal
                    font.weight: Font.DemiBold
                }
                Item { Layout.fillWidth: true }
                TextButton {
                    variant: TextButton.Text
                    symbol: "delete_sweep"
                    text: "Очистить"
                    onClicked: Backend.feature({action: "clear_search_history"})
                }
            }

            Flow {
                width: parent.width
                spacing: 8

                Repeater {
                    model: Backend.searchHistory
                    delegate: Rectangle {
                        id: historyChip
                        required property string modelData
                        implicitWidth: chipRow.implicitWidth + 16
                        height: 34
                        radius: Appearance.rounding.full
                        color: chipHover.hovered
                            ? Appearance.colors.secondaryContainerHover
                            : Appearance.colors.secondaryContainer

                        Behavior on color { ElementMoveFastColor {} }

                        HoverHandler { id: chipHover }

                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 6

                            Row {
                                id: chipMain
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                MaterialSymbol {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "history"
                                    iconSize: 16
                                    color: Appearance.colors.onSecondaryContainer
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: historyChip.modelData
                                    font.pixelSize: Appearance.fontSize.small
                                    font.weight: Font.Medium
                                    color: Appearance.colors.onSecondaryContainer
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Backend.search(historyChip.modelData)
                                }
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20
                                height: 20
                                radius: 10
                                color: chipRemoveHover.hovered
                                    ? Qt.alpha(Appearance.colors.onSecondaryContainer, 0.16)
                                    : "transparent"

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "close"
                                    iconSize: 14
                                    color: Appearance.colors.onSecondaryContainer
                                }

                                HoverHandler { id: chipRemoveHover; cursorShape: Qt.PointingHandCursor }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Backend.feature({action: "remove_search_history_item", query: historyChip.modelData})
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: 220
            visible: Backend.listLoading

            Column {
                anchors.centerIn: parent
                spacing: 12
                LoadingSpinner {
                    anchors.horizontalCenter: parent.horizontalCenter
                    running: Backend.listLoading
                }
                StyledText {
                    text: "Ищем…"
                    color: Appearance.colors.onSurfaceVariant
                }
            }
        }

        // Карточка «Лучший результат» с крупной обложкой
        Column {
            width: parent.width
            spacing: 10
            visible: root.hasBest

            StyledText {
                text: "Лучший результат"
                font.pixelSize: Appearance.fontSize.larger
                font.weight: Font.Bold
            }

            Rectangle {
                id: bestCard
                width: Math.min(540, parent.width)
                height: 98
                radius: Appearance.rounding.large
                color: bestHover.hovered ? Appearance.colors.surfaceContainerHigh : Appearance.colors.surfaceContainerLow
                border.width: 1
                border.color: bestHover.hovered ? Appearance.colors.outline : Appearance.colors.outlineVariant

                Behavior on color { ElementMoveFastColor {} }
                Behavior on border.color { ElementMoveFastColor {} }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 13
                    spacing: 14

                    ArtworkImage {
                        Layout.preferredWidth: 72
                        Layout.preferredHeight: 72
                        circular: Boolean(Backend.searchBest?.circular ?? false)
                        radius: (Backend.searchBest?.circular ?? false) ? 36 : Appearance.rounding.normal
                        source: (Backend.searchBest?.has_cover ?? false) ? (Backend.searchBest?.cover_url ?? "") : ""
                        placeholderSymbol: (Backend.searchBest?.kind ?? "") === "track" ? "music_note"
                            : ((Backend.searchBest?.kind ?? "") === "artist" ? "artists" : "album")
                        fallbackKey: Backend.searchBest?.title ?? ""
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        StyledText {
                            text: {
                                const k = Backend.searchBest?.kind ?? "";
                                if (k === "track") return "Лучший трек";
                                if (k === "artist") return "Исполнитель";
                                if (k === "album") return "Альбом";
                                return "Плейлист";
                            }
                            font.pixelSize: Appearance.fontSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.primary
                        }

                        TitleText {
                            Layout.fillWidth: true
                            text: Backend.searchBest?.title ?? ""
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.fontSize.larger
                            font.weight: Font.Bold
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: (Backend.searchBest?.subtitle ?? "").length > 0
                            text: Backend.searchBest?.subtitle ?? ""
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.fontSize.smaller
                            color: Appearance.colors.onSurfaceVariant
                        }
                    }

                    TextButton {
                        variant: TextButton.Filled
                        symbol: (Backend.searchBest?.kind ?? "") === "track" ? "play_arrow" : "arrow_forward"
                        text: (Backend.searchBest?.kind ?? "") === "track" ? "Слушать" : "Открыть"
                        onClicked: Backend.feature({action: "open_search_best", source: "search"})
                    }
                }

                HoverHandler { id: bestHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: Backend.feature({action: "open_search_best", source: "search"})
                }
            }
        }

        // Треки с обложками
        Column {
            width: parent.width
            spacing: 8
            visible: !Backend.listLoading && tracks.count > 0

            StyledText {
                text: "Треки"
                font.pixelSize: Appearance.fontSize.larger
                font.weight: Font.Bold
            }

            ListView {
                id: tracks
                width: parent.width
                height: contentHeight
                interactive: false
                model: root.visible ? Backend.tracks : null

                displaced: Transition {
                    enabled: !Appearance.performanceMode
                    NumberAnimation {
                        properties: "x,y"
                        duration: Appearance.motion(280)
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.curves.expressiveDefaultSpatial
                    }
                }

                delegate: TrackRow { width: tracks.width }
            }
        }

        // Исполнители, альбомы и плейлисты
        Column {
            width: parent.width
            spacing: 10
            visible: !Backend.listLoading && cards.count > 0

            StyledText {
                text: {
                    if (Backend.searchFilter === "album") return "Альбомы";
                    if (Backend.searchFilter === "artist") return "Исполнители";
                    if (Backend.searchFilter === "playlist") return "Плейлисты";
                    return "Исполнители, альбомы и плейлисты";
                }
                font.pixelSize: Appearance.fontSize.larger
                font.weight: Font.Bold
            }

            GridView {
                id: cards
                width: parent.width
                height: Math.ceil(Math.max(1, count) / Math.max(1, Math.floor(width / cellWidth))) * cellHeight
                cellWidth: 194
                cellHeight: 264
                interactive: false
                reuseItems: true
                model: root.visible ? Backend.cards : null

                displaced: Transition {
                    enabled: !Appearance.performanceMode
                    NumberAnimation {
                        properties: "x,y"
                        duration: Appearance.motion(300)
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.curves.expressiveDefaultSpatial
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
        }

        Item {
            width: parent.width
            height: 44
            visible: !Backend.listLoading && root.hasQuery && Backend.searchHasMore

            TextButton {
                anchors.centerIn: parent
                variant: TextButton.Tonal
                symbol: Backend.searchLoadingMore ? "hourglass_top" : "expand_more"
                text: Backend.searchLoadingMore ? "Загружаем…" : "Показать ещё"
                enabled: !Backend.searchLoadingMore
                onClicked: Backend.feature({action: "search_more"})
            }
        }

        EmptyState {
            width: parent.width
            height: 260
            Reveal.shown: !Backend.listLoading && cards.count === 0 && tracks.count === 0 && !root.hasBest
            title: root.hasQuery ? "Ничего не найдено" : "Начните поиск"
            description: root.hasQuery
                ? "Измените запрос или выберите другой фильтр."
                : "Введите название трека, альбома или имя исполнителя в строке сверху."
            symbol: root.hasQuery ? "search_off" : "search"
        }
    }
}
