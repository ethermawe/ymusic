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
import ymusic.ui

Item {
    id: root

    readonly property bool isArtist: backend.isArtistView
    readonly property url artworkUrl: isArtist ? (backend.artistHasAvatar ? backend.artistAvatar : "") : backend.listCover
    readonly property bool circular: isArtist
    readonly property string kind: isArtist ? "Исполнитель"
        : (backend.page === 2 ? "Мне нравится" : (backend.page === 7 ? "Загружено" : "Коллекция"))
    readonly property string kindSymbol: isArtist ? "artists"
        : (backend.page === 2 ? "favorite" : (backend.page === 7 ? "download_done" : "queue_music"))
    readonly property string title: isArtist ? backend.artistName : backend.listTitle
    readonly property string description: isArtist ? backend.artistGenres : ""
    readonly property string facts: isArtist ? backend.artistStats : backend.listSubtitle
    readonly property bool downloading: Boolean(backend.batch && backend.batch.running)
    readonly property real titleSize: stacked ? 26 : 34

    readonly property real sideArtworkSpace: width - 2 * Appearance.sizes.pageMargin - 24 - 220
    readonly property bool stacked: sideArtworkSpace < 160
    readonly property real artworkSize: stacked ? Math.min(176, (width - 2 * Appearance.sizes.pageMargin) * 0.5)
                                              : Math.min(Appearance.sizes.headerArtwork, sideArtworkSpace)

    implicitHeight: stacked ? artworkSize + details.implicitHeight + 100
                            : Math.max(artworkSize, details.implicitHeight) + 80

    Stickers {
        anchors.fill: parent
        key: root.kind + root.title
        count: 5
        minimumSize: 80
        maximumSize: 230
    }

    Item {
        id: artworkBox
        objectName: "heroArtwork"
        x: Appearance.sizes.pageMargin
        y: 40
        width: root.artworkSize
        height: width

        readonly property bool awaitingFlight: UiState.heroTarget === artworkBox
        readonly property bool ready: cover.ready

        Component.onCompleted: UiState.claimHero(artworkBox)

        Binding {
            target: UiState
            property: "heroReady"
            value: artworkBox.ready
            when: artworkBox.awaitingFlight
        }

        ArtworkGlow {
            anchors.fill: parent
            opacity: artworkBox.awaitingFlight ? 0 : 1
            source: root.artworkUrl
            circular: root.circular
            intensity: 0.24
            glowRadius: 30

            Behavior on opacity {
                NumberAnimation { duration: Appearance.duration(320); easing.type: Easing.OutCubic }
            }
        }

        ArtworkImage {
            id: cover
            anchors.fill: parent
            opacity: artworkBox.awaitingFlight ? 0 : 1
            source: root.artworkUrl
            fallbackKey: root.title
            placeholderSymbol: root.isArtist ? "artists" : (backend.page === 2 ? "favorite" : "library_music")
            circular: root.circular
        }
    }

    Column {
        id: details
        objectName: "heroDetails"
        x: root.stacked ? Appearance.sizes.pageMargin : artworkBox.x + artworkBox.width + 24
        y: root.stacked ? artworkBox.y + artworkBox.height + 20
                        : 40 + Math.max(0, artworkBox.height - implicitHeight)
        width: Math.max(0, root.width - x - Appearance.sizes.pageMargin)
        spacing: 9

        Rectangle {
            width: Math.min(parent.width, kindRow.implicitWidth + 20)
            height: 26
            radius: height / 2
            color: Appearance.colors.primaryContainer

            Row {
                id: kindRow
                anchors.centerIn: parent
                spacing: 5

                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.kindSymbol
                    iconSize: 15
                    fill: 1
                    color: Appearance.colors.onPrimaryContainer
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.kind.toUpperCase()
                    font.pixelSize: Appearance.fontSize.smallest
                    font.weight: Font.Bold
                    font.letterSpacing: 0.8
                    color: Appearance.colors.onPrimaryContainer
                }
            }
        }

        TitleText {
            width: parent.width
            text: root.title
            maximumLineCount: 2
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            font.pixelSize: root.titleSize
            font.weight: Font.Bold
        }

        StyledText {
            width: parent.width
            visible: root.description.length > 0
            text: root.description
            maximumLineCount: 3
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            color: Appearance.colors.onSurfaceVariant
        }

        Flow {
            width: parent.width
            visible: root.facts.length > 0
            spacing: 6

            Repeater {
                model: root.facts.split("  •  ")

                Rectangle {
                    id: chip
                    required property string modelData
                    visible: modelData.length > 0
                    width: Math.min(parent.width, factText.implicitWidth + 18)
                    height: 24
                    radius: height / 2
                    color: Appearance.colors.surfaceContainerHigh

                    StyledText {
                        id: factText
                        anchors.centerIn: parent
                        width: Math.max(0, parent.width - 18)
                        elide: Text.ElideRight
                        text: chip.modelData
                        font.pixelSize: Appearance.fontSize.smaller
                        color: Appearance.colors.onSurfaceVariant
                    }
                }
            }
        }

        Flow {
            id: actionSlot
            objectName: "heroActions"
            width: parent.width
            readonly property bool compactActions: width < 130
            readonly property real actionSize: Math.max(28, Math.min(48, (width - 30) / 4))
            topPadding: 6
            spacing: 10

            PlayButton {
                playing: backend.tracks.currentIndex >= 0 && backend.playing
                size: actionSlot.compactActions ? Math.min(40, actionSlot.actionSize) : 44
                iconSize: actionSlot.compactActions ? 20 : 24
                enabled: backend.tracks.count > 0
                tooltip: playing ? "Пауза" : "Слушать"
                onClicked: {
                    if (backend.tracks.currentIndex >= 0) backend.toggle();
                    else backend.play(0);
                }
            }

            TextButton {
                visible: !root.isArtist && backend.collectionDownloadable && backend.loggedIn
                enabled: !root.downloading && backend.tracks.count > 0
                wavy: !root.downloading
                variant: TextButton.Tonal
                symbol: root.downloading ? "downloading" : "download"
                text: root.downloading
                    ? ("Загрузка " + backend.batch.done + "/" + backend.batch.total)
                    : "Скачать всё"
                onClicked: backend.feature({action: "download_collection"})
            }

            TextButton {
                visible: !root.isArtist && backend.page === 6 && backend.activePlaylistKey.length > 0 && backend.loggedIn
                variant: backend.activePlaylistPinned ? TextButton.Tonal : TextButton.Outlined
                symbol: "push_pin"
                text: backend.activePlaylistPinned ? qsTr("Открепить") : qsTr("Закрепить")
                onClicked: backend.feature({action: "toggle_pin_playlist"})
            }

            TextButton {
                visible: root.isArtist && backend.canStartArtistWave && backend.loggedIn
                variant: TextButton.Filled
                wavy: true
                symbol: "my_wave"
                text: "Моя волна по артисту"
                onClicked: backend.startArtistWave()
            }

            IconButton {
                visible: backend.loggedIn && backend.collectionKind !== "" && backend.collectionKind !== "own_playlist"
                symbol: backend.collectionLiked ? "favorite" : "favorite_border"
                toggled: backend.collectionLiked
                burst: "hearts"
                size: 40
                iconSize: 22
                tooltip: backend.collectionLiked ? "Убрать из Моей музыки" : "Добавить в Мою музыку"
                onClicked: backend.feature({action: "toggle_like_collection"})
            }

            TextButton {
                visible: !root.isArtist && backend.page === 6 && backend.isOwnPlaylist && backend.loggedIn
                variant: TextButton.Outlined
                symbol: "edit"
                text: "Переименовать"
                onClicked: {
                    renameField.text = root.title;
                    renamePlaylistDialog.open();
                }
            }

            IconButton {
                visible: !root.isArtist && backend.page === 6 && backend.isOwnPlaylist && backend.loggedIn
                symbol: "delete"
                size: 40
                iconSize: 21
                tooltip: "Удалить плейлист"
                onClicked: deletePlaylistDialog.open()
            }

            ModSlotHost {
                layoutMode: "row"
                height: 40
                spacing: 8
                visible: implicitWidth > 0
                slotName: "collection.actions"
                slotContext: ({
                    title: root.title,
                    isArtist: root.isArtist,
                    kind: backend.collectionKind,
                    playlistKey: backend.activePlaylistKey
                })
            }
        }
    }

    StyledDialog {
        id: renamePlaylistDialog
        headline: "Переименовать плейлист"
        symbol: "edit"
        iconShape: "bun"
        preferredWidth: 420

        onOpened: renameField.inputItem.forceActiveFocus()

        OutlinedTextField {
            id: renameField
            width: parent.width
            placeholder: "Новое название плейлиста"
            onAccepted: {
                if (text.trim().length > 0) {
                    backend.feature({action: "rename_playlist", title: text.trim()});
                    renamePlaylistDialog.accept();
                }
            }
        }

        buttons: [
            TextButton {
                text: "Отмена"
                variant: TextButton.Text
                onClicked: renamePlaylistDialog.close()
            },
            TextButton {
                text: "Сохранить"
                variant: TextButton.Filled
                enabled: renameField.text.trim().length > 0
                onClicked: {
                    backend.feature({action: "rename_playlist", title: renameField.text.trim()});
                    renamePlaylistDialog.accept();
                }
            }
        ]
    }

    StyledDialog {
        id: deletePlaylistDialog
        headline: "Удалить плейлист?"
        symbol: "delete"
        iconShape: "clover4"
        body: "Плейлист «" + root.title + "» будет удалён без возможности восстановления."
        buttons: [
            TextButton {
                text: "Отмена"
                variant: TextButton.Text
                onClicked: deletePlaylistDialog.close()
            },
            TextButton {
                text: "Удалить"
                variant: TextButton.Filled
                onClicked: {
                    backend.feature({action: "delete_playlist"});
                    deletePlaylistDialog.accept();
                }
            }
        ]
    }
}
