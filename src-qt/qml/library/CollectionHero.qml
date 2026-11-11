import QtQuick
import QtQuick.Layouts
import ymusic.ui

Item {
    id: root

    property string title: backend.listTitle
    property string subtitle: backend.listSubtitle
    property bool isArtist: backend.isArtistView

    implicitHeight: 180
    implicitWidth: 600

    RowLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 20

        // Hero Artwork with glow
        Item {
            Layout.preferredWidth: 140
            Layout.preferredHeight: 140
            Layout.alignment: Qt.AlignVCenter

            // Soft glow behind artwork
            Rectangle {
                anchors.centerIn: parent
                width: parent.width + 12
                height: parent.height + 12
                radius: root.isArtist ? width / 2 : Appearance.rounding.normal
                color: Appearance.colors.primary
                opacity: 0.18
            }

            Rectangle {
                id: artworkContainer
                anchors.fill: parent
                radius: root.isArtist ? width / 2 : Appearance.rounding.normal
                color: Appearance.colors.surfaceContainerHighest
                clip: true

                Image {
                    anchors.fill: parent
                    source: root.isArtist
                            ? (backend.artistHasAvatar ? backend.artistAvatar : "")
                            : (backend.hasCover ? backend.nowCover : "")
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    visible: root.isArtist ? backend.artistHasAvatar : backend.hasCover
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.isArtist ? "person" : (backend.page === 2 ? "auto_awesome" : "album")
                    iconSize: 56
                    color: Appearance.colors.onSurfaceVariant
                    visible: root.isArtist ? !backend.artistHasAvatar : !backend.hasCover
                }
            }
        }

        // Details
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 6

            // Kind Chip
            Rectangle {
                height: 22
                width: kindText.implicitWidth + 14
                radius: Appearance.rounding.full
                color: Qt.rgba(Appearance.colors.primary.r, Appearance.colors.primary.g, Appearance.colors.primary.b, 0.15)

                Text {
                    id: kindText
                    anchors.centerIn: parent
                    text: root.isArtist ? "АРТИСТ" : (backend.page === 2 ? "ПОТОК" : (backend.page === 1 ? "ИЗБРАННОЕ" : "КОЛЛЕКЦИЯ"))
                    color: Appearance.colors.primary
                    font.pixelSize: Appearance.fontSize.smallest
                    font.weight: Font.Bold
                    font.capitalization: Font.AllUppercase
                }
            }

            // Big Title
            Text {
                text: root.isArtist ? backend.artistName : root.title
                color: Appearance.colors.onSurface
                font.pixelSize: 26
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
                topPadding: 4

                // Play first track or Wave
                PlayHeroButton {
                    size: 40
                    playing: backend.playing
                    onClicked: {
                        if (backend.tracks && backend.tracks.rowCount() > 0) {
                            backend.play(0);
                        } else {
                            backend.toggle();
                        }
                    }
                }

                // Start Artist Wave button (if artist)
                Rectangle {
                    visible: root.isArtist && backend.canStartArtistWave
                    height: 40
                    width: waveRow.implicitWidth + 24
                    radius: Appearance.rounding.full
                    color: waveHover.containsMouse ? Appearance.colors.surfaceContainerHighest : Appearance.colors.surfaceContainerHigh
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.1)

                    RowLayout {
                        id: waveRow
                        anchors.centerIn: parent
                        spacing: 8

                        MaterialSymbol {
                            text: "auto_awesome"
                            iconSize: 18
                            color: Appearance.colors.primary
                        }

                        Text {
                            text: "Моя волна по артисту"
                            color: Appearance.colors.onSurface
                            font.pixelSize: Appearance.fontSize.small
                            font.weight: Font.Medium
                        }
                    }

                    MouseArea {
                        id: waveHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: backend.startArtistWave()
                    }
                }
            }
        }
    }
}
