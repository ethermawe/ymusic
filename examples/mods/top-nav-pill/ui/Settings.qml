import QtQuick
import ymusic.sdk 1.0

Column {
    id: root
    property var modApi: null
    property bool showLabels: modApi ? Boolean(modApi.storageGet("showLabels", false)) : false
    width: parent ? parent.width : 360
    spacing: 12

    Connections {
        target: root.modApi
        function onStorageChanged(key) {
            if (key === "showLabels" && root.modApi) {
                root.showLabels = Boolean(root.modApi.storageGet("showLabels", false));
            }
        }
    }

    StyledText {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Настройка компактной верхней панели навигации. Правый клик по иконке «Плейлисты» открывает закреплённые плейлисты и создание нового."
        color: Theme.colors.onSurfaceVariant
    }

    Row {
        spacing: 10
        TextButton {
            variant: root.showLabels ? TextButton.Outlined : TextButton.Filled
            text: "Только иконки"
            onClicked: {
                if (root.modApi) {
                    root.showLabels = false;
                    root.modApi.storageSet("showLabels", false);
                }
            }
        }
        TextButton {
            variant: root.showLabels ? TextButton.Filled : TextButton.Outlined
            text: "Иконки + подписи"
            onClicked: {
                if (root.modApi) {
                    root.showLabels = true;
                    root.modApi.storageSet("showLabels", true);
                }
            }
        }
    }
}
