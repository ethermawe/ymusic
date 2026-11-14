pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import ymusic.ui

T.AbstractButton {
    id: root

    property string trackId
    property string titleText
    property string artistsText
    property string coverUrl
    property bool current: false
    property bool available: true
    property MaterialScheme scheme: Appearance.colors

    implicitHeight: 54
    hoverEnabled: true
    focusPolicy: Qt.TabFocus
    padding: 6
    leftPadding: 10
    rightPadding: 10
    enabled: !current && available

    background: Rectangle {
        radius: 10
        color: root.hovered ? root.scheme.layer1Hover : "transparent"
    }

    contentItem: Item {
        opacity: root.available ? 1 : 0.38

        ArtworkImage {
            id: art
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 42
            height: 42
            radius: 6
            source: root.coverUrl
            fallbackKey: root.trackId.length > 0 ? root.trackId : root.titleText
        }

        Column {
            anchors.left: art.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            StyledText {
                width: parent.width
                text: root.titleText
                elide: Text.ElideRight
                font.pixelSize: Appearance.fontSize.smallie
                font.weight: root.current ? Font.DemiBold : Font.Normal
                color: root.current ? root.scheme.primary : root.scheme.onSurface
            }
            StyledText {
                width: parent.width
                text: root.artistsText
                elide: Text.ElideRight
                font.pixelSize: Appearance.fontSize.smaller
                color: root.scheme.onSurfaceVariant
            }
        }
    }

    HoverHandler {
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
}
