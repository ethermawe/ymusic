import QtQuick
import QtQuick.Layouts
import ymusic.ui

Item {
    id: root

    property bool isHovered: mouseArea.containsMouse
    property bool isPressed: mouseArea.pressed
    readonly property bool isArtist: model.kind === "artist"

    implicitWidth: 174
    implicitHeight: 242

    // Swiftify hover lift & press squish
    scale: isPressed ? 0.95 : (isHovered ? 1.03 : 1.0)
    opacity: isPressed ? 0.88 : 1.0
    z: isHovered ? 5 : 1

    Behavior on scale {
        Bounce {}
    }

    Behavior on opacity {
        NumberAnimation { duration: 120 }
    }

    // 3D Tilt towards mouse pointer (like Swiftify MediaCard)
    property real tiltAcross: isHovered ? (mouseArea.mouseX / Math.max(1, width) - 0.5) * 10 : 0
    property real tiltDown: isHovered ? (0.5 - mouseArea.mouseY / Math.max(1, height)) * 8 : 0

    Behavior on tiltAcross {
        SpringAnimation { spring: 5; damping: 0.35; epsilon: 0.01 }
    }
    Behavior on tiltDown {
        SpringAnimation { spring: 5; damping: 0.35; epsilon: 0.01 }
    }

    transform: [
        Rotation {
            origin.x: root.width / 2
            origin.y: root.height / 2
            axis { x: 0; y: 1; z: 0 }
            angle: root.tiltAcross
        },
        Rotation {
            origin.x: root.width / 2
            origin.y: root.height / 2
            axis { x: 1; y: 0; z: 0 }
            angle: root.tiltDown
        }
    ]

    // Background card container
    Rectangle {
        id: bg
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: root.isHovered ? Appearance.colors.surfaceContainerHigh : Appearance.colors.surfaceContainerLow
        border.width: 1
        border.color: root.isHovered
                      ? Qt.rgba(1, 1, 1, 0.12)
                      : Qt.rgba(Appearance.colors.outlineVariant.r,
                                Appearance.colors.outlineVariant.g,
                                Appearance.colors.outlineVariant.b, 0.35)

        Behavior on color {
            ElementMoveFastColor {}
        }

        // Soft drop shadow
        Rectangle {
            anchors.centerIn: parent
            width: parent.width + 4
            height: parent.height + 6
            radius: parent.radius
            z: -1
            color: "#000000"
            opacity: root.isHovered ? 0.35 : 0.08
            Behavior on opacity { NumberAnimation { duration: 160 } }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        // Artwork Container
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: width
            Layout.alignment: Qt.AlignHCenter

            RoundedImage {
                id: artBox
                anchors.fill: parent
                radius: root.isArtist ? width / 2 : Appearance.rounding.small
                source: model.hasCover ? model.coverUrl : ""
                fallbackSymbol: root.isArtist ? "artists" : "album"
                fallbackIconSize: 40
                sourceSize.width: 240
                sourceSize.height: 240

                // Swiftify Badge Overlay (Bottom-Right circle with Play icon)
                Rectangle {
                    id: badge
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 8
                    width: 36
                    height: 36
                    radius: 18
                    color: Appearance.colors.primary
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.2)
                    opacity: root.isHovered ? 1.0 : 0.0
                    scale: root.isHovered ? 1.0 : 0.7
                    visible: opacity > 0.0
                    z: 5

                    Behavior on opacity {
                        NumberAnimation { duration: 160 }
                    }
                    Behavior on scale {
                        Bounce {}
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "play_arrow"
                        iconSize: 22
                        color: Appearance.colors.onPrimary
                    }
                }
            }
        }

        // Title and Subtitle (Swiftify typography)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                text: model.title
                color: Appearance.colors.onSurface
                font.pixelSize: Appearance.fontSize.small
                font.weight: Font.DemiBold
                horizontalAlignment: root.isArtist ? Text.AlignHCenter : Text.AlignLeft
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            Text {
                text: model.subtitle
                color: Appearance.colors.onSurfaceVariant
                font.pixelSize: Appearance.fontSize.smaller
                horizontalAlignment: root.isArtist ? Text.AlignHCenter : Text.AlignLeft
                elide: Text.ElideRight
                Layout.fillWidth: true
                visible: model.subtitle.length > 0
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: backend.openCard(model.index)
    }
}
