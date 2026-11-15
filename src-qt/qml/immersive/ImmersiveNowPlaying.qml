/*
 * Swiftify, a spotify player for desktop
 * Copyright (C) 2026  shred0s
 * Modified for ymusic (2026).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import ymusic.ui

Item {
    id: root

    required property ImmersiveLayout layout
    property real metadataWidth: 300
    property bool animateLayout: false
    property MaterialScheme scheme: PlayerStyle.darkScheme
    property real controlsOpacity: 1
    readonly property real controlsShift: compactHorizontal ? 0 : Math.round((transport.implicitHeight + volume.implicitHeight + details.spacing * 2) / 2)

    readonly property bool showsRing: appSettings.visualizersEnabled && appSettings.immersiveVisualizer && appSettings.circularVisualizer
    readonly property bool roundCover: showsRing || ((!appSettings.visualizersEnabled || !appSettings.immersiveVisualizer) && appSettings.roundArtwork)
    readonly property bool compactHorizontal: layout.contentHeight < 460
    readonly property real targetArtworkSize: compactHorizontal ? Math.min(240, Math.max(0, layout.contentHeight - 16), width * 0.36)
                                                               : layout.artworkSize
    property real artworkSize: targetArtworkSize
    readonly property real innerSize: showsRing ? artworkSize * ring.innerRadiusRatio : artworkSize
    readonly property real artworkRadius: Math.max(18, innerSize * 0.055)

    component Time: StyledText {
        tabularNumbers: true
        font.pixelSize: Appearance.fontSize.smallest + 1
        font.weight: Font.Medium
        color: Qt.rgba(1, 1, 1, 0.78)
        style: Text.Raised
        styleColor: Qt.rgba(0, 0, 0, 0.45)
    }

    component Control: TransportButton {
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        scheme: root.scheme
        size: root.compactHorizontal ? 36 : 40
        iconSize: 24
        fillWhenToggled: false
        iconColor: toggled ? root.scheme.primary : "white"
        colBackgroundHover: hasShape ? "transparent" : Qt.rgba(1, 1, 1, 0.1)
        colBackgroundToggled: "transparent"
        colBackgroundToggledHover: hasShape ? "transparent" : Qt.rgba(1, 1, 1, 0.1)
    }

    Behavior on artworkSize {
        enabled: root.animateLayout
        ElementMove {}
    }

    implicitWidth: compactHorizontal ? artworkSize + 24 + Math.max(220, details.implicitWidth)
                                     : Math.max(artworkSize, metadataWidth, transport.implicitWidth)
    implicitHeight: content.implicitHeight

    Item {
        id: content
        width: root.width
        implicitHeight: root.compactHorizontal ? Math.max(root.artworkSize, details.implicitHeight)
                                                : root.artworkSize + root.layout.contentSpacing + details.implicitHeight

        Item {
            id: artwork
            objectName: "immersiveArtwork"
            x: root.compactHorizontal ? 0 : (content.width - width) / 2
            y: root.compactHorizontal ? (content.height - height) / 2 : 0
            width: root.artworkSize
            height: root.artworkSize

            transform: Scale {
                id: pop
                origin.x: artwork.width / 2
                origin.y: artwork.height / 2
            }

            Connections {
                target: backend
                function onNowPlayingChanged() {
                    if (!Appearance.performanceMode) {
                        popIn.restart();
                    }
                }
            }
            NumberAnimation {
                id: popIn
                target: pop
                properties: "xScale,yScale"
                from: 0.9
                to: 1
                duration: 640
                easing.type: Easing.OutBack
                easing.overshoot: 2
            }

            ArtworkGlow {
                anchors.centerIn: parent
                width: root.innerSize
                height: root.innerSize
                intensity: 0.42
                glowRadius: 44
                cornerRadius: root.artworkRadius
                circular: root.roundCover
                primary: PlayerStyle.primary
                secondary: PlayerStyle.secondary
            }

            SpectrumView {
                id: ring
                anchors.fill: parent
                Reveal.shown: root.showsRing
                kind: SpectrumView.Ring
                wave: appSettings.visualizerShape === "wave"
                sensitivity: appSettings.visualizerSensitivity
                active: backend.playing && root.showsRing
                cutWaves: cover.showsSquiggle ? cover.squiggleWaves : 0
                cutRadius: cover.squiggleMiddle
                cutAmplitude: cover.squiggleAmplitude
                cutPhase: cover.squigglePhase
            }

            ArtworkImage {
                id: cover
                anchors.centerIn: parent
                width: root.innerSize
                height: root.innerSize
                radius: root.artworkRadius
                circular: root.roundCover
                squiggleFollowsPlayback: true
                squiggleColor: PlayerStyle.primary
                source: backend.hasCover ? backend.nowCover : ""
                placeholderSymbol: "music_note"
                fallbackKey: backend.nowTitle
                crossfade: true
                revealDuration: 360
            }
        }

        Column {
            id: details
            objectName: "immersiveDetails"
            x: root.compactHorizontal ? root.artworkSize + 24 : 0
            y: root.compactHorizontal ? (content.height - height) / 2 : root.artworkSize + root.layout.contentSpacing
            width: root.compactHorizontal ? Math.max(0, content.width - x) : content.width
            spacing: root.compactHorizontal ? 8 : root.layout.contentSpacing

            Column {
                id: metadata
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(root.metadataWidth, details.width)
                spacing: root.compactHorizontal ? 2 : 5

                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: PlayerStyle.primary
                    shadowOpacity: 0.14
                    shadowBlur: 1
                    blurMax: 18
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                }

                ScrollingText {
                    objectName: "immersiveTitle"
                    width: parent.width
                    height: root.compactHorizontal ? 48 : root.layout.titleHeight
                    text: backend.nowTitle
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: root.compactHorizontal ? 24 : root.layout.titleFontSize
                    font.weight: Font.Bold
                    color: "white"
                    rounded: true
                    animateChange: true
                }

                AiBadge {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: backend.hasTrack && backend.showAiLabels && backend.nowIsAi
                    scheme: root.scheme
                }

                Item {
                    id: artistLine
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width
                    implicitHeight: Math.max(artistLinks.implicitHeight, more.height, likeBtn.height, 28)

                    ArtistLinks {
                        id: artistLinks
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth + 2, parent.width - (more.width + likeBtn.width + 18))
                        horizontalAlignment: Text.AlignHCenter
                        links: backend.nowArtistLinks
                        fallbackText: backend.nowArtists
                        clickable: backend.hasTrack
                        fallbackClickable: backend.nowHasArtist
                        font.pixelSize: Appearance.fontSize.larger
                        font.weight: Font.Medium
                        color: Qt.rgba(1, 1, 1, 0.72)
                        onArtistActivated: UiState.immersiveOpen = false
                    }

                    IconButton {
                        id: likeBtn
                        anchors.right: artistLinks.left
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        scheme: root.scheme
                        symbol: "favorite"
                        toggled: backend.nowLiked
                        fillWhenToggled: true
                        burst: backend.nowLiked ? "" : "hearts"
                        size: 28
                        iconSize: 18
                        iconColor: backend.nowLiked ? root.scheme.primary : Qt.rgba(1, 1, 1, 0.62)
                        colBackgroundHover: Qt.rgba(1, 1, 1, 0.1)
                        tooltip: backend.nowLiked ? "Убрать из Мне нравится" : "Мне нравится"
                        opacity: root.controlsOpacity
                        enabled: root.controlsOpacity > 0 && backend.hasTrack
                        onClicked: backend.toggleNowLike()
                    }

                    IconButton {
                        id: more
                        anchors.left: artistLinks.right
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        scheme: root.scheme
                        symbol: "more_horiz"
                        size: 28
                        iconSize: 20
                        iconColor: Qt.rgba(1, 1, 1, 0.62)
                        colBackgroundHover: Qt.rgba(1, 1, 1, 0.1)
                        tooltip: "Действия с треком"
                        opacity: root.controlsOpacity
                        enabled: root.controlsOpacity > 0 && backend.hasTrack
                        onClicked: {
                            const appWin = root.Window.window;
                            const pt = more.mapToItem(appWin ? appWin.contentItem : null, more.width, more.height);
                            backend.requestTrackMenu(backend.nowId, backend.nowTitle, true, pt.x, pt.y);
                        }
                    }
                }

                ScrollingText {
                    width: parent.width
                    visible: backend.nowAlbum.length > 0
                    text: backend.nowAlbum
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.fontSize.smallie
                    color: Qt.rgba(1, 1, 1, 0.45)
                    animateChange: true
                }
            }

            Item {
                id: progress
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(details.width, root.compactHorizontal ? details.width : Math.max(320, root.artworkSize + 80))
                height: 18

                Time {
                    id: elapsed
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 42
                    horizontalAlignment: Text.AlignRight
                    text: Format.playbackTime(seek.displayPositionMs)
                }
                SeekBar {
                    id: seek
                    objectName: "immersiveSeek"
                    anchors.left: elapsed.right
                    anchors.leftMargin: 12
                    anchors.right: remainingTime.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    height: 18
                    scheme: root.scheme
                    followsCrossfade: true
                    activeColor: PlayerStyle.primary
                    trackColor: Qt.rgba(1, 1, 1, 0.2)
                }
                Time {
                    id: remainingTime
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 48
                    text: "−" + Format.playbackTime(Math.max(seek.durationMs - seek.displayPositionMs, 0))
                }
            }

            Row {
                id: transport
                objectName: "immersiveTransport"
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: root.compactHorizontal ? Math.max(8, Math.min(28, (details.width - 196) / 4)) : 28
                opacity: root.controlsOpacity
                enabled: root.controlsOpacity > 0

                Control {
                    effect: TransportButton.Bounce
                    symbol: "shuffle"
                    toggledShape: "clover4"
                    toggled: backend.shuffle
                    enabled: backend.hasTrack
                    tooltip: "Перемешать"
                    onClicked: backend.toggleShuffle()
                }
                Control {
                    effect: TransportButton.NudgeLeft
                    symbol: "skip_previous"
                    hoverShape: "arrow"
                    hoverAngle: -90
                    iconSize: 30
                    alwaysFilled: true
                    enabled: backend.hasTrack
                    tooltip: "Предыдущий трек"
                    onClicked: backend.prev()
                }

                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.compactHorizontal ? 52 : 60
                    height: width

                    SoftShadow {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: width / 2
                        blur: 15
                        color: Qt.rgba(PlayerStyle.primary.r, PlayerStyle.primary.g, PlayerStyle.primary.b, 0.34)
                    }
                    PlayButton {
                        anchors.fill: parent
                        enabled: backend.hasTrack
                        playing: backend.playing
                        color: "white"
                        hoverColor: "#ececec"
                        iconColor: "black"
                        iconSize: 32
                        onClicked: backend.toggle()
                    }
                }

                Control {
                    effect: TransportButton.NudgeRight
                    symbol: "skip_next"
                    hoverShape: "arrow"
                    hoverAngle: 90
                    iconSize: 30
                    alwaysFilled: true
                    enabled: backend.hasTrack
                    tooltip: "Следующий трек"
                    onClicked: backend.next()
                }
                Control {
                    effect: TransportButton.Bounce
                    symbol: backend.repeatMode === 2 ? "repeat_one" : "repeat"
                    toggledShape: backend.repeatMode === 2 ? "cookie4" : "cookie6"
                    toggled: backend.repeatMode !== 0
                    enabled: backend.hasTrack
                    tooltip: backend.repeatMode === 2 ? "Повтор одного трека" : (backend.repeatMode === 1 ? "Повтор очереди" : "Повтор выкл")
                    onClicked: backend.toggleRepeat()
                }
            }

            Row {
                id: volume
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: -muteButton.width / 2
                spacing: 10
                opacity: root.controlsOpacity
                enabled: root.controlsOpacity > 0

                IconButton {
                    id: muteButton
                    anchors.verticalCenter: parent.verticalCenter
                    scheme: root.scheme
                    symbol: backend.volume <= 0.01 ? "volume_off" : (backend.volume <= 0.5 ? "volume_down" : "volume_up")
                    size: 30
                    iconSize: 20
                    iconColor: Qt.rgba(1, 1, 1, 0.78)
                    colBackgroundHover: Qt.rgba(1, 1, 1, 0.1)
                    tooltip: backend.volume <= 0.01 ? "Включить звук" : "Выключить звук"
                    onClicked: backend.toggleMute()
                }
                StyledSlider {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, Math.min(Math.max(0, progress.width - 40), 300) - muteButton.width)
                    scheme: root.scheme
                    trackThickness: 8
                    handleLength: 20
                    showStopIndicator: false
                    showValueTip: true
                    activeColor: "white"
                    inactiveColor: Qt.rgba(1, 1, 1, 0.2)
                    value: backend.volume
                    onMoved: backend.setVolume(value)
                }
            }
        }
    }
}
