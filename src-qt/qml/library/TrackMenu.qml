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

    function showFor(id, title, available) {
        trackId = id;
        trackTitle = title;
        trackAvailable = available;
        downloaded = backend.isDownloaded(id);
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
    MenuSeparator {}
    Entry {
        text: "Добавить в плейлист…"
        enabled: backend.loggedIn
        onTriggered: playlistPicker.choose(root.trackId, root.trackTitle)
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
        title: "Сохранить аудиофайл (MP3)"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Аудио MP3 (*.mp3)"]
        defaultSuffix: "mp3"
        onAccepted: backend.downloadTrack(pendingTrackId, selectedFile)
    }
    PlaylistPicker {
        id: playlistPicker
        parent: Overlay.overlay
    }
}
