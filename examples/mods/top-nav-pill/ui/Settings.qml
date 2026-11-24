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
        text: "Настройка компактной верхней панели навигации. Правый клик по иконке «Плейлисты» открывает закреплённые плейлисты и создание нового."
        color: Appearance.colors.onSurfaceVariant
    }

    Row {
        spacing: 10
        TextButton {
            variant: (root.modApi && Boolean(root.modApi.storageGet("showLabels", false))) ? TextButton.Outlined : TextButton.Filled
            text: "Только иконки"
            onClicked: {
                if (root.modApi) {
                    root.modApi.storageSet("showLabels", false);
                    ModManager.reloadMods();
                }
            }
        }
        TextButton {
            variant: (root.modApi && Boolean(root.modApi.storageGet("showLabels", false))) ? TextButton.Filled : TextButton.Outlined
            text: "Иконки + подписи"
            onClicked: {
                if (root.modApi) {
                    root.modApi.storageSet("showLabels", true);
                    ModManager.reloadMods();
                }
            }
        }
    }
}
