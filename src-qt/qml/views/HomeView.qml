import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Effects
import ymusic.ui

Flickable {
    id: root

    contentHeight: homeColumn.implicitHeight + Appearance.sizes.playerBarClearance
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    readonly property int currentHour: new Date().getHours()
    readonly property string greetingText: currentHour < 5 ? "Доброй ночи"
                                         : (currentHour < 12 ? "Доброе утро"
                                         : (currentHour < 18 ? "Добрый день" : "Добрый вечер"))

    ColumnLayout {
        id: homeColumn
        width: parent.width
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Appearance.sizes.pageMargin
        spacing: Appearance.sizes.sectionGap

        // Header: Greeting + Title
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            RowLayout {
                spacing: 8
                MaterialSymbol {
                    text: root.currentHour < 5 ? "nightlight"
                        : (root.currentHour < 18 ? "wb_sunny" : "nightlight")
                    iconSize: 20
                    color: Appearance.colors.primary
                }

                StyledText {
                    text: root.greetingText + (backend.loggedIn && backend.userName.length > 0 ? ", " + backend.userName : "")
                    font.pixelSize: Appearance.fontSize.large
                    font.weight: Font.DemiBold
                    color: Appearance.colors.onSurfaceVariant
                }
            }

            TitleText {
                text: "Yandex Music"
                level: "display"
                color: Appearance.colors.onSurface
            }
        }

        // Spotlight Card: Now Playing Hero Card
        Rectangle {
            id: spotlightCard
            Layout.fillWidth: true
            Layout.preferredHeight: 180
            radius: Appearance.rounding.large
            color: Appearance.colors.surfaceContainerLow
            clip: true
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            // Blurred backdrop from artwork
            Item {
                id: blurSource
                anchors.fill: parent
                visible: false
                layer.enabled: true

                Image {
                    anchors.fill: parent
                    source: backend.hasCover ? backend.nowCover : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 64
                    sourceSize.height: 64
                    visible: backend.hasCover
                }
            }

            MultiEffect {
                anchors.fill: parent
                source: blurSource
                blurEnabled: true
                blur: 1.0
                blurMax: 48
                saturation: 0.3
                opacity: 0.35
                visible: backend.hasCover
            }

            // Spotlight Content
            RowLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 20

                // Cover Artwork
                Rectangle {
                    Layout.preferredWidth: 140
                    Layout.preferredHeight: 140
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.surfaceContainerHighest
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: backend.hasCover ? backend.nowCover : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        sourceSize.width: 280
                        sourceSize.height: 280
                        visible: backend.hasCover
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "music_note"
                        iconSize: 48
                        color: Appearance.colors.onSurfaceVariant
                        visible: !backend.hasCover
                    }
                }

                // Info & Controls
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 6

                    // Tag
                    StyledText {
                        text: backend.hasTrack ? (backend.playing ? "СЕЙЧАС ИГРАЕТ" : "ПАУЗА") : "ПЕРСОНАЛЬНЫЙ ПОТОК"
                        font.pixelSize: Appearance.fontSize.smallest
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                        color: Appearance.colors.primary
                    }

                    // Title
                    TitleText {
                        Layout.fillWidth: true
                        text: backend.hasTrack ? backend.nowTitle : "Моя волна"
                        level: "headline"
                        elide: Text.ElideRight
                    }

                    // Artist & Album
                    StyledText {
                        Layout.fillWidth: true
                        text: backend.hasTrack
                              ? (backend.nowArtists + (backend.nowAlbum.length > 0 ? " • " + backend.nowAlbum : ""))
                              : "Бесконечный поток музыки под ваше настроение"
                        font.pixelSize: Appearance.fontSize.normal
                        font.weight: Font.Medium
                        color: Appearance.colors.onSurfaceVariant
                        elide: Text.ElideRight
                    }

                    // Action buttons
                    RowLayout {
                        spacing: 12
                        Layout.topMargin: 6

                        Rectangle {
                            height: 40
                            width: playBtnRow.implicitWidth + 28
                            radius: Appearance.rounding.full
                            color: playHeroMouse.containsMouse ? Appearance.colors.primaryHover : Appearance.colors.primary

                            RowLayout {
                                id: playBtnRow
                                anchors.centerIn: parent
                                spacing: 8

                                MaterialSymbol {
                                    text: backend.hasTrack ? (backend.playing ? "pause" : "play_arrow") : "auto_awesome"
                                    iconSize: 20
                                    color: Appearance.colors.onPrimary
                                }

                                StyledText {
                                    text: backend.hasTrack ? (backend.playing ? "Пауза" : "Слушать") : "Запустить волну"
                                    font.pixelSize: Appearance.fontSize.small
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.onPrimary
                                }
                            }

                            MouseArea {
                                id: playHeroMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (backend.hasTrack) {
                                        backend.toggle();
                                    } else {
                                        backend.startWave();
                                    }
                                }
                            }
                        }

                        IconButton {
                            symbol: backend.nowLiked ? "favorite" : "favorite_border"
                            size: 38
                            iconSize: 20
                            iconColor: backend.nowLiked ? Appearance.colors.primary : Appearance.colors.onSurfaceVariant
                            visible: backend.hasTrack
                            onClicked: backend.toggleNowLike()
                        }

                        IconButton {
                            symbol: "skip_next"
                            size: 38
                            iconSize: 22
                            iconColor: Appearance.colors.onSurfaceVariant
                            visible: backend.hasTrack
                            onClicked: backend.next()
                        }
                    }
                }
            }
        }

        // Two Shortcuts Side by Side
        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            HomeShortcut {
                Layout.fillWidth: true
                title: "Любимые треки"
                subtitle: "Понравившаяся вам музыка"
                symbol: "favorite"
                badgeColor: Qt.rgba(Appearance.colors.primary.r, Appearance.colors.primary.g, Appearance.colors.primary.b, 0.16)
                badgeIconColor: Appearance.colors.primary
                onClicked: backend.loadLikes()
            }

            HomeShortcut {
                Layout.fillWidth: true
                title: "Моя волна"
                subtitle: "Умные рекомендации потока"
                symbol: "auto_awesome"
                badgeColor: Qt.rgba(Appearance.colors.secondary.r, Appearance.colors.secondary.g, Appearance.colors.secondary.b, 0.16)
                badgeIconColor: Appearance.colors.secondary
                onClicked: backend.startWave()
            }
        }

        // Recommendations Section
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 14

            RowLayout {
                Layout.fillWidth: true

                TitleText {
                    text: "Ваша музыка и рекомендации"
                    level: "title"
                    Layout.fillWidth: true
                }
            }

            // Grid of recommendation cards
            GridView {
                id: homeCardsGrid
                Layout.fillWidth: true
                Layout.preferredHeight: Math.ceil(Math.max(1, count) / Math.max(1, Math.floor(width / cellWidth))) * cellHeight
                clip: true
                interactive: false
                cellWidth: 194
                cellHeight: 254
                reuseItems: true
                model: backend.cards

                delegate: CardItem {
                    width: 178
                    height: 238
                }
            }
        }
    }

    ScrollBar.vertical: ScrollBar { active: true }
}
