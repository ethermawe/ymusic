import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import ymusic.ui

Menu {
    id: root
    property string trackId: ""
    property string trackTitle: ""
    property bool trackAvailable: true
    property bool downloaded: false
    width: 272
    padding: 8

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

    background: Rectangle {
        radius: Appearance.rounding.normal
        color: Appearance.colors.surfaceContainerHigh
        border.color: Appearance.colors.outlineVariant
        border.width: 1
    }

    component Entry: MenuItem {
        id: entry
        implicitHeight: 40
        contentItem: Text {
            text: entry.text
            font.family: Appearance.fontFamily
            font.pixelSize: Appearance.fontSize.small
            color: entry.enabled ? Appearance.colors.onSurface : Appearance.colors.onSurfaceVariant
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            radius: Appearance.rounding.small
            color: entry.highlighted ? Appearance.colors.surfaceContainerHighest : "transparent"
        }
    }

    Entry {
        text: "Играть следующим"
        enabled: root.trackAvailable
        onTriggered: backend.trackAction(root.trackId, 0)
    }
    Entry {
        text: "Добавить в конец очереди"
        enabled: root.trackAvailable
        onTriggered: backend.trackAction(root.trackId, 1)
    }
    Entry {
        text: "Играть на повторе"
        enabled: root.trackAvailable
        onTriggered: backend.trackAction(root.trackId, 2)
    }
    Entry {
        text: "Волна по треку"
        enabled: backend.loggedIn && root.trackId !== ""
        onTriggered: backend.feature({action: "track_wave", id: root.trackId, title: root.trackTitle})
    }
    Entry {
        text: "Похожие треки"
        enabled: backend.loggedIn && root.trackId !== ""
        onTriggered: backend.feature({action: "similar_tracks", id: root.trackId, title: root.trackTitle})
    }
    Entry {
        text: "Авторы и информация…"
        enabled: backend.loggedIn && root.trackId !== ""
        onTriggered: backend.feature({action: "track_credits", id: root.trackId, title: root.trackTitle})
    }
    Entry {
        text: "Скопировать ссылку на трек"
        enabled: root.trackId !== ""
        onTriggered: backend.feature({action: "copy_track_link", id: root.trackId})
    }
    MenuSeparator {}
    Entry {
        text: "Добавить в плейлист…"
        enabled: backend.loggedIn
        onTriggered: playlistPicker.choose(root.trackId, root.trackTitle)
    }
    Entry {
        text: "Удалить из плейлиста"
        visible: backend.page === 6 && backend.isOwnPlaylist
        height: visible ? implicitHeight : 0
        onTriggered: backend.feature({action: "remove_from_playlist", id: root.trackId})
    }
    Entry {
        text: "Скачать"
        enabled: root.trackAvailable && !root.downloaded && backend.loggedIn
        onTriggered: backend.saveOffline(root.trackId)
    }
    Entry {
        text: "Удалить трек с устройства"
        visible: root.downloaded
        height: visible ? implicitHeight : 0
        onTriggered: backend.removeDownload(root.trackId)
    }
    Entry {
        text: "Скачать аудиофайл…"
        enabled: root.trackAvailable
        onTriggered: {
            saveDialog.pendingTrackId = root.trackId;
            saveDialog.selectedFile = "";
            saveDialog.open();
        }
    }

    FileDialog {
        id: saveDialog
        property string pendingTrackId: ""
        title: "Сохранить аудиофайл"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Аудиофайлы (*.mp3 *.flac *.m4a)"]
        defaultSuffix: backend.audioQuality === "lossless" ? "flac" : "mp3"
        onAccepted: backend.downloadTrack(pendingTrackId, selectedFile)
    }
    PlaylistPicker {
        id: playlistPicker
        parent: Overlay.overlay
    }
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
    }
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
}
