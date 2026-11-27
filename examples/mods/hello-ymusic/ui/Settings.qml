import QtQuick
import ymusic.sdk 1.0

Column {
    id: root
    property var modApi: null
    width: parent ? parent.width : 360
    spacing: 16

    property bool showImmersiveBadge: modApi ? Boolean(modApi.storageGet("showImmersiveBadge", true)) : true
    property int playedCount: modApi ? Number(modApi.storageGet("playedCount", 0)) : 0

    Connections {
        target: root.modApi
        function onStorageChanged(key) {
            if (!root.modApi) return;
            if (key === "showImmersiveBadge") root.showImmersiveBadge = Boolean(root.modApi.storageGet("showImmersiveBadge", true));
            if (key === "playedCount") root.playedCount = Number(root.modApi.storageGet("playedCount", 0));
        }
    }

    ContentSection {
        title: "Hello YMusic"
        symbol: "auto_awesome"

        ConfigSwitch {
            text: "Показывать мини-индикатор в полном экране"
            checked: root.showImmersiveBadge
            onToggledTo: (v) => {
                root.showImmersiveBadge = v;
                if (root.modApi) root.modApi.storageSet("showImmersiveBadge", v);
            }
        }

        NoteText {
            text: "Настройки сохраняются в изолированном файле mod-data/hello-ymusic.json. Зафиксировано треков: " + root.playedCount
        }

        Row {
            x: 12
            spacing: 8

            TextButton {
                variant: TextButton.Tonal
                symbol: "restart_alt"
                text: "Сбросить счётчик"
                onClicked: {
                    if (!root.modApi) return;
                    root.modApi.call("resetStats");
                    root.modApi.showToast("Счётчик сброшен");
                }
            }
        }
    }
}
