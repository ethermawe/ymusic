import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import ymusic.ui

Item {
    id: root

    property bool isCurrent: model.isCurrent
    property bool isPlaying: model.isPlaying
    property bool queueView: false
    readonly property bool isHovered: rowHover.hovered

    implicitHeight: 56
    implicitWidth: 600

    function openTrackMenu() {
        const appWindow = root.Window.window;
        if (appWindow) {
            const position = root.mapToItem(appWindow.contentItem, root.width - 36, root.height);
            backend.requestTrackMenu(model.id, model.title, model.available, position.x, position.y);
        }
    }

    HoverHandler {
        id: rowHover
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                root.openTrackMenu();
                return;
            }
            if (root.isCurrent) backend.toggle();
            else if (root.queueView) backend.trackAction(model.id, 3);
            else backend.play(model.index);
        }
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4
        radius: Appearance.rounding.small
        z: -1
        antialiasing: true
        color: Appearance.colors.primary
        opacity: root.isCurrent ? 0.14 : 0

        border.width: root.isCurrent ? 1 : 0
        border.color: Qt.rgba(Appearance.colors.primary.r, Appearance.colors.primary.g, Appearance.colors.primary.b, 0.25)

        Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4
        radius: Appearance.rounding.small
        z: -1
        antialiasing: true
        color: root.isCurrent ? Appearance.colors.primary : Appearance.colors.surfaceContainerHigh
        opacity: root.isHovered ? (root.isCurrent ? 0.08 : 1) : 0
        Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 12

        // Left: Index or Play icon or Equalizer
        Item {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            Layout.alignment: Qt.AlignVCenter

            // Equalizer when playing
            EqualizerBars {
                anchors.centerIn: parent
                active: root.isPlaying && visible
                opacity: root.isCurrent && root.isPlaying && !root.isHovered ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }

            // Track index number
            Text {
                anchors.centerIn: parent
                text: String(model.index + 1)
                color: root.isCurrent ? Appearance.colors.primary : Appearance.colors.onSurfaceVariant
                font.pixelSize: Appearance.fontSize.smaller
                font.weight: Font.Medium
                opacity: (!root.isCurrent || !root.isPlaying) && !root.isHovered ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }

            // Play / Pause icon on hover
            MaterialSymbol {
                anchors.centerIn: parent
                text: root.isPlaying ? "pause" : "play_arrow"
                iconSize: 20
                color: Appearance.colors.onSurface
                opacity: root.isHovered ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
        }

        // Thumbnail cover with true rounded corners
        RoundedImage {
            Layout.preferredWidth: 40
            Layout.preferredHeight: 40
            Layout.alignment: Qt.AlignVCenter
            radius: Appearance.rounding.verySmall
            source: model.hasCover ? model.coverUrl : ""
            fallbackSymbol: "music_note"
            fallbackIconSize: 18
            sourceSize.width: 80
            sourceSize.height: 80
        }

        // Title and Artists
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            Text {
                text: model.title
                color: root.isCurrent ? Appearance.colors.primary : Appearance.colors.onSurface
                font.pixelSize: Appearance.fontSize.small
                font.weight: Font.Medium
                elide: Text.ElideRight
                Layout.fillWidth: true
                font.underline: titleHover.hovered && model.hasAlbum
                HoverHandler {
                    id: titleHover
                    cursorShape: model.hasAlbum ? Qt.PointingHandCursor : Qt.ArrowCursor
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: model.hasAlbum
                    onClicked: {
                        if (root.queueView) backend.trackAction(model.id, 6);
                        else backend.openTrackAlbum(model.index);
                    }
                }
            }

            Text {
                text: model.artists
                color: Appearance.colors.onSurfaceVariant
                font.pixelSize: Appearance.fontSize.smaller
                elide: Text.ElideRight
                Layout.fillWidth: true
                font.underline: artistHover.hovered && model.hasArtist
                HoverHandler { id: artistHover; cursorShape: model.hasArtist ? Qt.PointingHandCursor : Qt.ArrowCursor }
                MouseArea {
                    anchors.fill: parent
                    enabled: model.hasArtist
                    onClicked: {
                        if (root.queueView) backend.trackAction(model.id, 5);
                        else backend.openTrackArtist(model.index);
                    }
                }
            }
        }

        // Album name (hidden on narrow widths)
        Text {
            text: model.album
            color: Appearance.colors.onSurfaceVariant
            font.pixelSize: Appearance.fontSize.smaller
            elide: Text.ElideRight
            Layout.preferredWidth: 160
            Layout.alignment: Qt.AlignVCenter
            visible: parent.width > 500
        }

        // Like button
        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: "download_done"
            iconSize: 16
            color: Appearance.colors.primary
            visible: model.downloaded
        }

        IconButton {
            Layout.alignment: Qt.AlignVCenter
            symbol: model.liked ? "favorite" : "favorite_border"
            size: 32
            iconSize: 18
            iconColor: model.liked ? Appearance.colors.primary : Appearance.colors.onSurfaceVariant
            activeIconColor: Appearance.colors.primary
            toggled: model.liked
            opacity: (model.liked || root.isHovered) ? 1.0 : 0.0
            enabled: model.liked || root.isHovered
            Behavior on opacity { NumberAnimation { duration: 120 } }
            onClicked: {
                if (root.queueView) backend.trackAction(model.id, 4);
                else backend.toggleLike(model.index);
            }
        }

        // Duration
        Text {
            text: model.duration
            color: Appearance.colors.onSurfaceVariant
            font.pixelSize: Appearance.fontSize.smaller
            font.family: "monospace"
            Layout.preferredWidth: 44
            Layout.alignment: Qt.AlignVCenter
            horizontalAlignment: Text.AlignRight
        }

        IconButton {
            symbol: "more_horiz"
            size: 32
            iconSize: 20
            tooltip: "Действия с треком"
            onClicked: root.openTrackMenu()
        }
    }


}
