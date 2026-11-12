import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ymusic.ui

Item {
    id: root

    signal closeRequested()

    focus: visible
    Keys.onEscapePressed: root.closeRequested()

    // Deep dark backdrop
    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.background

        // Soft radial/gradient glow from primary accent
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.7
            height: parent.height * 0.7
            radius: width / 2
            color: Appearance.colors.primary
            opacity: 0.08
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }
    }

    // Top Header with Close Button
    RowLayout {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 24
        height: 48

        Text {
            text: "СЕЙЧАС ИГРАЕТ"
            color: Appearance.colors.onSurfaceVariant
            font.pixelSize: Appearance.fontSize.smallest
            font.weight: Font.Bold
            font.letterSpacing: 1.5
            Layout.fillWidth: true
        }

        IconButton {
            symbol: "close"
            size: 40
            iconSize: 22
            onClicked: root.closeRequested()
        }
    }

    // Main content: Left (Artwork + Controls), Right (Queue List)
    RowLayout {
        anchors.fill: parent
        anchors.topMargin: 70
        anchors.bottomMargin: 40
        anchors.leftMargin: 40
        anchors.rightMargin: 40
        spacing: 48

        // Left: Player Core
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.maximumWidth: 460
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            spacing: 24

            // Large Artwork
            Item {
                Layout.preferredWidth: 300
                Layout.preferredHeight: 300
                Layout.alignment: Qt.AlignHCenter

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 24
                    height: parent.height + 24
                    radius: Appearance.rounding.veryLarge
                    color: Appearance.colors.primary
                    opacity: 0.2
                }

                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.large
                    color: Appearance.colors.surfaceContainerHighest
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: appSettings.coversEnabled && backend.hasCover ? backend.nowCover : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        visible: backend.hasCover
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "music_note"
                        iconSize: 72
                        color: Appearance.colors.onSurfaceVariant
                        visible: !backend.hasCover
                    }
                }
            }

            // Track info
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                spacing: 6

                Text {
                    text: backend.hasTrack ? backend.nowTitle : "Ничего не играет"
                    color: Appearance.colors.onSurface
                    font.pixelSize: 24
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    font.underline: immersiveTitleHover.hovered && backend.nowHasAlbum
                    HoverHandler {
                        id: immersiveTitleHover
                        cursorShape: backend.nowHasAlbum ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                    TapHandler {
                        enabled: backend.nowHasAlbum
                        onTapped: { backend.openNowAlbum(); root.closeRequested(); }
                    }
                }

                Text {
                    text: backend.nowArtists
                    color: Appearance.colors.onSurfaceVariant
                    font.pixelSize: Appearance.fontSize.normal
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    font.underline: immersiveArtistHover.hovered && backend.nowHasArtist
                    HoverHandler { id: immersiveArtistHover; cursorShape: backend.nowHasArtist ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler {
                        enabled: backend.nowHasArtist
                        onTapped: { backend.openNowArtist(); root.closeRequested(); }
                    }
                }
            }

            // Progress Slider
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                StyledSlider {
                    Layout.fillWidth: true
                    value: backend.progress
                    animatedWave: true
                    playing: backend.playing
                    trackHeight: 6
                    activeTrackHeight: 8
                    onUserSeek: (fraction) => backend.seek(fraction)
                }

                RowLayout {
                    Layout.fillWidth: true

                    RollingText {
                        text: backend.positionText
                        color: Appearance.colors.onSurfaceVariant
                        pixelSize: Appearance.fontSize.smallest
                    }

                    Item { Layout.fillWidth: true }

                    RollingText {
                        text: backend.durationText
                        color: Appearance.colors.onSurfaceVariant
                        pixelSize: Appearance.fontSize.smallest
                    }
                }
            }

            // Transport Controls
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 16

                TransportButton {
                    symbol: "shuffle"
                    effect: TransportButton.Bounce
                    size: 44
                    iconSize: 22
                    toggled: backend.shuffle
                    onClicked: backend.toggleShuffle()
                }

                TransportButton {
                    symbol: "skip_previous"
                    effect: TransportButton.NudgeLeft
                    size: 48
                    iconSize: 28
                    onClicked: backend.prev()
                }

                PlayHeroButton {
                    size: 58
                    playing: backend.playing
                    onClicked: backend.toggle()
                }

                TransportButton {
                    symbol: "skip_next"
                    effect: TransportButton.NudgeRight
                    size: 48
                    iconSize: 28
                    onClicked: backend.next()
                }

                TransportButton {
                    symbol: backend.repeatMode === 2 ? "repeat_one" : "repeat"
                    effect: TransportButton.Bounce
                    size: 44
                    iconSize: 22
                    toggled: backend.repeatMode !== 0
                    onClicked: backend.toggleRepeat()
                }

                IconButton {
                    symbol: backend.nowLiked ? "favorite" : "favorite_border"
                    size: 44
                    iconSize: 24
                    iconColor: backend.nowLiked ? Appearance.colors.primary : Appearance.colors.onSurface
                    activeIconColor: Appearance.colors.primary
                    toggled: backend.nowLiked
                    onClicked: backend.toggleNowLike()
                }
            }
        }

        // Right: Queue List
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 320
            radius: Appearance.rounding.large
            color: Appearance.colors.surfaceContainerLow
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.06)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                    text: "ОЧЕРЕДЬ · " + backend.queue.count
                    color: Appearance.colors.onSurfaceVariant
                    font.pixelSize: Appearance.fontSize.smallest
                    font.weight: Font.Bold
                    font.letterSpacing: 1.2
                    Layout.fillWidth: true
                    }
                    StyledButton { text: "Очистить"; onClicked: backend.feature({action: "queue", operation: "clear"}) }
                    IconButton {
                        symbol: "play_arrow"
                        tooltip: "Показать текущий трек"
                        onClicked: queueList.positionViewAtIndex(backend.queue.currentIndex, ListView.Center)
                    }
                }

                ListView {
                    id: queueList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: backend.queue
                    delegate: TrackRow {
                        width: queueList.width
                        queueView: true
                    }

                    ScrollBar.vertical: ScrollBar {
                        active: true
                    }
                }
            }
        }
    }
}
