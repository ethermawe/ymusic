pragma ComponentBehavior: Bound
import QtCore
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
        downloaded = Backend.isDownloaded(id);
    }

    function showFor(id, title, available) {
        prepareFor(id, title, available);
        popup();
    }

    StyledMenuItem {
        text: "Играть следующим"
        symbol: "queue_play_next"
        enabled: root.trackAvailable
        onTriggered: Backend.trackAction(root.trackId, 0)
    }
    StyledMenuItem {
        text: "Добавить в конец очереди"
        symbol: "add_to_queue"
        enabled: root.trackAvailable
        onTriggered: Backend.trackAction(root.trackId, 1)
    }
    StyledMenuItem {
        text: "Играть на повторе"
        symbol: "repeat_one"
        enabled: root.trackAvailable
        onTriggered: Backend.trackAction(root.trackId, 2)
    }

    StyledMenuSeparator {}

    StyledMenuItem {
        text: "Волна по треку"
        symbol: "my_wave"
        enabled: Backend.loggedIn && root.trackId !== ""
        onTriggered: Backend.feature({action: "track_wave", id: root.trackId, title: root.trackTitle})
    }
    StyledMenuItem {
        text: "Похожие треки"
        symbol: "auto_awesome"
        enabled: Backend.loggedIn && root.trackId !== ""
        onTriggered: Backend.feature({action: "similar_tracks", id: root.trackId, title: root.trackTitle})
    }
    StyledMenuItem {
        text: "Не нравится"
        symbol: "thumb_down"
        visible: !(Backend.page === 6 && Backend.listTitle === "Не нравится")
        enabled: Backend.loggedIn && root.trackId !== ""
        onTriggered: Backend.feature({action: "dislike_track", id: root.trackId})
    }
    StyledMenuItem {
        text: "Убрать из «Не нравится»"
        symbol: "thumb_up"
        visible: Backend.page === 6 && Backend.listTitle === "Не нравится"
        enabled: Backend.loggedIn && root.trackId !== ""
        onTriggered: Backend.feature({action: "undislike_track", id: root.trackId})
    }
    StyledMenuItem {
        text: "Авторы и информация…"
        symbol: "info"
        enabled: Backend.loggedIn && root.trackId !== ""
        onTriggered: Backend.feature({action: "track_credits", id: root.trackId, title: root.trackTitle})
    }
    StyledMenuItem {
        text: "Скопировать ссылку на трек"
        symbol: "content_copy"
        enabled: root.trackId !== ""
        onTriggered: Backend.feature({action: "copy_track_link", id: root.trackId})
    }

    StyledMenuSeparator {}

    StyledMenuItem {
        text: "Добавить в плейлист…"
        symbol: "playlist_add"
        enabled: Backend.loggedIn
        onTriggered: playlistPicker.choose(root.trackId, root.trackTitle)
    }
    StyledMenuItem {
        text: "Удалить из плейлиста"
        symbol: "playlist_remove"
        destructive: true
        visible: Backend.page === 6 && Backend.isOwnPlaylist
        onTriggered: Backend.feature({action: "remove_from_playlist", id: root.trackId})
    }
    StyledMenuItem {
        text: "Скачать"
        symbol: "download"
        enabled: root.trackAvailable && !root.downloaded && Backend.loggedIn
        onTriggered: Backend.saveOffline(root.trackId)
    }
    StyledMenuItem {
        text: "Удалить трек с устройства"
        symbol: "delete"
        destructive: true
        visible: root.downloaded
        onTriggered: Backend.removeDownload(root.trackId)
    }
    StyledMenuItem {
        text: "Скачать аудиофайл…"
        symbol: "audio_file"
        enabled: root.trackAvailable
        onTriggered: {
            saveDialog.pendingTrackId = root.trackId;
            const rawName = (root.trackTitle || "track").replace(/[\\/:*?"<>|]/g, "_").trim();
            const safeName = rawName.length > 0 ? rawName : "track";
            const useFlac = Backend.downloadQuality === "flac"
                || (Backend.downloadQuality === "match" && Backend.audioQuality === "lossless");
            const ext = useFlac ? "flac" : "mp3";
            const folder = String(saveDialog.currentFolder || StandardPaths.writableLocation(StandardPaths.MusicLocation));
            const sep = folder.endsWith("/") ? "" : "/";
            saveDialog.selectedFile = folder + sep + safeName + "." + ext;
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
            defaultSuffix: (Backend.downloadQuality === "flac" || (Backend.downloadQuality === "match" && Backend.audioQuality === "lossless")) ? "flac" : "mp3"
            onAccepted: Backend.downloadTrack(pendingTrackId, selectedFile)
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
            target: Backend
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
