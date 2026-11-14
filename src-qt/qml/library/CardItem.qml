pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import ymusic.ui

T.AbstractButton {
    id: root

    required property int index
    required property var model
    property bool isArtist: (model?.kind ?? "") === "artist"
    property url artworkUrl: (model?.hasCover ?? false) ? (model?.coverUrl ?? "") : ""
    property string placeholderSymbol: isArtist ? "artists" : ((model?.kind ?? "") === "album" ? "album" : "library_music")
    property string title: model?.title ?? ""
    property string fallbackKey: title
    property string subtitle: model?.subtitle ?? ""
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

    onClicked: backend.openCard(root.index)

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
                              ? (pointer.point.position.x / Math.max(1, width) - 0.5) * 12 : 0
    property real tiltDown: pointer.hovered && !Appearance.performanceMode
                            ? (0.5 - pointer.point.position.y / Math.max(1, root.artworkSize)) * 10 : 0

    Behavior on tiltAcross {
        SpringAnimation { spring: 4; damping: 0.3; epsilon: 0.01 }
    }
    Behavior on tiltDown {
        SpringAnimation { spring: 4; damping: 0.3; epsilon: 0.01 }
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
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: root.secondaryClicked()
    }
}
