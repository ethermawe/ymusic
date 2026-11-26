import QtQuick
import QtQuick.Layouts
import ymusic.sdk 1.0

Item {
    id: root
    property var modApi: null
    property var slotContext: ({})
    property int totalPlays: modApi ? Number(modApi.storageGet("totalPlays", 0)) : 0
    property string lastTrack: modApi ? String(modApi.storageGet("lastTrack", "")) : ""

    Connections {
        target: root.modApi
        function onStorageChanged() {
            if (!root.modApi) return;
            root.totalPlays = Number(root.modApi.storageGet("totalPlays", 0));
            root.lastTrack = String(root.modApi.storageGet("lastTrack", ""));
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 16

        TitleText { text: "Статистика прослушиваний" }

        Card {
            Layout.fillWidth: true
            implicitHeight: col.implicitHeight + 32

            Column {
                id: col
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                StyledText {
                    font.weight: Font.DemiBold
                    text: "Всего прослушано треков: " + root.totalPlays
                }
                StyledText {
                    color: Theme.colors.onSurfaceVariant
                    text: root.lastTrack.length > 0 ? ("Последний трек: " + root.lastTrack) : "Пока нет записей"
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
