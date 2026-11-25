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
import QtQuick.Effects
import ymusic.ui

Item {
    id: root

    required property Window window
    property Item backdropSource
    property bool windowControlsOnRight: false
    property bool inspectorShown: false
    readonly property bool compact: width < 560
    readonly property real buttonSize: width < 400 ? 30 : (compact ? 36 : 42)
    readonly property real searchRightEdge: rightControls.x - 10
    readonly property real searchLeftEdge: back.x + (back.visible ? back.width + 10 : 0)
    readonly property real reservedSearchWidth: Math.max(120, Math.min(320, searchRightEdge - searchLeftEdge))

    readonly property bool searchEditing: search.editing

    function focusSearch() {
        search.focusField()
    }

    function dismissSearch() {
        suggestTimer.stop()
        search.clearFocus()
    }

    function isSearchInteractiveAt(sourceItem: Item, x: real, y: real): bool {
        if (!sourceItem) return false
        const inSearch = sourceItem.mapToItem(search, x, y)
        if (inSearch.x >= 0 && inSearch.x <= search.width
            && inSearch.y >= 0 && inSearch.y <= search.height) {
            return true
        }
        if (suggestionsPopup.visible) {
            const inPopup = sourceItem.mapToItem(suggestionsPopup, x, y)
            if (inPopup.x >= 0 && inPopup.x <= suggestionsPopup.width
                && inPopup.y >= 0 && inPopup.y <= suggestionsPopup.height) {
                return true
            }
        }
        return false
    }

    implicitHeight: Appearance.sizes.topBarHeight

    DragHandler {
        target: null
        grabPermissions: PointerHandler.CanTakeOverFromAnything
        onActiveChanged: if (active) root.window.startSystemMove()
    }
    TapHandler {
        acceptedButtons: Qt.LeftButton
        onDoubleTapped: root.window.visibility === Window.Maximized ? root.window.showNormal() : root.window.showMaximized()
    }

    Item {
        id: toolbarButtons
        anchors.fill: parent

        ToolbarButton {
            id: back
            effect: ToolbarButton.NudgeLeft
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            size: root.buttonSize
            iconSize: root.compact ? 20 : 24
            symbol: "arrow_back"
            shape: "arrow"
            shapeAngle: -90
            turnsOnHover: false
            Reveal.shown: backend.canGoBack
            Reveal.scaleFrom: 0.72
            Reveal.overshoot: 1.9
            enabled: backend.canGoBack
            onClicked: backend.goBack()
            tooltip: qsTr("Назад")
        }

        ModSlotHost {
            id: topBarCenterSlot
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            x: Math.max(back.visible ? back.x + back.width + 12 : 148, 148)
            width: Math.max(0, search.x - x - 12)
            z: 5
            visible: !search.editing && width >= 180
            slotName: "topbar.center"
            slotContext: ({ topBarWidth: root.width, compact: root.compact })
        }

        Row {
            id: rightControls
            anchors.right: parent.right
            anchors.rightMargin: 12 + (root.windowControlsOnRight && !root.inspectorShown ? 96 : 0)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            ModSlotHost {
                layoutMode: "row"
                spacing: 4
                height: root.buttonSize
                anchors.verticalCenter: parent.verticalCenter
                visible: implicitWidth > 0
                slotName: "topbar.right"
                slotContext: ({ buttonSize: root.buttonSize, compact: root.compact })
            }

            ToolbarButton {
                id: overflow
                effect: ToolbarButton.Spin
                size: root.buttonSize
                iconSize: root.compact ? 20 : 24
                shape: "cookie9"
                anchors.verticalCenter: parent.verticalCenter
                symbol: "more_vert"
                onClicked: playbackMenu.popupAt(overflow, 0, overflow.height)
                tooltip: qsTr("Воспроизведение и настройки")
            }
        }
    }

    Rectangle {
        id: searchMask
        width: search.width
        height: search.height
        radius: height / 2
        layer.enabled: true
        visible: false
    }

    Item {
        id: searchBlur
        anchors.fill: search
        z: 8
        visible: search.editing && !!root.backdropSource

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Appearance.colors.layer1
        }

        ShaderEffectSource {
            id: searchBackdrop
            anchors.fill: parent
            sourceItem: root.backdropSource
            live: searchBlur.visible
            hideSource: false
            sourceRect: {
                const origin = root.mapToItem(root.backdropSource, search.x, search.y)
                return Qt.rect(origin.x, origin.y, search.width, search.height)
            }
            textureSize: Qt.size(Math.max(1, Math.ceil(search.width)), Math.max(1, Math.ceil(search.height)))
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: searchBackdrop
            blurEnabled: true
            blur: 0.8
            blurMax: 48
            maskEnabled: true
            maskSource: searchMask
        }
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Qt.alpha(Appearance.colors.surfaceContainerHighest, 0.18)
        }
    }

    Timer {
        id: suggestTimer
        interval: 220
        onTriggered: {
            if (search.editing && search.text.trim().length > 0 && backend.loggedIn) {
                backend.feature({action: "search_suggest", part: search.text.trim()})
            }
        }
    }

    SearchField {
        id: search
        x: root.searchRightEdge - width
        anchors.verticalCenter: parent.verticalCenter
        z: editing ? 9 : 0
        width: {
            if (!visible) return 0
            return editing ? Math.max(140, Math.min(340, root.searchRightEdge - root.searchLeftEdge)) : root.reservedSearchWidth
        }
        placeholder: qsTr("Поиск музыки…")
        onTextChanged: {
            if (editing && text.trim().length > 0) {
                suggestTimer.restart()
            } else {
                suggestTimer.stop()
                if (editing && backend.loggedIn) {
                    backend.feature({action: "search_suggest", part: ""})
                }
            }
        }
        onEditingChanged: {
            if (editing && backend.loggedIn) {
                if (text.trim().length > 0) suggestTimer.restart()
                else backend.feature({action: "search_suggest", part: ""})
            }
        }
        onAccepted: {
            const query = text.trim()
            root.dismissSearch()
            if (query.length > 0) {
                backend.search(query)
            }
        }

        Behavior on width {
            ElementMoveSmall {}
        }
    }

    Rectangle {
        id: suggestionsPopup
        readonly property string trimmedPart: search.text.trim()
        readonly property bool hasBest: Boolean(backend.searchSuggestBest && backend.searchSuggestBest.title)
        readonly property bool hasSuggestData: backend.searchQuickTracks.length > 0 || hasBest || backend.searchSuggestions.length > 0
        readonly property bool showingHistory: search.editing && trimmedPart.length === 0 && backend.searchHistory.length > 0
        readonly property bool suggestionsOpen: search.editing && ((trimmedPart.length > 0 && hasSuggestData) || showingHistory)

        x: Math.max(12, Math.min(search.x, root.width - width - 12))
        y: search.y + search.height + (suggestionsOpen ? 6 : 0)
        width: Math.max(search.width, Math.min(420, root.width - 24))
        height: Math.min(440, suggestColumn.implicitHeight + 14)
        z: 30
        radius: Appearance.rounding.normal
        color: Appearance.colors.surfaceContainerHigh
        border.width: 1
        border.color: Appearance.colors.outlineVariant
        transformOrigin: Item.Top
        Reveal.shown: suggestionsOpen
        Reveal.scaleFrom: 0.94
        Reveal.overshoot: 1.3
        clip: true

        Behavior on y {
            enabled: !Appearance.performanceMode
            ElementMoveSmall {}
        }
        Behavior on height {
            enabled: !Appearance.performanceMode && suggestionsPopup.visible
            ElementMoveSmall {}
        }

        Flickable {
            id: suggestScroll
            anchors.fill: parent
            anchors.margins: 7
            contentHeight: suggestColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            FastWheel { target: suggestScroll }

            Column {
                id: suggestColumn
                width: suggestScroll.width
                spacing: 4

                // История поиска (когда поле пустое)
                Item {
                    visible: suggestionsPopup.showingHistory
                    width: suggestColumn.width
                    height: 24

                    StyledText {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Недавние запросы")
                        font.pixelSize: Appearance.fontSize.smallest
                        font.weight: Font.DemiBold
                        color: Appearance.colors.onSurfaceVariant
                    }

                    StyledText {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Очистить")
                        font.pixelSize: Appearance.fontSize.smallest
                        color: clearHistHover.hovered ? Appearance.colors.primary : Appearance.colors.onSurfaceVariant

                        HoverHandler { id: clearHistHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: backend.feature({action: "clear_search_history"}) }
                    }
                }

                Repeater {
                    model: suggestionsPopup.showingHistory ? backend.searchHistory : []
                    delegate: Rectangle {
                        id: histItem
                        required property string modelData
                        width: suggestColumn.width
                        height: 34
                        radius: Appearance.rounding.small
                        color: histHover.hovered ? Appearance.colors.surfaceContainerHighest : "transparent"

                        Behavior on color { ElementMoveFastColor {} }

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "history"
                                iconSize: 16
                                color: histHover.hovered ? Appearance.colors.primary : Appearance.colors.onSurfaceVariant
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 28
                                text: histItem.modelData
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.fontSize.small
                            }
                        }

                        HoverHandler { id: histHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                search.text = histItem.modelData
                                root.dismissSearch()
                                backend.search(histItem.modelData)
                            }
                        }
                    }
                }

                // Лучший артист / альбом / плейлист с обложкой
                Rectangle {
                    id: bestSuggestCard
                    visible: suggestionsPopup.trimmedPart.length > 0 && suggestionsPopup.hasBest
                    width: suggestColumn.width
                    height: 52
                    radius: Appearance.rounding.small
                    color: bestSuggestHover.hovered ? Appearance.colors.surfaceContainerHighest : Qt.alpha(Appearance.colors.primary, 0.06)

                    Behavior on color { ElementMoveFastColor {} }

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 10
                        spacing: 10

                        ArtworkImage {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 38
                            height: 38
                            radius: (backend.searchSuggestBest?.circular ?? false) ? 19 : 7
                            circular: Boolean(backend.searchSuggestBest?.circular ?? false)
                            source: (backend.searchSuggestBest?.has_cover ?? false) ? (backend.searchSuggestBest?.cover_url ?? "") : ""
                            placeholderSymbol: (backend.searchSuggestBest?.kind ?? "") === "artist" ? "artists" : "album"
                            fallbackKey: backend.searchSuggestBest?.title ?? ""
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 68
                            spacing: 1

                            StyledText {
                                width: parent.width
                                text: backend.searchSuggestBest?.title ?? ""
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.fontSize.small
                                font.weight: Font.DemiBold
                            }
                            StyledText {
                                width: parent.width
                                text: {
                                    const k = backend.searchSuggestBest?.kind ?? ""
                                    const prefix = k === "artist" ? qsTr("Исполнитель") : (k === "album" ? qsTr("Альбом") : qsTr("Плейлист"))
                                    const sub = backend.searchSuggestBest?.subtitle ?? ""
                                    return sub.length > 0 ? (prefix + " • " + sub) : prefix
                                }
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.fontSize.smallest
                                color: Appearance.colors.onSurfaceVariant
                            }
                        }

                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "arrow_forward"
                            iconSize: 16
                            color: bestSuggestHover.hovered ? Appearance.colors.primary : Appearance.colors.onSurfaceVariant
                        }
                    }

                    HoverHandler { id: bestSuggestHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            root.dismissSearch()
                            backend.feature({action: "open_search_best", source: "suggest"})
                        }
                    }
                }

                // Быстрые треки с обложками прямо в поиске
                StyledText {
                    visible: suggestionsPopup.trimmedPart.length > 0 && backend.searchQuickTracks.length > 0
                    leftPadding: 8
                    topPadding: 2
                    text: qsTr("Треки")
                    font.pixelSize: Appearance.fontSize.smallest
                    font.weight: Font.DemiBold
                    color: Appearance.colors.onSurfaceVariant
                }

                Repeater {
                    model: suggestionsPopup.trimmedPart.length > 0 ? backend.searchQuickTracks : []
                    delegate: Rectangle {
                        id: quickTrackItem
                        required property var modelData
                        width: suggestColumn.width
                        height: 48
                        radius: Appearance.rounding.small
                        color: quickHover.hovered ? Appearance.colors.surfaceContainerHighest : "transparent"

                        Behavior on color { ElementMoveFastColor {} }

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 10
                            spacing: 10

                            Item {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 36
                                height: 36

                                ArtworkImage {
                                    anchors.fill: parent
                                    radius: 6
                                    source: (quickTrackItem.modelData?.has_cover ?? false) ? (quickTrackItem.modelData?.cover_url ?? "") : ""
                                    placeholderSymbol: "music_note"
                                    fallbackKey: quickTrackItem.modelData?.title ?? ""
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 6
                                    color: Qt.rgba(0, 0, 0, 0.45)
                                    opacity: quickHover.hovered ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "play_arrow"
                                        iconSize: 20
                                        fill: 1
                                        color: "white"
                                    }
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(0, parent.width - 90)
                                spacing: 1

                                StyledText {
                                    width: parent.width
                                    text: quickTrackItem.modelData?.title ?? ""
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.fontSize.small
                                    font.weight: Font.Medium
                                }
                                StyledText {
                                    width: parent.width
                                    text: quickTrackItem.modelData?.artists ?? ""
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.fontSize.smallest
                                    color: Appearance.colors.onSurfaceVariant
                                }
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 34
                                horizontalAlignment: Text.AlignRight
                                text: quickTrackItem.modelData?.duration ?? ""
                                tabularNumbers: true
                                font.pixelSize: Appearance.fontSize.smallest
                                color: Appearance.colors.onSurfaceVariant
                            }
                        }

                        HoverHandler { id: quickHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                root.dismissSearch()
                                backend.feature({action: "play_quick_track", id: quickTrackItem.modelData.id})
                            }
                        }
                    }
                }

                // Текстовые подсказки
                StyledText {
                    visible: suggestionsPopup.trimmedPart.length > 0 && backend.searchSuggestions.length > 0 && (backend.searchQuickTracks.length > 0 || suggestionsPopup.hasBest)
                    leftPadding: 8
                    topPadding: 2
                    text: qsTr("Запросы")
                    font.pixelSize: Appearance.fontSize.smallest
                    font.weight: Font.DemiBold
                    color: Appearance.colors.onSurfaceVariant
                }

                Repeater {
                    model: suggestionsPopup.trimmedPart.length > 0 ? backend.searchSuggestions.slice(0, 5) : []
                    delegate: Rectangle {
                        id: suggestItem
                        required property string modelData
                        width: suggestColumn.width
                        height: 34
                        radius: Appearance.rounding.small
                        color: suggestHover.hovered ? Appearance.colors.surfaceContainerHighest : "transparent"

                        Behavior on color {
                            ElementMoveFastColor {}
                        }

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: suggestHover.hovered ? 13 : 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Behavior on anchors.leftMargin {
                                enabled: !Appearance.performanceMode
                                ElementMoveSmall {}
                            }

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "search"
                                iconSize: 16
                                color: suggestHover.hovered ? Appearance.colors.primary : Appearance.colors.onSurfaceVariant

                                Behavior on color {
                                    ElementMoveFastColor {}
                                }
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 28
                                text: suggestItem.modelData
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.fontSize.small
                            }
                        }

                        HoverHandler {
                            id: suggestHover
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            onTapped: {
                                search.text = suggestItem.modelData
                                root.dismissSearch()
                                backend.search(suggestItem.modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    MenuLoader {
        id: playbackMenu
        sourceComponent: PlaybackMenu {}
    }
}
