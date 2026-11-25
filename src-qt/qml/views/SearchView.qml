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
    readonly property var filterValues: ["all", "track", "album", "artist", "playlist"]
    readonly property bool hasQuery: backend.searchQuery.trim().length > 0
    readonly property bool hasBest: !backend.listLoading && hasQuery && Boolean(backend.searchBest && backend.searchBest.title)

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
            text: root.hasQuery ? ("Поиск: " + backend.searchQuery) : "Поиск музыки"
            elide: Text.ElideRight
            font.pixelSize: Appearance.fontSize.huge
            font.weight: Font.Bold
        }

        SegmentedControl {
            id: filters
            currentIndex: Math.max(0, root.filterValues.indexOf(backend.searchFilter))
            segments: [
                Segment { text: "Всё" },
                Segment { text: "Треки" },
                Segment { text: "Альбомы" },
                Segment { text: "Артисты" },
                Segment { text: "Плейлисты" }
            ]
            onActivated: (index) => {
                backend.feature({action: "search", query: backend.searchQuery, filter: root.filterValues[index]});
            }
        }

        ModSlotHost {
            layoutMode: "column"
            width: parent.width
            visible: implicitHeight > 0
            slotName: "search.top"
            slotContext: ({
                query: backend.searchQuery,
                filter: backend.searchFilter,
                loading: backend.listLoading
            })
        }

        // Недавние поисковые запросы, когда строка поиска пуста
        Column {
            width: parent.width
            spacing: 10
            visible: !root.hasQuery && backend.searchHistory.length > 0 && !backend.listLoading

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
                    onClicked: backend.feature({action: "clear_search_history"})
                }
            }

            Flow {
                width: parent.width
                spacing: 8

                Repeater {
                    model: backend.searchHistory
                    delegate: TextButton {
                        required property string modelData
                        variant: TextButton.Tonal
                        text: modelData
                        symbol: "history"
                        onClicked: backend.search(modelData)
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: 220
            visible: backend.listLoading

            Column {
                anchors.centerIn: parent
                spacing: 12
                LoadingSpinner {
                    anchors.horizontalCenter: parent.horizontalCenter
                    running: backend.listLoading
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
                        circular: Boolean(backend.searchBest?.circular ?? false)
                        radius: (backend.searchBest?.circular ?? false) ? 36 : Appearance.rounding.normal
                        source: (backend.searchBest?.has_cover ?? false) ? (backend.searchBest?.cover_url ?? "") : ""
                        placeholderSymbol: (backend.searchBest?.kind ?? "") === "track" ? "music_note"
                            : ((backend.searchBest?.kind ?? "") === "artist" ? "artists" : "album")
                        fallbackKey: backend.searchBest?.title ?? ""
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        StyledText {
                            text: {
                                const k = backend.searchBest?.kind ?? "";
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
                            text: backend.searchBest?.title ?? ""
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.fontSize.larger
                            font.weight: Font.Bold
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: (backend.searchBest?.subtitle ?? "").length > 0
                            text: backend.searchBest?.subtitle ?? ""
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.fontSize.smaller
                            color: Appearance.colors.onSurfaceVariant
                        }
                    }

                    TextButton {
                        variant: TextButton.Filled
                        symbol: (backend.searchBest?.kind ?? "") === "track" ? "play_arrow" : "arrow_forward"
                        text: (backend.searchBest?.kind ?? "") === "track" ? "Слушать" : "Открыть"
                        onClicked: backend.feature({action: "open_search_best", source: "search"})
                    }
                }

                HoverHandler { id: bestHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: backend.feature({action: "open_search_best", source: "search"})
                }
            }
        }

        // Треки с обложками
        Column {
            width: parent.width
            spacing: 8
            visible: !backend.listLoading && tracks.count > 0

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
                model: root.visible ? backend.tracks : null

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
            visible: !backend.listLoading && cards.count > 0

            StyledText {
                text: {
                    if (backend.searchFilter === "album") return "Альбомы";
                    if (backend.searchFilter === "artist") return "Исполнители";
                    if (backend.searchFilter === "playlist") return "Плейлисты";
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
                model: root.visible ? backend.cards : null

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
            visible: !backend.listLoading && root.hasQuery && backend.searchHasMore

            TextButton {
                anchors.centerIn: parent
                variant: TextButton.Tonal
                symbol: backend.searchLoadingMore ? "hourglass_top" : "expand_more"
                text: backend.searchLoadingMore ? "Загружаем…" : "Показать ещё"
                enabled: !backend.searchLoadingMore
                onClicked: backend.feature({action: "search_more"})
            }
        }

        EmptyState {
            width: parent.width
            height: 260
            Reveal.shown: !backend.listLoading && cards.count === 0 && tracks.count === 0 && !root.hasBest
            title: root.hasQuery ? "Ничего не найдено" : "Начните поиск"
            description: root.hasQuery
                ? "Измените запрос или выберите другой фильтр."
                : "Введите название трека, альбома или имя исполнителя в строке сверху."
            symbol: root.hasQuery ? "search_off" : "search"
        }
    }
}
