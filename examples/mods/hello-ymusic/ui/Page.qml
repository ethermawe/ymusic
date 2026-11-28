import QtQuick
import QtQuick.Layouts
import ymusic.sdk 1.0

Item {
    id: root
    property var modApi: null
    property var slotContext: ({})

    property int playedCount: modApi ? Number(modApi.storageGet("playedCount", 0)) : 0
    property string lastTrackTitle: modApi ? String(modApi.storageGet("lastTrackTitle", "") || "") : ""
    property var energies: [0.1, 0.2, 0.3, 0.2, 0.1]

    function refreshStats() {
        if (!root.modApi) return;
        const stats = root.modApi.call("getStats");
        if (stats && typeof stats === "object" && stats.playedCount !== undefined) {
            root.playedCount = Number(stats.playedCount) || 0;
            root.lastTrackTitle = String(stats.lastTrackTitle || "");
        } else {
            root.playedCount = Number(root.modApi.storageGet("playedCount", 0)) || 0;
            root.lastTrackTitle = String(root.modApi.storageGet("lastTrackTitle", "") || "");
        }
    }

    Component.onCompleted: refreshStats()

    Connections {
        target: root.modApi
        function onStorageChanged(key) {
            if (key === "playedCount" || key === "lastTrackTitle") {
                root.refreshStats();
            }
        }
        function onShortcutTriggered(actionId) {
            if (actionId === "copy_current" && root.modApi && root.modApi.hasTrack) {
                const line = root.modApi.trackArtists + " — " + root.modApi.trackTitle;
                root.modApi.copyText(line);
                root.modApi.showToast("Скопировано: " + line);
            }
        }
    }

    Connections {
        target: root.modApi
        enabled: root.visible && !Theme.performanceMode && root.modApi !== null
        function onSpectrumUpdated() {
            const e = root.modApi.spectrumEnergies();
            if (e && e.length >= 5) root.energies = e;
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: contentCol.implicitHeight + 56
        clip: true

        ColumnLayout {
            id: contentCol
            x: 28
            y: 28
            width: Math.min(720, Math.max(320, root.width - 56))
            spacing: 20

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                TitleText {
                    text: "Hello YMusic Mod"
                }

                Badge {
                    symbol: "auto_awesome"
                    text: "SDK 1.0"
                    tone: "primary"
                }

                Badge {
                    symbol: "history"
                    text: "Треков: " + root.playedCount
                    tone: "secondary"
                }

                Item { Layout.fillWidth: true }
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Theme.colors.onSurfaceVariant
                text: "Эталонный пример мода: страница в sidebar.page, логика в main.js (хук track_after_play + ym.ui.expose) и компоненты ymusic.sdk 1.0."
            }

            // Now Playing card using RoundedImage, SpectrumBars, StyledSlider, IconButton
            Card {
                Layout.fillWidth: true
                implicitHeight: playerCol.implicitHeight + 32

                ColumnLayout {
                    id: playerCol
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 14

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14

                        RoundedImage {
                            Layout.preferredWidth: 64
                            Layout.preferredHeight: 64
                            source: root.modApi ? root.modApi.trackCover : ""
                            radius: 14
                            fallbackSymbol: "music_note"
                            maskColor: Theme.colors.surfaceContainer
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            StyledText {
                                Layout.fillWidth: true
                                font.pixelSize: Theme.fontSize.large
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                text: root.modApi && root.modApi.hasTrack
                                    ? root.modApi.trackTitle
                                    : "Сейчас ничего не играет"
                            }

                            StyledText {
                                Layout.fillWidth: true
                                color: Theme.colors.onSurfaceVariant
                                elide: Text.ElideRight
                                text: root.modApi && root.modApi.hasTrack
                                    ? root.modApi.trackArtists
                                    : "Включите трек, чтобы проверить управление"
                            }

                            SpectrumBars {
                                Layout.topMargin: 4
                                energies: root.energies
                                active: root.modApi ? root.modApi.playing : false
                                barCount: 5
                                maxHeight: 14
                            }
                        }

                        IconButton {
                            symbol: "favorite"
                            iconColor: (root.modApi && root.modApi.trackLiked)
                                ? Theme.colors.primary
                                : Theme.colors.onSurfaceVariant
                            tooltip: "Нравится"
                            enabled: root.modApi && root.modApi.hasTrack
                            onClicked: if (root.modApi) root.modApi.toggleLike()
                        }
                    }

                    // Transport + volume slider
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        IconButton {
                            symbol: "shuffle"
                            iconColor: (root.modApi && root.modApi.shuffle) ? Theme.colors.primary : Theme.colors.onSurfaceVariant
                            tooltip: "Перемешать"
                            onClicked: if (root.modApi) root.modApi.toggleShuffle()
                        }
                        IconButton {
                            symbol: "skip_previous"
                            tooltip: "Предыдущий"
                            onClicked: if (root.modApi) root.modApi.prev()
                        }
                        IconButton {
                            symbol: (root.modApi && root.modApi.playing) ? "pause" : "play_arrow"
                            iconColor: Theme.colors.primary
                            tooltip: "Пауза / Играть"
                            onClicked: if (root.modApi) root.modApi.toggle()
                        }
                        IconButton {
                            symbol: "skip_next"
                            tooltip: "Следующий"
                            onClicked: if (root.modApi) root.modApi.next()
                        }
                        IconButton {
                            symbol: (root.modApi && root.modApi.repeatMode === 2) ? "repeat_one" : "repeat"
                            iconColor: (root.modApi && root.modApi.repeatMode > 0) ? Theme.colors.primary : Theme.colors.onSurfaceVariant
                            tooltip: "Повтор"
                            onClicked: if (root.modApi) root.modApi.toggleRepeat()
                        }

                        Item { Layout.preferredWidth: 8 }

                        IconButton {
                            symbol: (root.modApi && root.modApi.muted) ? "volume_off" : "volume_up"
                            tooltip: "Без звука"
                            onClicked: if (root.modApi) root.modApi.toggleMute()
                        }

                        StyledSlider {
                            Layout.fillWidth: true
                            value: root.modApi ? root.modApi.volume : 0.5
                            onMoved: (v) => { if (root.modApi) root.modApi.setVolume(v); }
                        }
                    }

                    // Quick action chips
                    Flow {
                        Layout.fillWidth: true
                        spacing: 8

                        Chip {
                            symbol: "content_copy"
                            text: "Скопировать трек"
                            enabled: root.modApi && root.modApi.hasTrack
                            onClicked: {
                                const line = root.modApi.trackArtists + " — " + root.modApi.trackTitle;
                                root.modApi.copyText(line);
                                root.modApi.showToast("Скопировано: " + line);
                            }
                        }

                        Chip {
                            symbol: "person"
                            text: "Открыть артиста"
                            enabled: root.modApi && root.modApi.hasTrack
                            onClicked: if (root.modApi) root.modApi.openNowArtist()
                        }

                        Chip {
                            symbol: "restart_alt"
                            text: "Сбросить счётчик"
                            onClicked: {
                                if (!root.modApi) return;
                                root.modApi.call("resetStats");
                                root.refreshStats();
                                root.modApi.showToast("Счётчик сброшен");
                            }
                        }
                    }
                }
            }
        }
    }
}
