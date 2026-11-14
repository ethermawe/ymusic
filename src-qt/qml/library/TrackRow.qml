pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Templates as T
import ymusic.ui

T.AbstractButton {
    id: root

    required property int index
    required property var model
    property bool isCurrent: model?.isCurrent ?? false
    property bool isPlaying: model?.isPlaying ?? false
    property bool queueView: false
    property bool showsNumber: true
    readonly property bool expanded: hovered || isCurrent

    implicitHeight: 58
    implicitWidth: 600
    hoverEnabled: true
    focusPolicy: Qt.TabFocus
    scale: (expanded ? 1 + Math.min(0.025, 10 / Math.max(width, 1)) : 1) - (down ? 0.012 : 0)
    z: expanded ? 2 : 1

    Behavior on scale {
        enabled: !Appearance.performanceMode
        Bounce {}
    }

    leftPadding: 14
    rightPadding: 14

    function openTrackMenu() {
        const appWindow = root.Window.window;
        if (appWindow && root.model) {
            const position = root.mapToItem(appWindow.contentItem, root.width - 36, root.height);
            backend.requestTrackMenu(root.model.id, root.model.title, root.model.available, position.x, position.y);
        }
    }

    onClicked: {
        if (!root.model) return;
        if (root.isCurrent) backend.toggle();
        else if (root.queueView) backend.trackAction(root.model.id, 3);
        else backend.play(root.index);
    }

    background: Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        radius: Appearance.rounding.small
        color: root.isCurrent ? Qt.alpha(Appearance.colors.primary, 0.07)
             : root.hovered ? Qt.alpha(Appearance.colors.onSurface, 0.05)
             : Qt.alpha(Appearance.colors.onSurface, 0)

        Behavior on color {
            ColorAnimation { duration: Appearance.duration(120) }
        }
    }

    contentItem: Item {
        Item {
            id: number
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: root.showsNumber ? 24 : 0
            visible: root.showsNumber
            height: parent.height

            Loader {
                id: cookieHolder
                property bool showing: false
                Binding {
                    target: cookieHolder
                    property: "showing"
                    value: (cookieHolder.item as Item)?.visible ?? false
                    delayed: true
                }
                anchors.centerIn: playingMark
                active: root.isCurrent || showing
                sourceComponent: MaterialShape {
                    id: cookie
                    property bool arrived: false
                    width: 24
                    height: 24
                    Reveal.shown: arrived && root.isCurrent && !root.hovered
                    shape: "cookie6"
                    color: Appearance.colors.primaryContainer
                    spinRate: 30
                    scale: visible ? 1 + 0.12 * Math.sin(UiState.spin * 7) : 1
                    Component.onCompleted: Qt.callLater(() => {
                        if (cookie) cookie.arrived = true;
                    })
                }
            }

            MaterialSymbol {
                id: playingMark
                anchors.right: parent.right
                anchors.rightMargin: -3
                anchors.verticalCenter: parent.verticalCenter
                Reveal.shown: root.hovered || root.isCurrent
                text: root.hovered ? (root.isPlaying ? "pause" : "play_arrow") : "volume_up"
                iconSize: 16
                fill: 1
                color: root.hovered ? Appearance.colors.onSurface : Appearance.colors.onPrimaryContainer
            }

            StyledText {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                Reveal.shown: !root.hovered && !root.isCurrent
                text: root.index + 1
                tabularNumbers: true
                font.pixelSize: Appearance.fontSize.smaller
                color: Appearance.colors.onSurfaceVariant
            }
        }

        Item {
            id: artwork
            anchors.left: number.right
            anchors.leftMargin: root.showsNumber ? 12 : 0
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            height: 44
            opacity: (root.model?.available ?? true) ? 1 : 0.38

            ArtworkImage {
                anchors.fill: parent
                radius: 6
                source: (root.model?.hasCover ?? false) ? (root.model?.coverUrl ?? "") : ""
                placeholderSymbol: "music_note"
                fallbackKey: root.model?.title ?? ""
            }

            Loader {
                id: meterHolder
                property bool showing: false
                Binding {
                    target: meterHolder
                    property: "showing"
                    value: (meterHolder.item as Item)?.visible ?? false
                    delayed: true
                }
                anchors.fill: parent
                active: (root.isCurrent && appSettings.visualizersEnabled) || showing
                sourceComponent: Rectangle {
                    id: shade
                    property bool arrived: false
                    Reveal.shown: arrived && root.isCurrent && appSettings.visualizersEnabled
                    radius: 6
                    color: Qt.rgba(0, 0, 0, 0.34)
                    Component.onCompleted: Qt.callLater(() => {
                        if (shade) shade.arrived = true;
                    })

                    CompactMeter {
                        anchors.centerIn: parent
                        width: 26
                        height: 22
                        active: root.isPlaying
                    }
                }
            }
        }

        Column {
            anchors.left: artwork.right
            anchors.leftMargin: 12
            anchors.right: albumText.visible ? albumText.left : actions.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            opacity: (root.model?.available ?? true) ? 1 : 0.38

            StyledText {
                width: parent.width
                text: root.model?.title ?? ""
                elide: Text.ElideRight
                font.pixelSize: Appearance.fontSize.small
                font.weight: root.isCurrent ? Font.DemiBold : Font.Normal
                color: root.isCurrent ? Appearance.colors.primary : Appearance.colors.onSurface
                font.underline: titleHover.hovered && (root.model?.hasAlbum ?? false)

                HoverHandler {
                    id: titleHover
                    cursorShape: (root.model?.hasAlbum ?? false) ? Qt.PointingHandCursor : Qt.ArrowCursor
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: root.model?.hasAlbum ?? false
                    onClicked: {
                        if (!root.model) return;
                        if (root.queueView) backend.trackAction(root.model.id, 6);
                        else backend.openTrackAlbum(root.index);
                    }
                }
            }

            ArtistLinks {
                width: parent.width
                links: root.model?.artistLinks ?? []
                fallbackText: root.model?.artists ?? ""
                clickable: true
                fallbackClickable: root.model?.hasArtist ?? false
                handleDefaultFallback: false
                font.pixelSize: Appearance.fontSize.smaller
                color: Appearance.colors.onSurfaceVariant
                onFallbackActivated: {
                    if (!root.model) return;
                    if (root.queueView) backend.trackAction(root.model.id, 5);
                    else backend.openTrackArtist(root.index);
                }
            }
        }

        StyledText {
            id: albumText
            anchors.right: actions.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: visible ? Math.min(160, Math.max(90, root.width * 0.2)) : 0
            visible: root.width > 580 && !root.queueView && (root.model?.album ?? "").length > 0
            text: root.model?.album ?? ""
            elide: Text.ElideRight
            font.pixelSize: Appearance.fontSize.smaller
            color: Appearance.colors.onSurfaceVariant
        }

        StyledText {
            id: duration
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            horizontalAlignment: Text.AlignRight
            text: root.model?.duration ?? ""
            tabularNumbers: true
            font.pixelSize: Appearance.fontSize.smaller
            color: Appearance.colors.onSurfaceVariant
        }

        Row {
            id: actions
            anchors.right: duration.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            layoutDirection: Qt.RightToLeft
            spacing: 2

            move: Transition {
                enabled: !Appearance.performanceMode
                NumberAnimation { properties: "x"; duration: 240; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
            }

            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                symbol: "more_horiz"
                size: 28
                iconSize: 18
                tooltip: "Действия с треком"
                onClicked: root.openTrackMenu()
            }

            IconButton {
                id: likeButton
                anchors.verticalCenter: parent.verticalCenter
                symbol: (root.model?.liked ?? false) ? "favorite" : "favorite_border"
                toggled: root.model?.liked ?? false
                size: 28
                iconSize: 18
                iconColor: (root.model?.liked ?? false) ? Appearance.colors.primary : Appearance.colors.onSurfaceVariant
                opacity: ((root.model?.liked ?? false) || root.hovered) ? 1.0 : 0.0
                enabled: (root.model?.liked ?? false) || root.hovered
                tooltip: (root.model?.liked ?? false) ? "Убрать из Мне нравится" : "Добавить в Мне нравится"

                onClicked: {
                    if (!root.model) return;
                    if (!root.model.liked) {
                        UiState.burst(likeButton, "hearts");
                        if (!Appearance.performanceMode) likePop.restart();
                    }
                    if (root.queueView) backend.trackAction(root.model.id, 4);
                    else backend.toggleLike(root.index);
                }

                MaterialShape {
                    id: likeBurst
                    anchors.centerIn: parent
                    width: 40
                    height: 40
                    z: -2
                    opacity: 0
                    shape: "sunny"
                    color: Appearance.colors.primaryContainer
                }

                ParallelAnimation {
                    id: likePop
                    NumberAnimation { target: likeBurst; property: "scale"; from: 0.3; to: 1.15; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2 }
                    NumberAnimation { target: likeBurst; property: "spinAngle"; from: -40; to: 40; duration: 520; easing.type: Easing.OutCubic }
                    SequentialAnimation {
                        NumberAnimation { target: likeBurst; property: "opacity"; from: 0; to: 1; duration: 90 }
                        PauseAnimation { duration: 200 }
                        NumberAnimation { target: likeBurst; property: "opacity"; to: 0; duration: 260; easing.type: Easing.InCubic }
                    }
                }
            }

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: "download_done"
                iconSize: 16
                color: Appearance.colors.primary
                visible: root.model?.downloaded ?? false
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.queueView
                spacing: 0
                IconButton {
                    symbol: "expand_more"; rotation: 180; size: 26; iconSize: 16
                    enabled: root.index > 0
                    onClicked: if (root.model) backend.feature({action: "queue", operation: "up", index: root.index, id: root.model.id})
                }
                IconButton {
                    symbol: "expand_more"; size: 26; iconSize: 16
                    enabled: root.index < backend.queue.count - 1
                    onClicked: if (root.model) backend.feature({action: "queue", operation: "down", index: root.index, id: root.model.id})
                }
                IconButton {
                    symbol: "close"; size: 26; iconSize: 16
                    enabled: !root.isCurrent
                    onClicked: if (root.model) backend.feature({action: "queue", operation: "remove", index: root.index, id: root.model.id})
                }
            }
        }
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: root.openTrackMenu()
    }
}
