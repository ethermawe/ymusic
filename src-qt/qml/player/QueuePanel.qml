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
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ymusic.ui

Item {
    id: root

    property MaterialScheme scheme: Appearance.colors

    RowLayout {
        id: headerRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        spacing: 8

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Очередь")
            elide: Text.ElideRight
            font.pixelSize: Appearance.fontSize.normal
            font.weight: Font.DemiBold
            color: root.scheme.onSurfaceVariant
        }

        IconButton {
            visible: backend.queue.count > 0
            symbol: "delete_sweep"
            size: 32
            iconSize: 18
            scheme: root.scheme
            tooltip: qsTr("Очистить очередь")
            onClicked: backend.feature({ action: "queue", operation: "clear" })
        }
    }

    ListView {
        id: list
        anchors.fill: parent
        anchors.topMargin: 56
        leftMargin: 12
        rightMargin: 12
        bottomMargin: 20
        clip: true
        model: backend.queue
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        reuseItems: true
        ScrollBar.vertical: StyledScrollBar {}
        FastWheel { target: list }

        header: Column {
            width: list.width - list.leftMargin - list.rightMargin
            spacing: 8

            StyledText {
                Reveal.shown: backend.hasTrack
                leftPadding: 6
                text: qsTr("Сейчас играет")
                font.pixelSize: Appearance.fontSize.smaller
                font.weight: Font.Bold
                color: root.scheme.onSurfaceVariant
            }
            QueueRow {
                width: parent.width
                Reveal.shown: backend.hasTrack
                trackId: backend.nowId
                titleText: backend.nowTitle
                artistsText: backend.nowArtists
                coverUrl: backend.hasCover ? backend.nowCover : ""
                current: true
                isAi: backend.nowIsAi
                scheme: root.scheme
            }
            StyledText {
                Reveal.shown: backend.queue.count > 0
                leftPadding: 6
                topPadding: 8
                bottomPadding: 2
                text: qsTr("Далее · ") + backend.queue.count
                font.pixelSize: Appearance.fontSize.smaller
                font.weight: Font.Bold
                color: root.scheme.onSurfaceVariant
            }
        }

        delegate: QueueRow {
            required property int index
            required property var model
            width: list.width - list.leftMargin - list.rightMargin
            trackId: model.id || ""
            titleText: model.title || ""
            artistsText: model.artists || ""
            coverUrl: model.hasCover ? (model.coverUrl || "") : ""
            current: Boolean(model.isCurrent)
            available: model.available === undefined ? true : Boolean(model.available)
            isAi: Boolean(model.isAi)
            scheme: root.scheme
            onClicked: backend.trackAction(trackId, 3)
        }
    }

    EmptyState {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 24
        width: parent.width - 32
        Reveal.shown: backend.queue.count === 0
        symbol: "queue_music"
        title: qsTr("Очередь пуста")
        description: qsTr("Запустите трек, альбом или Мою волну")
        scheme: root.scheme
    }
}
