import QtQuick
import QtQuick.Layouts
import ymusic.ui

Item {
    id: root

    property bool isCurrent: model.isCurrent
    property bool isPlaying: model.isPlaying
    property bool isHovered: mouseArea.containsMouse

    implicitHeight: 56
    implicitWidth: 600

    scale: isHovered ? 1.012 : 1.0
    z: isHovered ? 2 : 1
    Behavior on scale {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutBack
            easing.overshoot: 1.6
        }
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: Appearance.rounding.small
        color: root.isCurrent
               ? Qt.rgba(Appearance.colors.primary.r, Appearance.colors.primary.g, Appearance.colors.primary.b, 0.12)
               : (root.isHovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent")

        border.width: root.isCurrent ? 1 : 0
        border.color: Qt.rgba(Appearance.colors.primary.r, Appearance.colors.primary.g, Appearance.colors.primary.b, 0.25)

        Behavior on color {
            ColorAnimation { duration: 130 }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 12

        // Left: Index or Play icon or Equalizer
        Item {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            Layout.alignment: Qt.AlignVCenter

            // Equalizer when playing
            EqualizerBars {
                anchors.centerIn: parent
                active: root.isPlaying
                visible: root.isCurrent && root.isPlaying && !root.isHovered
            }

            // Track index number
            Text {
                anchors.centerIn: parent
                text: (model.index + 1).toString()
                color: root.isCurrent ? Appearance.colors.primary : Appearance.colors.onSurfaceVariant
                font.pixelSize: Appearance.fontSize.smaller
                font.weight: Font.Medium
                visible: (!root.isCurrent || !root.isPlaying) && !root.isHovered
            }

            // Play / Pause icon on hover
            MaterialSymbol {
                anchors.centerIn: parent
                text: root.isPlaying ? "pause" : "play_arrow"
                iconSize: 20
                color: Appearance.colors.onSurface
                visible: root.isHovered
            }
        }

        // Thumbnail cover
        Rectangle {
            Layout.preferredWidth: 40
            Layout.preferredHeight: 40
            Layout.alignment: Qt.AlignVCenter
            radius: Appearance.rounding.verySmall
            color: Appearance.colors.surfaceContainerHighest
            clip: true

            Image {
                anchors.fill: parent
                source: model.hasCover ? model.coverUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                visible: model.hasCover
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: "music_note"
                iconSize: 18
                color: Appearance.colors.onSurfaceVariant
                visible: !model.hasCover
            }
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
            }

            Text {
                text: model.artists
                color: Appearance.colors.onSurfaceVariant
                font.pixelSize: Appearance.fontSize.smaller
                elide: Text.ElideRight
                Layout.fillWidth: true
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
        IconButton {
            Layout.alignment: Qt.AlignVCenter
            symbol: model.liked ? "favorite" : "favorite_border"
            size: 32
            iconSize: 18
            iconColor: model.liked ? Appearance.colors.primary : Appearance.colors.onSurfaceVariant
            activeIconColor: Appearance.colors.primary
            toggled: model.liked
            opacity: (model.liked || root.isHovered) ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 120 } }
            onClicked: backend.toggleLike(model.index)
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
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        z: -1
        onClicked: backend.play(model.index)
    }
}
