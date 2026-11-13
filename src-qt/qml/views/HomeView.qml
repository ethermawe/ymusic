import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ymusic.ui

Flickable {
    id: root

    contentHeight: homeColumn.y + homeColumn.implicitHeight + Appearance.sizes.playerBarClearance
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    readonly property int currentHour: new Date().getHours()
    readonly property string greetingText: currentHour < 5 ? "Доброй ночи"
                                         : (currentHour < 12 ? "Доброе утро"
                                         : (currentHour < 18 ? "Добрый день" : "Добрый вечер"))

    // Subtle organic stickers floating faintly in background (Swiftify style)
    Stickers {
        anchors.fill: parent
        opacity: 0.75
        z: 0
    }

    ColumnLayout {
        id: homeColumn
        y: Appearance.sizes.pageMargin
        width: parent.width
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Appearance.sizes.pageMargin
        spacing: Appearance.sizes.sectionGap
        z: 1

        // Header: Display Title (Swiftify style)
        TitleText {
            text: "Yandex Music"
            level: "display"
            color: Appearance.colors.onSurface
            Layout.topMargin: 4
        }

        // Spotlight Card: Now Playing Hero Card (Swiftify-inspired frosted card)
        Rectangle {
            id: spotlightCard
            Layout.fillWidth: true
            Layout.preferredHeight: 186
            radius: Appearance.rounding.large
            color: Appearance.colors.surfaceContainerLow
            clip: true
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            // Blurred luminous backdrop from artwork
            Image {
                id: backdropImage
                anchors.fill: parent
                visible: false
                source: appSettings.coversEnabled && backend.hasCover ? backend.nowCover : ""
                asynchronous: true
                sourceSize: Qt.size(64, 64)
                smooth: true
                mipmap: true
            }

            ShaderEffect {
                id: horizontalBlur
                width: 256
                height: 64
                property variant source: backdropImage
                property vector2d texelStep: Qt.vector2d(1 / 256, 0)
                fragmentShader: "qrc:/shaders/gaussian_blur.frag.qsb"
            }

            ShaderEffectSource {
                id: blurredTexture
                sourceItem: horizontalBlur
                hideSource: true
                visible: false
                textureSize: Qt.size(256, 64)
                smooth: true
                live: backdropImage.status === Image.Ready
            }

            ShaderEffect {
                anchors.fill: parent
                property variant source: blurredTexture
                property size itemSize: Qt.size(width, height)
                property real radius: spotlightCard.radius
                fragmentShader: "qrc:/shaders/artwork_backdrop.frag.qsb"
                opacity: 0.38
                visible: backdropImage.status === Image.Ready
            }

            // Spotlight Content
            RowLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 20

                // Cover Artwork with true rounded corners
                RoundedImage {
                    Layout.preferredWidth: 144
                    Layout.preferredHeight: 144
                    radius: Appearance.rounding.normal
                    source: backend.hasCover ? backend.nowCover : ""
                    fallbackSymbol: "music_note"
                    fallbackIconSize: 48
                    sourceSize.width: 288
                    sourceSize.height: 288
                    borderWidth: 1
                    borderColor: Qt.rgba(1, 1, 1, 0.08)
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
                        font.underline: homeTitleHover.hovered && backend.nowHasAlbum
                        HoverHandler {
                            id: homeTitleHover
                            cursorShape: backend.nowHasAlbum ? Qt.PointingHandCursor : Qt.ArrowCursor
                        }
                        TapHandler { enabled: backend.nowHasAlbum; onTapped: backend.openNowAlbum() }
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
                        font.underline: homeArtistHover.hovered && backend.nowHasArtist
                        HoverHandler { id: homeArtistHover; cursorShape: backend.nowHasArtist ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        TapHandler { enabled: backend.nowHasArtist; onTapped: backend.openNowArtist() }
                    }

                    // Action buttons
                    RowLayout {
                        spacing: 12
                        Layout.topMargin: 6

                        // Play Button with Swiftify softCookie / cookie9 shape
                        PlayHeroButton {
                            size: 42
                            playing: backend.playing
                            onClicked: {
                                if (backend.hasTrack) {
                                    backend.toggle();
                                } else {
                                    backend.startWave();
                                }
                            }
                        }

                        IconButton {
                            symbol: backend.nowLiked ? "favorite" : "favorite_border"
                            size: 38
                            iconSize: 20
                            iconColor: backend.nowLiked ? Appearance.colors.primary : Appearance.colors.onSurfaceVariant
                            toggled: backend.nowLiked
                            heartBurst: true
                            visible: backend.hasTrack
                            onClicked: backend.toggleNowLike()
                        }

                        TransportButton {
                            symbol: "skip_next"
                            effect: TransportButton.NudgeRight
                            size: 38
                            iconSize: 22
                            iconColor: Appearance.colors.onSurfaceVariant
                            visible: backend.hasTrack
                            onClicked: backend.next()
                        }

                        // Wavy Sound Wave running across the bottom of spotlight card
                        WavyLine {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredHeight: 10
                            wavelength: 22
                            amplitude: backend.playing && !Appearance.reduceMotion ? 2.8 : 0
                            running: backend.playing
                            opacity: backend.playing ? 1 : 0.45
                            Behavior on amplitude {
                                NumberAnimation { duration: Appearance.reduceMotion ? 0 : 420; easing.type: Easing.InOutCubic }
                            }
                            Behavior on opacity {
                                NumberAnimation { duration: Appearance.reduceMotion ? 0 : 300; easing.type: Easing.InOutCubic }
                            }
                            color: Qt.rgba(Appearance.colors.primary.r,
                                           Appearance.colors.primary.g,
                                           Appearance.colors.primary.b, 0.35)
                        }
                    }
                }
            }
        }

        // Two Shortcuts Side by Side (Swiftify HomeShortcut)
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
                symbol: "my_wave"
                badgeColor: Qt.rgba(Appearance.colors.secondary.r, Appearance.colors.secondary.g, Appearance.colors.secondary.b, 0.16)
                badgeIconColor: Appearance.colors.secondary
                onClicked: backend.startWave()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: backend.history.count > 0
            spacing: 12
            SectionHeader {
                Layout.fillWidth: true
                title: "Недавно слушали"
                symbol: "music_note"
                showsAction: true
                actionText: "Очистить"
                onActionClicked: clearHistory.open()
            }
            ListView {
                id: recent
                Layout.fillWidth: true
                Layout.preferredHeight: 104
                orientation: ListView.Horizontal
                spacing: 12
                clip: true
                model: backend.history
                delegate: Rectangle {
                    id: historyTile
                    required property var model
                    width: 240; height: 92
                    radius: 16
                    color: Appearance.colors.surfaceContainerLow
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 12; spacing: 12
                        RoundedImage { Layout.preferredWidth: 60; Layout.preferredHeight: 60; source: historyTile.model.coverUrl; radius: 12 }
                        ColumnLayout {
                            Layout.fillWidth: true
                            StyledText { Layout.fillWidth: true; text: historyTile.model.title; elide: Text.ElideRight; font.weight: Font.Medium }
                            StyledText { Layout.fillWidth: true; text: historyTile.model.artists; elide: Text.ElideRight; color: Appearance.colors.onSurfaceVariant }
                        }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: backend.feature({action: "play_history", id: historyTile.model.id}) }
                }
            }
        }

        // Recommendations Section with Swiftify SectionHeader and WavyLine
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 14

            SectionHeader {
                Layout.fillWidth: true
                title: "Ваши плейлисты и альбомы"
                symbol: "auto_awesome"
                showsAction: backend.cards.count > 0
                actionText: "Смотреть все"
                onActionClicked: backend.loadPlaylists()
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
                visible: count > 0

                delegate: CardItem {
                    width: 178
                    height: 238
                }
            }

            EmptyState {
                Layout.fillWidth: true
                Layout.preferredHeight: 180
                visible: backend.cards.count === 0
                symbol: "auto_awesome"
                title: "Подборки появятся здесь"
                description: "Музыка, плейлисты и альбомы из вашей библиотеки"
            }
        }
    }

    ScrollBar.vertical: ScrollBar { active: true }
    Dialog {
        id: clearHistory
        parent: Overlay.overlay
        anchors.centerIn: parent
        title: "Очистить историю прослушивания?"
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        onAccepted: backend.feature({action: "clear_history"})
    }
}
