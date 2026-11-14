pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import ymusic.ui

T.AbstractButton {
    id: root

    property string trackTitle: ""
    property string trackArtists: ""
    property url artworkUrl: ""
    property bool available: true
    property bool current: false
    property MaterialScheme scheme: PlayerStyle.darkScheme

    enabled: !current
    hoverEnabled: true
    focusPolicy: Qt.TabFocus
    padding: 8
    leftPadding: 12
    rightPadding: 12
    implicitWidth: 300
    implicitHeight: 54 + topPadding + bottomPadding

    background: Rectangle {
        radius: 14
        color: Qt.rgba(1, 1, 1, root.current ? 0.09 : (root.down ? 0.1 : (root.hovered ? 0.05 : 0)))

        Behavior on color {
            ElementMoveFastColor {}
        }
    }

    contentItem: Item {
        opacity: root.available ? 1 : 0.38

        ArtworkImage {
            id: art
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 54
            height: 54
            radius: 8
            source: root.artworkUrl
            placeholderSymbol: "music_note"
            fallbackKey: root.trackTitle
        }

        Column {
            anchors.left: art.right
            anchors.leftMargin: 13
            anchors.right: speaker.visible ? speaker.left : parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            ScrollingText {
                width: parent.width
                text: root.trackTitle
                horizontalAlignment: Text.AlignLeft
                font.pixelSize: Appearance.fontSize.small
                font.weight: root.current ? Font.Bold : Font.DemiBold
                color: root.current ? "white" : Qt.rgba(1, 1, 1, 0.86)
                running: root.current || root.hovered
            }
            StyledText {
                width: parent.width
                text: root.trackArtists
                elide: Text.ElideRight
                font.pixelSize: Appearance.fontSize.smallie
                color: Qt.rgba(1, 1, 1, 0.62)
            }
        }

        MaterialSymbol {
            id: speaker
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            Reveal.shown: root.current
            text: "volume_up"
            fill: 1
            iconSize: 20
            color: root.scheme.primary
        }
    }

    HoverHandler {
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
}
