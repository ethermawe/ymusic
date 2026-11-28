pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import ymusic.ui

T.AbstractButton {
    id: root

    property int cardIndex: -1
    property var cardData: null
    readonly property int effectiveCardIndex: (cardData?.cardIndex !== undefined && cardData?.cardIndex !== null)
        ? Number(cardData.cardIndex) : cardIndex
    property bool isArtist: (cardData?.kind ?? "") === "artist"
    property url artworkUrl: (cardData?.hasCover ?? false) ? (cardData?.coverUrl ?? "") : ""
    property string placeholderSymbol: isArtist ? "artists" : ((cardData?.kind ?? "") === "album" ? "album" : "library_music")
    property string title: cardData?.title ?? ""
    property string fallbackKey: title
    property string subtitle: cardData?.subtitle ?? ""
    property bool isPlaylist: (cardData?.kind ?? "") === "playlist"
    property bool isPinned: cardData?.pinned ?? false
    property bool circular: isArtist
    property bool current: false
    property string badgeSymbol: "arrow_forward"
    property real artworkSize: Math.max(120, width)
    property int titleLines: 2
    property bool wavyOnHover: !circular

    signal secondaryClicked()

    implicitWidth: Appearance.sizes.cardSize
    implicitHeight: column.implicitHeight
    hoverEnabled: true
    focusPolicy: Qt.TabFocus
    scale: down ? 0.95 : (hovered ? 1.03 : 1)
    opacity: down ? 0.86 : 1

    Behavior on scale {
        enabled: !Appearance.performanceMode
        Bounce {}
    }

    onClicked: Backend.openCard(root.effectiveCardIndex)

    contentItem: Column {
        id: column
        spacing: 8

        MediaArtwork {
            id: artwork
            width: root.artworkSize
            height: root.artworkSize
            source: root.artworkUrl
            placeholderSymbol: root.placeholderSymbol
            fallbackKey: root.fallbackKey
            circular: root.circular
            current: root.current
            badgeSymbol: root.badgeSymbol
            hovered: root.hovered
            wavy: root.wavyOnHover && root.hovered
        }

        StyledText {
            z: -1
            width: root.artworkSize
            text: root.title
            maximumLineCount: root.titleLines
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            horizontalAlignment: root.circular ? Text.AlignHCenter : Text.AlignLeft
            font.pixelSize: Appearance.fontSize.small
            font.weight: Font.DemiBold
        }

        StyledText {
            z: -1
            width: root.artworkSize
            visible: root.subtitle.length > 0
            text: root.subtitle
            elide: Text.ElideRight
            horizontalAlignment: root.circular ? Text.AlignHCenter : Text.AlignLeft
            font.pixelSize: Appearance.fontSize.smaller
            color: Appearance.colors.onSurfaceVariant
        }
    }

    onReleased: {
        if (hovered) {
            UiState.launchHero(artwork.cover, artworkUrl, circular)
        }
    }

    property real tiltAcross: pointer.hovered && !Appearance.performanceMode
                              ? (Math.max(0, Math.min(1, pointer.point.position.x / Math.max(1, width))) - 0.5) * 12 : 0
    property real tiltDown: pointer.hovered && !Appearance.performanceMode
                            ? (0.5 - Math.max(0, Math.min(1, pointer.point.position.y / Math.max(1, root.artworkSize)))) * 10 : 0
    readonly property bool tiltSmoothing: !pointer.hovered || enterTiltTimer.running

    Timer {
        id: enterTiltTimer
        interval: 110
    }

    Behavior on tiltAcross {
        enabled: root.tiltSmoothing && !Appearance.performanceMode
        NumberAnimation {
            duration: Appearance.duration(140)
            easing.type: Easing.OutCubic
        }
    }
    Behavior on tiltDown {
        enabled: root.tiltSmoothing && !Appearance.performanceMode
        NumberAnimation {
            duration: Appearance.duration(140)
            easing.type: Easing.OutCubic
        }
    }

    transform: [
        Rotation {
            origin.x: root.width / 2
            origin.y: root.artworkSize / 2
            axis { x: 0; y: 1; z: 0 }
            angle: root.tiltAcross
        },
        Rotation {
            origin.x: root.width / 2
            origin.y: root.artworkSize / 2
            axis { x: 1; y: 0; z: 0 }
            angle: root.tiltDown
        }
    ]

    HoverHandler {
        id: pointer
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: if (hovered) enterTiltTimer.restart()
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: {
            if (root.isPlaylist) pinMenu.popup();
            root.secondaryClicked();
        }
    }

    Loader {
        active: ModManager.reloadRevision >= 0 && ModManager.hasSlot("card.overlay")
        x: 0
        y: 0
        width: root.artworkSize
        height: root.artworkSize
        z: 2
        sourceComponent: ModSlotHost {
            slotName: "card.overlay"
            slotContext: ({
                card: root.cardData,
                index: root.effectiveCardIndex,
                title: root.title,
                subtitle: root.subtitle,
                isArtist: root.isArtist,
                isPlaylist: root.isPlaylist,
                hovered: root.hovered
            })
        }
    }

    IconButton {
        visible: root.isPlaylist && (root.hovered || root.isPinned)
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 8
        anchors.rightMargin: 8
        z: 3
        symbol: "push_pin"
        toggled: root.isPinned
        size: 32
        iconSize: 17
        colBackground: Qt.rgba(0, 0, 0, 0.58)
        colBackgroundHover: Qt.rgba(0, 0, 0, 0.78)
        colBackgroundToggled: Appearance.colors.primaryContainer
        colBackgroundToggledHover: Appearance.colors.primaryContainer
        iconColor: root.isPinned ? Appearance.colors.onPrimaryContainer : "white"
        tooltip: root.isPinned ? qsTr("Открепить плейлист") : qsTr("Закрепить в сайдбаре")
        onClicked: Backend.feature({action: "toggle_pin_playlist", card_index: root.effectiveCardIndex})
    }

    StyledMenu {
        id: pinMenu
        StyledMenuItem {
            symbol: "push_pin"
            text: root.isPinned ? qsTr("Открепить из сайдбара") : qsTr("Закрепить в сайдбаре")
            onTriggered: Backend.feature({action: "toggle_pin_playlist", card_index: root.effectiveCardIndex})
        }
    }
}
