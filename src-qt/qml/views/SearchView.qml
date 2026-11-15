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
            text: backend.searchQuery.trim().length > 0 ? ("Поиск: " + backend.searchQuery) : "Поиск музыки"
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

        GridView {
            id: cards
            width: parent.width
            height: Math.ceil(Math.max(1, count) / Math.max(1, Math.floor(width / cellWidth))) * cellHeight
            visible: !backend.listLoading && count > 0
            cellWidth: 194
            cellHeight: 264
            interactive: false
            reuseItems: true
            model: root.visible ? backend.cards : null
            delegate: CardItem {
                required property int index
                required property var model
                cardIndex: index
                cardData: model
                width: 178
                height: 252
            }
        }

        ListView {
            id: tracks
            width: parent.width
            height: contentHeight
            visible: !backend.listLoading && count > 0
            interactive: false
            model: root.visible ? backend.tracks : null
            delegate: TrackRow { width: tracks.width }
        }

        EmptyState {
            width: parent.width
            height: 260
            visible: !backend.listLoading && backend.cards.count === 0 && backend.tracks.count === 0
            title: "Ничего не найдено"
            description: "Измените запрос или выберите другой фильтр."
            symbol: "search_off"
        }
    }
}
