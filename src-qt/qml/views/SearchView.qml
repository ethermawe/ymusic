import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ymusic.ui

ColumnLayout {
    id: root
    spacing: 14
    TitleText { Layout.fillWidth: true; text: "Поиск: " + backend.searchQuery; elide: Text.ElideRight }
    RowLayout {
        Layout.fillWidth: true
        Repeater {
            model: [{label: "Всё", value: "all"}, {label: "Треки", value: "track"},
                    {label: "Альбомы", value: "album"}, {label: "Артисты", value: "artist"}, {label: "Плейлисты", value: "playlist"}]
            delegate: StyledButton {
                required property var modelData
                text: modelData.label
                highlighted: backend.searchFilter === modelData.value
                palette.button: Appearance.colors.surfaceContainerHigh
                palette.buttonText: Appearance.colors.onSurface
                palette.highlight: Appearance.colors.primaryContainer
                palette.highlightedText: Appearance.colors.onPrimaryContainer
                onClicked: backend.feature({action: "search", query: backend.searchQuery, filter: modelData.value})
            }
        }
    }
    StyledText { visible: backend.listLoading; text: "Ищем…" }
    ScrollView {
        id: scroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentWidth: availableWidth
        clip: true
        ColumnLayout {
            width: scroll.availableWidth
            spacing: 16
            GridView {
                id: cards
                Layout.fillWidth: true
                Layout.preferredHeight: Math.ceil(count / Math.max(1, Math.floor(width / cellWidth))) * cellHeight
                visible: count > 0
                cellWidth: 194; cellHeight: 254
                interactive: false
                model: root.visible ? backend.cards : null
                delegate: CardItem { width: 178; height: 238 }
            }
            ListView {
                id: tracks
                Layout.fillWidth: true
                Layout.preferredHeight: contentHeight
                interactive: false
                model: root.visible ? backend.tracks : null
                delegate: TrackRow { width: tracks.width }
            }
            EmptyState {
                Layout.fillWidth: true
                visible: !backend.listLoading && backend.cards.count === 0 && backend.tracks.count === 0
                title: "Ничего не найдено"
                description: "Измените запрос или выберите другой фильтр."
                symbol: "search"
            }
            Item { Layout.preferredHeight: 110 }
        }
    }
}
