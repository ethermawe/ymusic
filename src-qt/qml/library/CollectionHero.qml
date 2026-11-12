import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ymusic.ui

Item {
    id: root

    property string title: backend.listTitle
    property string subtitle: backend.listSubtitle
    property bool isArtist: backend.isArtistView

    implicitHeight: 200
    implicitWidth: 600

    RowLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 24

        // Hero Artwork with dual glowing backdrop
        Item {
            Layout.preferredWidth: 152
            Layout.preferredHeight: 152
            Layout.alignment: Qt.AlignVCenter

            // Dual soft glow layers behind artwork (inspired by Swiftify ArtworkGlow)
            Rectangle {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: -4
                anchors.verticalCenterOffset: 6
                width: parent.width + 16
                height: parent.height + 16
                radius: root.isArtist ? width / 2 : Appearance.rounding.normal
                color: Appearance.colors.primary
                opacity: 0.22
            }

            Rectangle {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: 4
                anchors.verticalCenterOffset: -2
                width: parent.width + 8
                height: parent.height + 8
                radius: root.isArtist ? width / 2 : Appearance.rounding.normal
                color: Appearance.colors.primaryContainer
                opacity: 0.18
            }

            RoundedImage {
                id: artworkContainer
                anchors.fill: parent
                radius: root.isArtist ? width / 2 : Appearance.rounding.normal
                source: root.isArtist
                        ? (backend.artistHasAvatar ? backend.artistAvatar : "")
                        : backend.listCover
                fallbackSymbol: root.isArtist ? "artists" : (backend.page === 1 ? "my_wave" : (backend.page === 2 ? "favorite" : "album"))
                fallbackIconSize: 64
                sourceSize.width: 320
                sourceSize.height: 320
                borderWidth: 1
                borderColor: Qt.rgba(1, 1, 1, 0.08)
            }
        }

        // Details Column
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 8

            // Kind Chip
            Rectangle {
                Layout.preferredHeight: 24
                Layout.preferredWidth: kindRow.implicitWidth + 20
                radius: Appearance.rounding.full
                color: Appearance.colors.primaryContainer

                RowLayout {
                    id: kindRow
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialSymbol {
                        text: root.isArtist ? "artists" : (backend.page === 1 ? "my_wave" : (backend.page === 2 ? "favorite" : "album"))
                        iconSize: 14
                        color: Appearance.colors.onPrimaryContainer
                    }

                    Text {
                        text: backend.page === 7 ? "НА УСТРОЙСТВЕ" : (root.isArtist ? "АРТИСТ" : (backend.page === 1 ? "ВОЛНА" : (backend.page === 2 ? "ИЗБРАННОЕ" : "КОЛЛЕКЦИЯ")))
                        color: Appearance.colors.onPrimaryContainer
                        font.pixelSize: Appearance.fontSize.smallest
                        font.weight: Font.Bold
                        font.capitalization: Font.AllUppercase
                    }
                }
            }

            // Big Title
            TitleText {
                text: root.isArtist ? backend.artistName : root.title
                color: Appearance.colors.onSurface
                font.pixelSize: 32
                font.weight: Font.Bold
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            // Subtitle / Genres / Stats
            Text {
                text: root.isArtist
                      ? (backend.artistGenres + (backend.artistStats.length > 0 ? " • " + backend.artistStats : ""))
                      : root.subtitle
                color: Appearance.colors.onSurfaceVariant
                font.pixelSize: Appearance.fontSize.small
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            // Action Buttons
            Row {
                spacing: 12
                topPadding: 6

                // Play Hero Button
                PlayHeroButton {
                    size: 44
                    playing: backend.playing && backend.tracks.currentIndex >= 0
                    onClicked: {
                        if (backend.tracks.currentIndex >= 0) {
                            backend.toggle();
                        } else if (backend.tracks.count > 0) {
                            backend.play(0);
                        }
                    }
                }

                // Start Artist Wave button (if artist)
                StyledButton {
                    visible: backend.collectionDownloadable
                    enabled: !backend.listLoading && !backend.batch.running
                    text: "Скачать всё"
                    onClicked: backend.feature({action: "download_collection"})
                }

                Rectangle {
                    visible: root.isArtist && backend.canStartArtistWave
                    height: 44
                    width: waveRow.implicitWidth + 28
                    radius: Appearance.rounding.full
                    color: waveHover.hovered ? Appearance.colors.surfaceContainerHighest : Appearance.colors.surfaceContainerHigh
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.1)

                    scale: waveMouse.pressed ? 0.96 : (waveHover.hovered ? 1.02 : 1.0)
                    Behavior on scale { Bounce {} }
                    Behavior on color { ElementMoveFastColor {} }

                    RowLayout {
                        id: waveRow
                        anchors.centerIn: parent
                        spacing: 8

                        MaterialSymbol {
                            text: "my_wave"
                            iconSize: 20
                            color: Appearance.colors.primary
                        }

                        Text {
                            text: "Моя волна по артисту"
                            color: Appearance.colors.onSurface
                            font.pixelSize: Appearance.fontSize.small
                            font.weight: Font.Medium
                        }
                    }

                    HoverHandler {
                        id: waveHover
                    }

                    MouseArea {
                        id: waveMouse
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: backend.startArtistWave()
                    }
                }
            }
        }
    }
}
