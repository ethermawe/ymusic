import QtQuick
import ymusic.ui

Column {
    id: root
    property var modApi: null
    width: parent ? parent.width : 360
    spacing: 12

    StyledText {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Настройки демонстрационного мода сохраняются в изолированном JSON-файле mod-data/hello-ymusic.json."
        color: Appearance.colors.onSurfaceVariant
    }

    Row {
        spacing: 10
        TextButton {
            variant: TextButton.Tonal
            symbol: "restart_alt"
            text: "Сбросить счётчик треков"
            onClicked: {
                if (root.modApi) {
                    root.modApi.storageSet("playedCount", 0);
                    root.modApi.showToast("Счётчик сброшен");
                }
            }
        }
    }
}
