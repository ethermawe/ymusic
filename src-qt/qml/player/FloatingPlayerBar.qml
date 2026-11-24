pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import ymusic.ui

Item {
    id: root

    property MaterialScheme scheme: Appearance.colors
    signal immersiveRequested()

    readonly property bool twoRow: width < 560
    readonly property bool compact: width < 680
    readonly property bool tiny: width < 420
    readonly property real buttonSize: tiny ? 28 : (compact ? 30 : 32)
    readonly property real innerGap: tiny ? 6 : (compact ? 10 : 14)
    readonly property bool titleFits: twoRow || (nowPlaying.width - artwork.width - 8 >= 48)
    readonly property bool showsMeter: !compact && appSettings.visualizersEnabled && appSettings.playerBarVisualizer && backend.hasTrack
    property bool progressExpanded: seek.expanded || seekTwoRow.expanded

    function openTrackMenuAt(item, lx, ly) {
        if (!backend.hasTrack) return
        const appWindow = root.Window.window
        if (!appWindow) return
        const pt = item.mapToItem(appWindow.contentItem, lx, ly)
        backend.requestTrackMenu(backend.nowId, backend.nowTitle, true, pt.x, pt.y)
    }

    implicitHeight: twoRow ? 98 : 66
    opacity: Window.active ? 1 : 0.88

    Behavior on opacity {
        NumberAnimation { duration: Appearance.duration(160); easing.type: Easing.OutCubic }
    }

    SoftShadow {
        anchors.fill: surface
        radius: surface.radius
        blur: 18
        offset: Qt.vector2d(0, 6)
        color: Qt.rgba(0, 0, 0, 0.22)
    }

    Rectangle {
        id: surface
        anchors.fill: parent
        radius: 20
        color: root.scheme.surfaceContainerHigh
        border.width: 1
        border.color: Qt.rgba(root.scheme.outlineVariant.r, root.scheme.outlineVariant.g, root.scheme.outlineVariant.b, 0.4)

        ModSlotHost {
            anchors.fill: parent
            z: 0
            slotName: "playerBar.overlay"
            slotContext: ({
                scheme: root.scheme,
                compact: root.compact,
                twoRow: root.twoRow
            })
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            hoverEnabled: true
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton) {
                    root.openTrackMenuAt(surface, mouse.x, mouse.y)
                }
            }
            onWheel: (wheel) => {
                const step = appSettings.volumeStep
                if (wheel.angleDelta.y > 0) {
                    backend.setVolume(Math.min(1.0, backend.volume + step))
                } else if (wheel.angleDelta.y < 0) {
                    backend.setVolume(Math.max(0.0, backend.volume - step))
                }
                wheel.accepted = true
            }
        }
    }

    // Main top bar row
    Item {
        id: topRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.twoRow ? 62 : parent.height

        Row {
            id: transport
            anchors.left: parent.left
            anchors.leftMargin: root.compact ? 8 : 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.tiny ? 0 : 4

            TransportButton {
                visible: !root.twoRow
                anchors.verticalCenter: parent.verticalCenter
                scheme: root.scheme
                effect: TransportButton.Bounce
                symbol: "shuffle"
                toggledShape: "clover4"
                size: root.buttonSize
                iconSize: 19
                toggled: backend.shuffle
                fillWhenToggled: false
                tooltip: backend.shuffle ? qsTr("Выключить перемешивание") : qsTr("Перемешивать")
                onClicked: backend.toggleShuffle()
            }

            TransportButton {
                anchors.verticalCenter: parent.verticalCenter
                scheme: root.scheme
                effect: TransportButton.NudgeLeft
                symbol: "skip_previous"
                hoverShape: "arrow"
                hoverAngle: -90
                size: root.buttonSize
                iconSize: root.tiny ? 20 : 22
                fillWhenToggled: false
                alwaysFilled: true
                enabled: backend.hasTrack
                tooltip: qsTr("Предыдущий трек")
                onClicked: backend.prev()
            }

            PlayButton {
                anchors.verticalCenter: parent.verticalCenter
                size: root.tiny ? 36 : (root.compact ? 40 : 44)
                enabled: backend.hasTrack
                playing: backend.playing
                color: root.scheme.primary
                hoverColor: root.scheme.primaryHover
                iconColor: root.scheme.onPrimary
                onClicked: backend.toggle()
            }

            TransportButton {
                anchors.verticalCenter: parent.verticalCenter
                scheme: root.scheme
                effect: TransportButton.NudgeRight
                symbol: "skip_next"
                hoverShape: "arrow"
                hoverAngle: 90
                size: root.buttonSize
                iconSize: root.tiny ? 20 : 22
                alwaysFilled: true
                enabled: backend.hasTrack
                tooltip: qsTr("Следующий трек")
                onClicked: backend.next()
            }

            TransportButton {
                visible: !root.twoRow
                anchors.verticalCenter: parent.verticalCenter
                scheme: root.scheme
                effect: TransportButton.Bounce
                symbol: backend.repeatMode === 2 ? "repeat_one" : "repeat"
                toggledShape: backend.repeatMode === 2 ? "cookie4" : "cookie6"
                size: root.buttonSize
                iconSize: 19
                toggled: backend.repeatMode !== 0
                fillWhenToggled: false
                enabled: backend.hasTrack
                tooltip: backend.repeatMode === 2 ? qsTr("Повтор: трек") : (backend.repeatMode === 1 ? qsTr("Повтор: всё") : qsTr("Повтор выкл."))
                onClicked: backend.toggleRepeat()
            }
        }

        Item {
            id: nowPlaying
            anchors.left: transport.right
            anchors.leftMargin: root.innerGap
            anchors.right: utilities.left
            anchors.rightMargin: root.innerGap
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            Item {
                id: artwork
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: root.twoRow ? 0 : -4
                width: root.tiny ? 34 : 40
                height: width
                z: 2
                scale: artHover.hovered ? 1.12 : 1

                transform: Scale {
                    id: pop
                    origin.x: artwork.width / 2
                    origin.y: artwork.height / 2
                }

                Connections {
                    target: backend
                    function onTrackInstanceIdChanged() {
                        if (!Appearance.performanceMode) popIn.restart()
                    }
                }
                NumberAnimation {
                    id: popIn
                    target: pop
                    properties: "xScale,yScale"
                    from: 0.7
                    to: 1
                    duration: 560
                    easing.type: Easing.OutBack
                    easing.overshoot: 2.4
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: Appearance.motion(artHover.hovered ? 220 : 340)
                        easing.type: artHover.hovered ? Easing.OutBack : Easing.OutCubic
                    }
                }

                SoftShadow {
                    anchors.fill: parent
                    radius: Appearance.sizes.smallArtworkRadius
                    blur: 7
                    offset: Qt.vector2d(0, 3)
                    color: Qt.rgba(0, 0, 0, artHover.hovered ? 0.22 : 0)
                }

                ArtworkImage {
                    anchors.fill: parent
                    radius: Appearance.sizes.smallArtworkRadius
                    source: backend.hasCover ? backend.nowCover : ""
                    crossfade: true
                    fallbackKey: backend.nowId.length > 0 ? backend.nowId : backend.nowTitle
                }

                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.sizes.smallArtworkRadius
                    color: Qt.rgba(0, 0, 0, artHover.hovered && backend.hasTrack ? 0.28 : 0)

                    Behavior on color {
                        ColorAnimation { duration: Appearance.duration(160) }
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "open_in_full"
                        iconSize: 16
                        weight: 600
                        color: "white"
                        opacity: artHover.hovered && backend.hasTrack ? 1 : 0
                    }
                }

                HoverHandler {
                    id: artHover
                    cursorShape: backend.hasTrack ? Qt.PointingHandCursor : Qt.ArrowCursor
                }
                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onTapped: if (backend.hasTrack) root.immersiveRequested()
                }
            }

            Item {
                id: info
                visible: root.titleFits
                clip: true
                property real blurAmount: !root.twoRow && seek.expanded ? 1 : 0

                Behavior on blurAmount {
                    NumberAnimation { duration: Appearance.duration(260); easing.type: Easing.OutCubic }
                }

                anchors.left: artwork.right
                anchors.leftMargin: 8
                anchors.right: root.showsMeter ? meter.left : parent.right
                anchors.rightMargin: root.showsMeter ? 9 : 0
                anchors.top: parent.top
                anchors.topMargin: root.twoRow ? 4 : 7
                anchors.bottom: root.twoRow ? parent.bottom : seekSlot.top
                anchors.bottomMargin: root.twoRow ? 4 : 0
                layer.enabled: blurAmount > 0.001
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: info.blurAmount
                    blurMax: 40
                    saturation: -0.2 * info.blurAmount
                }

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Item {
                        width: parent.width
                        height: Math.max(nowTitleItem.implicitHeight, 18)

                        readonly property bool showAiBadge: backend.hasTrack && backend.showAiLabels && backend.nowIsAi

                        TitleText {
                            id: nowTitleItem
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, Math.max(0, parent.width - (playerAiBadge.visible ? playerAiBadge.width + 6 : 0)))
                            text: backend.hasTrack ? backend.nowTitle : qsTr("Ничего не играет")
                            elide: Text.ElideRight
                            animateChange: true
                            changeDistanceX: 6
                            changeDistanceY: 0
                            font.pixelSize: Appearance.fontSize.small
                            color: root.scheme.onSurface
                            font.underline: titleHover.hovered && backend.nowHasAlbum

                            HoverHandler {
                                id: titleHover
                                cursorShape: backend.nowHasAlbum ? Qt.PointingHandCursor : Qt.ArrowCursor
                            }
                            TapHandler {
                                enabled: backend.nowHasAlbum
                                onTapped: backend.openNowAlbum()
                            }

                            ShaderEffect {
                                id: scan

                                property color color: root.scheme.primary
                                property real halfWidth: 0.22
                                property real edge: 0.18
                                property real position: -halfWidth

                                anchors.top: parent.bottom
                                anchors.topMargin: 1
                                width: parent.width
                                height: 2
                                opacity: backend.buffering ? 1 : 0
                                visible: opacity > 0
                                fragmentShader: "qrc:/shaders/gleam.frag.qsb"

                                Behavior on opacity {
                                    NumberAnimation { duration: Appearance.duration(260); easing.type: Easing.InOutSine }
                                }

                                NumberAnimation on position {
                                    running: scan.visible && !Appearance.reduceMotion
                                    from: -scan.halfWidth
                                    to: 1 + scan.halfWidth
                                    duration: 1300
                                    loops: Animation.Infinite
                                }
                            }
                        }

                        AiBadge {
                            id: playerAiBadge
                            visible: parent.showAiBadge
                            anchors.left: nowTitleItem.right
                            anchors.leftMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            scheme: root.scheme
                        }
                    }

                    ArtistLinks {
                        width: parent.width
                        links: backend.nowArtistLinks
                        fallbackText: backend.hasTrack ? backend.nowArtists : qsTr("Выберите трек")
                        fallbackClickable: backend.hasTrack && backend.nowHasArtist
                        clickable: backend.hasTrack
                        color: root.scheme.onSurfaceVariant
                        font.pixelSize: Appearance.fontSize.smaller
                    }
                }
            }

            CompactMeter {
                id: meter
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                height: 34
                Reveal.shown: root.showsMeter
                active: backend.playing
            }

            Item {
                id: seekSlot
                visible: !root.twoRow
                anchors.left: root.titleFits ? artwork.right : parent.left
                anchors.leftMargin: root.titleFits ? 8 : 0
                anchors.right: parent.right
                anchors.rightMargin: root.showsMeter ? 39 : 0
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                height: 18

                HoverHandler {
                    id: seekHover
                    cursorShape: seek.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                }

                SeekBar {
                    id: seek
                    anchors.fill: parent
                    externalHover: seekHover.hovered

                    property real lift: seek.expanded ? -5 : 0
                    Behavior on lift {
                        enabled: !Appearance.performanceMode
                        Bounce {}
                    }
                    transform: Translate { y: seek.lift }

                    scheme: root.scheme
                }
            }

            Row {
                visible: !root.twoRow && opacity > 0
                anchors.left: seekSlot.left
                anchors.right: seekSlot.right
                anchors.bottom: seekSlot.top
                anchors.bottomMargin: -2
                transform: Translate { y: seek.lift }
                opacity: seek.expanded ? 1 : 0

                Behavior on opacity {
                    NumberAnimation { duration: Appearance.duration(160) }
                }

                StyledText {
                    width: parent.width / 2
                    text: Format.playbackTime(seek.displayPositionMs)
                    tabularNumbers: true
                    font.pixelSize: Appearance.fontSize.smallest
                    font.weight: Font.Medium
                    color: root.scheme.onSurface
                }
                StyledText {
                    width: parent.width / 2
                    horizontalAlignment: Text.AlignRight
                    text: "−" + Format.playbackTime(Math.max(seek.durationMs - seek.displayPositionMs, 0))
                    tabularNumbers: true
                    font.pixelSize: Appearance.fontSize.smallest
                    font.weight: Font.Medium
                    color: root.scheme.onSurface
                }
            }
        }

        Row {
            id: utilities
            anchors.right: parent.right
            anchors.rightMargin: root.compact ? 8 : 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.tiny ? 0 : 4
            z: 3

            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                scheme: root.scheme
                symbol: "favorite"
                toggled: backend.nowLiked
                fillWhenToggled: true
                burst: backend.nowLiked ? "" : "hearts"
                size: root.buttonSize
                iconSize: 20
                tooltip: backend.nowLiked ? qsTr("Убрать из «Мне нравится»") : qsTr("Добавить в «Мне нравится»")
                enabled: backend.hasTrack
                onClicked: backend.toggleNowLike()
            }

            IconButton {
                id: moreButton
                anchors.verticalCenter: parent.verticalCenter
                scheme: root.scheme
                symbol: "more_horiz"
                size: root.buttonSize
                iconSize: 20
                tooltip: qsTr("Действия с треком")
                enabled: backend.hasTrack
                onClicked: root.openTrackMenuAt(moreButton, moreButton.width, 0)
            }

            IconButton {
                visible: !root.tiny
                anchors.verticalCenter: parent.verticalCenter
                scheme: root.scheme
                symbol: "lyrics"
                size: root.buttonSize
                iconSize: 20
                toggled: UiState.showingLyrics
                tooltip: qsTr("Текст трека")
                onClicked: UiState.toggleLyricsPanel()
            }

            IconButton {
                visible: !root.tiny
                anchors.verticalCenter: parent.verticalCenter
                scheme: root.scheme
                symbol: "queue_music"
                size: root.buttonSize
                iconSize: 20
                toggled: UiState.showingQueue
                tooltip: qsTr("Очередь")
                onClicked: UiState.toggleQueuePanel()
            }

            ModSlotHost {
                layoutMode: "row"
                anchors.verticalCenter: parent.verticalCenter
                height: root.buttonSize
                spacing: 4
                visible: !root.tiny && implicitWidth > 0
                slotName: "playerBar.controls"
                slotContext: ({
                    scheme: root.scheme,
                    buttonSize: root.buttonSize,
                    compact: root.compact
                })
            }

            VolumeControl {
                visible: !root.twoRow
                anchors.verticalCenter: parent.verticalCenter
                scheme: root.scheme
            }

            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                scheme: root.scheme
                symbol: "open_in_full"
                size: root.buttonSize
                iconSize: 18
                tooltip: qsTr("Иммерсивный плеер")
                onClicked: root.immersiveRequested()
            }
        }
    }

    // Two-row seek strip when window is very narrow (< 560px)
    Item {
        visible: root.twoRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.bottomMargin: 6
        height: 26

        StyledText {
            id: posLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: Format.playbackTime(seekTwoRow.displayPositionMs)
            tabularNumbers: true
            font.pixelSize: Appearance.fontSize.smallest
            color: root.scheme.onSurfaceVariant
        }

        SeekBar {
            id: seekTwoRow
            anchors.left: posLabel.right
            anchors.right: durLabel.left
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            height: 20
            scheme: root.scheme
        }

        StyledText {
            id: durLabel
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: Format.playbackTime(seekTwoRow.durationMs)
            tabularNumbers: true
            font.pixelSize: Appearance.fontSize.smallest
            color: root.scheme.onSurfaceVariant
        }
    }
}
