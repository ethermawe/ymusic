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
    property string remoteStatus: modApi ? String(modApi.storageGet("remoteStatus", "Ожидание загрузки...")) : ""
    property var customOverrides: modApi ? (modApi.storageGet("customOverrides", ({})) || ({})) : ({})
    property int appliedCount: modApi ? Number(modApi.storageGet("appliedCount", 0)) : 0

    function syncFromStorage() {
        if (!modApi) return;
        useRemoteDb = Boolean(modApi.storageGet("useRemoteDb", true));
        remoteStatus = String(modApi.storageGet("remoteStatus", "Готово"));
        customOverrides = modApi.storageGet("customOverrides", ({})) || ({});
        appliedCount = Number(modApi.storageGet("appliedCount", 0));

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

    function reapplyNow() {
        if (!modApi) return;
        const merged = {};
        if (useRemoteDb) {
            const cached = modApi.storageGet("cachedRemoteOverrides", ({})) || ({});
            const rKeys = Object.keys(cached);
            for (let i = 0; i < rKeys.length; ++i) {
                merged[rKeys[i]] = Object.assign({}, cached[rKeys[i]]);
            }
        }
        const cKeys = Object.keys(customOverrides);
        for (let j = 0; j < cKeys.length; ++j) {
            const id = cKeys[j];
            const ov = customOverrides[id];
            if (!ov) continue;
            if (ov.disabled) delete merged[id];
            else merged[id] = Object.assign({}, merged[id] || {}, ov);
        }
        modApi.setTrackOverrides(merged);
        appliedCount = Object.keys(merged).length;
        modApi.storageSet("appliedCount", appliedCount);
    }

    Component.onCompleted: syncFromStorage()

    Connections {
        target: root.modApi
        function onHttpFinished(requestId) {
            if (requestId === "fck-censor-db") {
                Qt.callLater(root.syncFromStorage);
            }
        }
    }

    ContentSection {
        title: "База подмен FckCensorData"
        symbol: "graphic_eq"

        ConfigSwitch {
            text: "Автоматические подмены из FckCensorData"
            checked: root.useRemoteDb
            onToggledTo: (checked) => {
                root.useRemoteDb = checked;
                if (root.modApi) {
                    root.modApi.storageSet("useRemoteDb", checked);
                    root.reapplyNow();
                }
            }
        }

        NoteText {
            text: root.remoteStatus + " · Активно подмен: " + root.appliedCount
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
                    root.remoteStatus = "Обновление базы...";
                    root.modApi.httpGet("https://raw.githubusercontent.com/Hazzz895/FckCensorData/main/list_v2.json", "fck-censor-db");
                    root.modApi.showToast("Запрос на обновление базы отправлен");
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

            Row {
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
                        root.reapplyNow();
                        root.modApi.showToast("Подмена для трека " + id + " сохранена");
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
        title: "Сохранённые пользовательские подмены"
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
                    height: 48
                    radius: Theme.rounding.small
                    color: Theme.colors.surfaceContainer

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 8
                        spacing: 10

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
                                text: delegateItem.ov.localFile || delegateItem.ov.audioUrl || (delegateItem.ov.audioTrackId ? ("trackId: " + delegateItem.ov.audioTrackId) : "Только метаданные")
                                font.pixelSize: Theme.fontSize.smaller
                                color: Theme.colors.onSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }

                        IconButton {
                            symbol: "delete"
                            size: 32
                            iconSize: 18
                            tooltip: "Удалить подмену"
                            onClicked: {
                                const next = Object.assign({}, root.customOverrides);
                                delete next[delegateItem.modelData];
                                root.customOverrides = next;
                                if (root.modApi) {
                                    root.modApi.storageSet("customOverrides", next);
                                    root.reapplyNow();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
