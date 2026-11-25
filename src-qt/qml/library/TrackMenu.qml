pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import ymusic.ui

StyledMenu {
    id: root
    property string trackId: ""
    property string trackTitle: ""
    property bool trackAvailable: true
    property bool downloaded: false

    function prepareFor(id, title, available) {
        trackId = id;
        trackTitle = title;
        trackAvailable = available;
        downloaded = backend.isDownloaded(id);
    }

    function showFor(id, title, available) {
        prepareFor(id, title, available);
        popup();
    }

    StyledMenuItem {
        text: "Играть следующим"
        symbol: "queue_play_next"
        enabled: root.trackAvailable
        onTriggered: backend.trackAction(root.trackId, 0)
    }
    StyledMenuItem {
        text: "Добавить в конец очереди"
        symbol: "add_to_queue"
        enabled: root.trackAvailable
        onTriggered: backend.trackAction(root.trackId, 1)
    }
    StyledMenuItem {
        text: "Играть на повторе"
        symbol: "repeat_one"
        enabled: root.trackAvailable
        onTriggered: backend.trackAction(root.trackId, 2)
    }

    StyledMenuSeparator {}

    StyledMenuItem {
        text: "Волна по треку"
        symbol: "my_wave"
        enabled: backend.loggedIn && root.trackId !== ""
        onTriggered: backend.feature({action: "track_wave", id: root.trackId, title: root.trackTitle})
    }
    StyledMenuItem {
        text: "Похожие треки"
        symbol: "auto_awesome"
        enabled: backend.loggedIn && root.trackId !== ""
        onTriggered: backend.feature({action: "similar_tracks", id: root.trackId, title: root.trackTitle})
    }
    StyledMenuItem {
        text: "Не нравится"
        symbol: "thumb_down"
        visible: !(backend.page === 6 && backend.listTitle === "Не нравится")
        enabled: backend.loggedIn && root.trackId !== ""
        onTriggered: backend.feature({action: "dislike_track", id: root.trackId})
    }
    StyledMenuItem {
        text: "Убрать из «Не нравится»"
        symbol: "thumb_up"
        visible: backend.page === 6 && backend.listTitle === "Не нравится"
        enabled: backend.loggedIn && root.trackId !== ""
        onTriggered: backend.feature({action: "undislike_track", id: root.trackId})
    }
    StyledMenuItem {
        text: "Авторы и информация…"
        symbol: "info"
        enabled: backend.loggedIn && root.trackId !== ""
        onTriggered: backend.feature({action: "track_credits", id: root.trackId, title: root.trackTitle})
    }
    StyledMenuItem {
        text: "Скопировать ссылку на трек"
        symbol: "content_copy"
        enabled: root.trackId !== ""
        onTriggered: backend.feature({action: "copy_track_link", id: root.trackId})
    }

    StyledMenuSeparator {}

    StyledMenuItem {
        text: "Добавить в плейлист…"
        symbol: "playlist_add"
        enabled: backend.loggedIn
        onTriggered: playlistPicker.choose(root.trackId, root.trackTitle)
    }
    StyledMenuItem {
        text: "Удалить из плейлиста"
        symbol: "playlist_remove"
        destructive: true
        visible: backend.page === 6 && backend.isOwnPlaylist
        onTriggered: backend.feature({action: "remove_from_playlist", id: root.trackId})
    }
    StyledMenuItem {
        text: "Скачать"
        symbol: "download"
        enabled: root.trackAvailable && !root.downloaded && backend.loggedIn
        onTriggered: backend.saveOffline(root.trackId)
    }
    StyledMenuItem {
        text: "Удалить трек с устройства"
        symbol: "delete"
        destructive: true
        visible: root.downloaded
        onTriggered: backend.removeDownload(root.trackId)
    }
    StyledMenuItem {
        text: "Скачать аудиофайл…"
        symbol: "audio_file"
        enabled: root.trackAvailable
        onTriggered: {
            saveDialog.pendingTrackId = root.trackId;
            saveDialog.selectedFile = "";
            saveDialog.open();
        }
    }

    StyledMenuSeparator {
        visible: ModManager.trackMenuActions.length > 0
        height: visible ? implicitHeight : 0
    }

    property list<QtObject> _helpers: [
        Instantiator {
            model: ModManager.trackMenuActions
            delegate: StyledMenuItem {
                required property var modelData
                text: modelData.label || ""
                symbol: modelData.symbol || "extension"
                destructive: Boolean(modelData.destructive)
                onTriggered: ModManager.triggerTrackMenuAction(
                    modelData.modId,
                    modelData.actionId,
                    root.trackId,
                    root.trackTitle
                )
            }
            onObjectAdded: (index, object) => root.insertItem(root.count, object)
            onObjectRemoved: (index, object) => root.removeItem(object)
        },
        FileDialog {
            id: saveDialog
            property string pendingTrackId: ""
            title: "Сохранить аудиофайл"
            fileMode: FileDialog.SaveFile
            nameFilters: ["Аудиофайлы (*.mp3 *.flac *.m4a)"]
            defaultSuffix: backend.audioQuality === "lossless" ? "flac" : "mp3"
            onAccepted: backend.downloadTrack(pendingTrackId, selectedFile)
        },
        PlaylistPicker {
            id: playlistPicker
            parent: Overlay.overlay
        },
        StyledDialog {
            id: creditsDialog
            parent: Overlay.overlay
            property string creditsTitle: ""
            property var creditsList: []
            headline: creditsTitle.length > 0 ? ("Авторы: " + creditsTitle) : "Авторы и участники"
            symbol: "info"
            iconShape: "sunny"
            preferredWidth: 440

            Column {
                width: parent.width
                spacing: 8

                Repeater {
                    model: creditsDialog.creditsList
                    delegate: Column {
                        required property var modelData
                        width: parent ? parent.width : 0
                        spacing: 2

                        StyledText {
                            width: parent.width
                            text: modelData.title || ""
                            font.pixelSize: Appearance.fontSize.smaller
                            color: Appearance.colors.onSurfaceVariant
                        }
                        StyledText {
                            width: parent.width
                            text: modelData.value || ""
                            wrapMode: Text.WordWrap
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }

            buttons: [
                TextButton {
                    text: "Закрыть"
                    variant: TextButton.Filled
                    onClicked: creditsDialog.close()
                }
            ]
        },
        Connections {
            target: backend
            function onFeatureResult(result) {
                if (result.type === "track_credits" && result.credits && result.credits.length > 0) {
                    creditsDialog.creditsTitle = result.title || "";
                    creditsDialog.creditsList = result.credits;
                    creditsDialog.open();
                }
            }
        }
    ]
}
