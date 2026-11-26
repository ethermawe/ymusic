pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ymusic.ui

StyledDialog {
    id: root

    property string version: updater.currentVersion

    // Короткий список изменений по существу для каждой версии (4–6 пунктов).
    readonly property var notesByVersion: ({
        "0.3.0": [
            "Переключение качества звука (HQ / Lossless FLAC) на лету без потери позиции",
            "Выбор формата экспорта треков на ПК (MP3 / FLAC)",
            "Theme Studio, светлая тема «Моей волны» и вход по QR-коду",
            "Волны по альбомам и плейлистам, скрытые треки и Last.fm",
            "Система модов v2 (.ymmod, 28 слотов) и оптимизация CPU/RAM"
        ]
    })

    readonly property var items: {
        const list = notesByVersion[root.version];
        return Array.isArray(list) ? list : [];
    }

    preferredWidth: 420
    headline: "Обновление v" + root.version
    symbol: "new_releases"
    iconShape: "cookie9"

    onClosed: {
        if (root.version.length > 0 && appSettings.lastSeenVersion !== root.version) {
            appSettings.lastSeenVersion = root.version;
        }
    }

    Column {
        width: parent.width
        spacing: 8

        Repeater {
            model: root.items

            delegate: RowLayout {
                required property string modelData
                width: parent ? parent.width : 0
                spacing: 10

                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 7
                    Layout.preferredWidth: 6
                    Layout.preferredHeight: 6
                    radius: 3
                    color: Appearance.colors.primary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: modelData
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.fontSize.small
                    color: Appearance.colors.onSurface
                }
            }
        }
    }

    buttons: [
        TextButton {
            text: "Понятно"
            variant: TextButton.Filled
            onClicked: root.accept()
        },
        TextButton {
            text: "Подробнее"
            variant: TextButton.Text
            onClicked: {
                Qt.openUrlExternally("https://github.com/ethermawe/ymusic/releases/tag/v" + root.version);
                root.accept();
            }
        }
    ]
}
