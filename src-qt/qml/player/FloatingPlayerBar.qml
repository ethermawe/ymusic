import QtQuick
import QtQuick.Layouts
import ymusic.ui

Item {
    id: root

    signal immersiveRequested()

    implicitHeight: 72
    implicitWidth: 800

    // Elevated surface capsule matching Swiftify
    Rectangle {
        id: surface
        anchors.fill: parent
        radius: Appearance.rounding.large
        color: Appearance.colors.surfaceContainerHigh
        border.width: 1
        border.color: Qt.rgba(Appearance.colors.outlineVariant.r,
                              Appearance.colors.outlineVariant.g,
                              Appearance.colors.outlineVariant.b, 0.4)

        // Drop shadow / soft ambient blur
        Rectangle {
            anchors.centerIn: parent
            width: parent.width + 4
            height: parent.height + 6
            radius: parent.radius
            z: -1
            color: "#000000"
            opacity: 0.28
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            hoverEnabled: true
            onWheel: (wheel) => {
                if (wheel.angleDelta.y > 0) {
                    backend.setVolume(Math.min(1.0, backend.volume + 0.05));
                } else if (wheel.angleDelta.y < 0) {
                    backend.setVolume(Math.max(0.0, backend.volume - 0.05));
                }
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 12

        // Left: Transport buttons
        Row {
            Layout.alignment: Qt.AlignVCenter
            spacing: 4

            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                symbol: "shuffle"
                size: 34
                iconSize: 18
                toggled: backend.shuffle
                onClicked: backend.toggleShuffle()
            }

            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                symbol: "skip_previous"
                size: 34
                iconSize: 22
                onClicked: backend.prev()
            }

            PlayHeroButton {
                anchors.verticalCenter: parent.verticalCenter
                size: 44
                playing: backend.playing
                onClicked: backend.toggle()
            }

            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                symbol: "skip_next"
                size: 34
                iconSize: 22
                onClicked: backend.next()
            }

            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                symbol: backend.repeatMode === 2 ? "repeat_one" : "repeat"
                size: 34
                iconSize: 18
                toggled: backend.repeatMode !== 0
                onClicked: backend.toggleRepeat()
            }
        }

        // Center: Track Cover + Info + Seek bar
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            RowLayout {
                anchors.fill: parent
                spacing: 12

                // Artwork with hover zoom and pop spring
                Item {
                    id: artContainer
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    Layout.alignment: Qt.AlignVCenter

                    scale: artHover.containsMouse ? 1.12 : 1.0
                    Behavior on scale {
                        NumberAnimation {
                            duration: 220
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.8
                        }
                    }

                    transform: Scale {
                        id: popScale
                        origin.x: 22
                        origin.y: 22
                    }

                    Connections {
                        target: backend
                        function onNowIdChanged() {
                            popAnim.restart();
                        }
                    }

                    NumberAnimation {
                        id: popAnim
                        target: popScale
                        properties: "xScale,yScale"
                        from: 0.70
                        to: 1.0
                        duration: 420
                        easing.type: Easing.OutBack
                        easing.overshoot: 2.2
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.small
                        color: Appearance.colors.surfaceContainerHighest
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: backend.hasCover ? backend.nowCover : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            visible: backend.hasCover
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "music_note"
                            iconSize: 20
                            color: Appearance.colors.onSurfaceVariant
                            visible: !backend.hasCover
                        }

                        // Hover overlay icon indicating expand
                        Rectangle {
                            anchors.fill: parent
                            color: Qt.rgba(0, 0, 0, 0.35)
                            opacity: artHover.containsMouse ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 140 } }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "open_in_full"
                                iconSize: 18
                                color: "white"
                            }
                        }
                    }

                    MouseArea {
                        id: artHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.immersiveRequested()
                    }
                }

                // Title + Seek slider + Times
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 3

                    // Title + Artists
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: backend.hasTrack ? backend.nowTitle : "Ничего не воспроизводится"
                            color: Appearance.colors.onSurface
                            font.pixelSize: Appearance.fontSize.small
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            Layout.maximumWidth: 280
                        }

                        Text {
                            text: "•"
                            color: Appearance.colors.outline
                            font.pixelSize: Appearance.fontSize.smallest
                            visible: backend.hasTrack && backend.nowArtists.length > 0
                        }

                        Text {
                            text: backend.nowArtists
                            color: Appearance.colors.onSurfaceVariant
                            font.pixelSize: Appearance.fontSize.smaller
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            visible: backend.hasTrack
                        }
                    }

                    // Seek Slider + Timestamps
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: backend.positionText
                            color: Appearance.colors.onSurfaceVariant
                            font.pixelSize: Appearance.fontSize.smallest
                            font.family: "monospace"
                        }

                        StyledSlider {
                            Layout.fillWidth: true
                            value: backend.progress
                            trackHeight: 3
                            activeTrackHeight: 5
                            onUserSeek: (fraction) => backend.seek(fraction)
                        }

                        Text {
                            text: backend.durationText
                            color: Appearance.colors.onSurfaceVariant
                            font.pixelSize: Appearance.fontSize.smallest
                            font.family: "monospace"
                        }
                    }
                }
            }
        }

        // Right: Utilities (Like, Volume Pill, Immersive)
        Row {
            Layout.alignment: Qt.AlignVCenter
            spacing: 6

            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                symbol: backend.nowLiked ? "favorite" : "favorite_border"
                size: 34
                iconSize: 20
                iconColor: backend.nowLiked ? Appearance.colors.primary : Appearance.colors.onSurfaceVariant
                activeIconColor: Appearance.colors.primary
                toggled: backend.nowLiked
                onClicked: backend.toggleNowLike()
            }

            VolumeControl {
                anchors.verticalCenter: parent.verticalCenter
            }

            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                symbol: "open_in_full"
                size: 34
                iconSize: 18
                onClicked: root.immersiveRequested()
            }
        }
    }
}
