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
            visible: backend.canGoBack
            enabled: backend.canGoBack
            onClicked: backend.goBack()
            tooltip: qsTr("Назад")
        }

        Row {
            id: rightControls
            anchors.right: parent.right
            anchors.rightMargin: 12 + (root.windowControlsOnRight && !root.inspectorShown ? 96 : 0)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

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
        x: search.x
        y: search.y + search.height + 6
        width: search.width
        height: suggestColumn.implicitHeight + 12
        z: 30
        radius: Appearance.rounding.normal
        color: Appearance.colors.surfaceContainerHigh
        border.width: 1
        border.color: Appearance.colors.outlineVariant
        visible: search.editing && search.text.trim().length > 0 && backend.searchSuggestions.length > 0

        Column {
            id: suggestColumn
            x: 6
            y: 6
            width: parent.width - 12
            spacing: 2

            Repeater {
                model: backend.searchSuggestions
                delegate: Rectangle {
                    required property string modelData
                    width: suggestColumn.width
                    height: 34
                    radius: Appearance.rounding.small
                    color: suggestHover.hovered ? Appearance.colors.surfaceContainerHighest : "transparent"

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "search"
                            iconSize: 16
                            color: Appearance.colors.onSurfaceVariant
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 28
                            text: modelData
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
                            search.text = modelData
                            root.dismissSearch()
                            backend.search(modelData)
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
