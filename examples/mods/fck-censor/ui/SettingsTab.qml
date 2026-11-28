pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ymusic.sdk 1.0

Column {
    id: root

    property var modApi: null
    width: parent ? parent.width : 0
    spacing: 16

    property bool useRemoteDb: modApi ? Boolean(modApi.storageGet("useRemoteDb", true)) : true
    property bool showPlayerBadge: modApi ? Boolean(modApi.storageGet("showPlayerBadge", true)) : true
    property string remoteStatus: modApi ? String(modApi.storageGet("remoteStatus", "Ожидание загрузки…")) : ""
    property var customOverrides: modApi ? (modApi.storageGet("customOverrides", ({})) || ({})) : ({})
    property int appliedCount: modApi ? Number(modApi.storageGet("appliedCount", 0)) : 0
    property int remoteTrackCount: modApi ? Number(modApi.storageGet("remoteTrackCount", 0)) : 0
    property int remoteAudioCount: modApi ? Number(modApi.storageGet("remoteAudioCount", 0)) : 0

    function syncFromStorage() {
        if (!modApi) return;
        useRemoteDb = Boolean(modApi.storageGet("useRemoteDb", true));
        showPlayerBadge = Boolean(modApi.storageGet("showPlayerBadge", true));
        remoteStatus = String(modApi.storageGet("remoteStatus", "Готово"));
        customOverrides = modApi.storageGet("customOverrides", ({})) || ({});
        appliedCount = Number(modApi.storageGet("appliedCount", 0));
        remoteTrackCount = Number(modApi.storageGet("remoteTrackCount", 0));
        remoteAudioCount = Number(modApi.storageGet("remoteAudioCount", 0));

        const draftId = String(modApi.storageGet("draftTrackId", "") || "");
        const draftTitle = String(modApi.storageGet("draftTrackTitle", "") || "");
        if (draftId.length > 0) {
            trackIdField.text = draftId;
            if (draftTitle.length > 0 && titleField.text.length === 0) {
                titleField.text = draftTitle;
            }
            modApi.storageRemove("draftTrackId");
            modApi.storageRemove("draftTrackTitle");
        }
    }

    function loadOverrideIntoForm(id) {
        const ov = root.customOverrides[id] || ({});
        trackIdField.text = id;
        titleField.text = ov.title || "";
        artistField.text = ov.artists || "";
        coverField.text = ov.coverUrl || "";
        audioField.text = ov.localFile || ov.audioUrl || ov.audioTrackId || "";
    }

    Component.onCompleted: syncFromStorage()

    Connections {
        target: root.modApi
        function onStorageChanged(key) {
            if (!root.modApi) return;
            if (key === "remoteStatus" || key === "appliedCount" || key === "remoteTrackCount"
                || key === "remoteAudioCount" || key === "customOverrides"
                || key === "useRemoteDb" || key === "showPlayerBadge"
                || key === "draftTrackId") {
                Qt.callLater(root.syncFromStorage);
            }
        }
    }

    ContentSection {
        title: "База подмен FckCensorData"
        symbol: "graphic_eq"

        Flow {
            x: 8
            width: parent.width - 16
            spacing: 8

            Badge {
                symbol: "check_circle"
                text: "Активно: " + root.appliedCount
                tone: "primary"
            }
            Badge {
                symbol: "library_music"
                text: "База: " + root.remoteTrackCount
                tone: "secondary"
                visible: root.remoteTrackCount > 0
            }
            Badge {
                symbol: "audio_file"
                text: "Аудио: " + root.remoteAudioCount
                tone: "tertiary"
                visible: root.remoteAudioCount > 0
            }
        }

        ConfigSwitch {
            text: "Автоматические подмены из FckCensorData"
            checked: root.useRemoteDb
            onToggledTo: (checked) => {
                root.useRemoteDb = checked;
                if (root.modApi) {
                    root.modApi.storageSet("useRemoteDb", checked);
                }
            }
        }

        ConfigSwitch {
            text: "Показывать бейдж FckCensor в плеере"
            checked: root.showPlayerBadge
            onToggledTo: (checked) => {
                root.showPlayerBadge = checked;
                if (root.modApi) {
                    root.modApi.storageSet("showPlayerBadge", checked);
                }
            }
        }

        NoteText {
            text: root.remoteStatus
        }

        Flow {
            x: 8
            width: parent.width - 16
            spacing: 8

            TextButton {
                variant: TextButton.Tonal
                symbol: "refresh"
                text: "Обновить базу"
                onClicked: {
                    if (!root.modApi) return;
                    root.modApi.storageSet("refreshNonce", Date.now());
                    root.modApi.showToast("Обновление базы FckCensorData…");
                }
            }
            TextButton {
                variant: TextButton.Outlined
                symbol: "open_in_new"
                text: "FckCensorData"
                onClicked: if (root.modApi) root.modApi.openExternalUrl("https://github.com/Hazzz895/FckCensorData")
            }
        }
    }

    ContentSection {
        title: "Своя подмена трека"
        symbol: "edit"

        Column {
            x: 8
            width: parent.width - 16
            spacing: 8

            Flow {
                width: parent.width
                spacing: 8

                Chip {
                    symbol: "music_note"
                    text: "Подставить текущий трек"
                    enabled: root.modApi && root.modApi.hasTrack
                    onClicked: {
                        if (!root.modApi || !root.modApi.hasTrack) return;
                        trackIdField.text = root.modApi.trackId || "";
                        titleField.text = root.modApi.trackTitle || "";
                        artistField.text = root.modApi.trackArtists || "";
                        coverField.text = root.modApi.trackCover || "";
                    }
                }
            }

            OutlinedTextField {
                id: trackIdField
                width: parent.width
                placeholder: "ID трека Яндекс Музыки (или выберите в меню трека)"
            }
            OutlinedTextField {
                id: titleField
                width: parent.width
                placeholder: "Новое название (необязательно)"
            }
            OutlinedTextField {
                id: artistField
                width: parent.width
                placeholder: "Новый исполнитель (необязательно)"
            }
            OutlinedTextField {
                id: audioField
                width: parent.width
                placeholder: "HTTPS URL аудио, локальный путь (/path/file.mp3) или другой trackId"
            }
            OutlinedTextField {
                id: coverField
                width: parent.width
                placeholder: "URL обложки (необязательно)"
            }

            Flow {
                width: parent.width
                spacing: 8

                TextButton {
                    variant: TextButton.Filled
                    symbol: "save"
                    text: "Сохранить подмену"
                    enabled: trackIdField.text.trim().length > 0
                    onClicked: {
                        if (!root.modApi) return;
                        const id = trackIdField.text.trim();
                        const entry = { available: true };
                        if (titleField.text.trim().length > 0) entry.title = titleField.text.trim();
                        if (artistField.text.trim().length > 0) entry.artists = artistField.text.trim();
                        if (coverField.text.trim().length > 0) entry.coverUrl = coverField.text.trim();

                        const audio = audioField.text.trim();
                        if (audio.length > 0) {
                            if (audio.indexOf("https://") === 0 || audio.indexOf("http://localhost") === 0 || audio.indexOf("http://127.0.0.1") === 0) {
                                entry.audioUrl = audio;
                            } else if (/^\d+$/.test(audio)) {
                                entry.audioTrackId = audio;
                            } else {
                                entry.localFile = audio;
                            }
                        }

                        const next = Object.assign({}, root.customOverrides);
                        next[id] = entry;
                        root.customOverrides = next;
                        root.modApi.storageSet("customOverrides", next);
                        root.modApi.showToast("Подмена для трека " + id + " сохранена");
                        trackIdField.text = "";
                        titleField.text = "";
                        artistField.text = "";
                        audioField.text = "";
                        coverField.text = "";
                    }
                }

                TextButton {
                    variant: TextButton.Outlined
                    symbol: "block"
                    text: "Отключить для трека"
                    enabled: trackIdField.text.trim().length > 0
                    onClicked: {
                        if (!root.modApi) return;
                        const id = trackIdField.text.trim();
                        const next = Object.assign({}, root.customOverrides);
                        next[id] = { disabled: true, title: titleField.text.trim() || ("Трек " + id) };
                        root.customOverrides = next;
                        root.modApi.storageSet("customOverrides", next);
                        root.modApi.showToast("Подмена из базы отключена для трека " + id);
                        trackIdField.text = "";
                        titleField.text = "";
                        artistField.text = "";
                        audioField.text = "";
                        coverField.text = "";
                    }
                }
            }
        }
    }

    ContentSection {
        title: "Сохранённые пользовательские правила"
        symbol: "list"
        visible: Object.keys(root.customOverrides).length > 0

        Column {
            x: 8
            width: parent.width - 16
            spacing: 6

            Repeater {
                model: Object.keys(root.customOverrides)

                delegate: Rectangle {
                    id: delegateItem
                    required property string modelData
                    readonly property var ov: root.customOverrides[modelData] || ({})
                    width: parent ? parent.width : 0
                    height: 54
                    radius: Theme.rounding.small
                    color: Theme.colors.surfaceContainer

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 10

                        RoundedImage {
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            Layout.alignment: Qt.AlignVCenter
                            source: delegateItem.ov.coverUrl || ""
                            radius: 8
                            fallbackSymbol: delegateItem.ov.disabled ? "block" : "graphic_eq"
                            fallbackIconSize: 18
                            maskColor: Theme.colors.surfaceContainer
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText {
                                Layout.fillWidth: true
                                text: (delegateItem.ov.title || "Трек") + " (" + delegateItem.modelData + ")"
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: delegateItem.ov.disabled
                                    ? "Подмена из базы отключена"
                                    : (delegateItem.ov.localFile || delegateItem.ov.audioUrl || (delegateItem.ov.audioTrackId ? ("trackId: " + delegateItem.ov.audioTrackId) : "Только метаданные"))
                                font.pixelSize: Theme.fontSize.smaller
                                color: delegateItem.ov.disabled ? Theme.colors.error : Theme.colors.onSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }

                        IconButton {
                            symbol: "edit"
                            size: 32
                            iconSize: 18
                            tooltip: "Редактировать"
                            visible: !delegateItem.ov.disabled
                            onClicked: root.loadOverrideIntoForm(delegateItem.modelData)
                        }

                        IconButton {
                            symbol: "delete"
                            size: 32
                            iconSize: 18
                            tooltip: "Удалить правило"
                            onClicked: {
                                const next = Object.assign({}, root.customOverrides);
                                delete next[delegateItem.modelData];
                                root.customOverrides = next;
                                if (root.modApi) {
                                    root.modApi.storageSet("customOverrides", next);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
