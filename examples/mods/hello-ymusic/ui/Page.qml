import QtQuick
import QtQuick.Layouts
import ymusic.sdk 1.0

Item {
    id: root
    property var modApi: null
    property var slotContext: ({})

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 16

        TitleText {
            text: "Hello YMusic Mod"
        }

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Theme.colors.onSurfaceVariant
            text: "Это демонстрационная страница, загруженная с диска через слот sidebar.page."
        }

        Card {
            Layout.fillWidth: true
            implicitHeight: infoCol.implicitHeight + 32

            Column {
                id: infoCol
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                StyledText {
                    font.weight: Font.DemiBold
                    text: root.modApi && root.modApi.hasTrack
                        ? ("Сейчас играет: " + root.modApi.trackTitle + " — " + root.modApi.trackArtists)
                        : "Сейчас ничего не играет"
                }
                StyledText {
                    color: Theme.colors.onSurfaceVariant
                    text: "Треков переключено с этим модом: " + (root.modApi ? root.modApi.storageGet("playedCount", 0) : 0)
                }
                TextButton {
                    variant: TextButton.Tonal
                    symbol: "content_copy"
                    text: "Скопировать текущий трек"
                    enabled: root.modApi && root.modApi.hasTrack
                    onClicked: {
                        const line = root.modApi.trackArtists + " — " + root.modApi.trackTitle;
                        root.modApi.copyText(line);
                        root.modApi.showToast("Скопировано: " + line);
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
