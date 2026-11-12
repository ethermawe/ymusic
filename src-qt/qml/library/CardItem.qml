import QtQuick
import QtQuick.Layouts
import ymusic.ui

Item {
    id: root

    property bool isHovered: mouseArea.containsMouse

    implicitWidth: 170
    implicitHeight: 230

    scale: isHovered ? 1.04 : 1.0
    z: isHovered ? 3 : 1
    Behavior on scale {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutBack
            easing.overshoot: 1.8
        }
    }

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
                                Appearance.colors.outlineVariant.b, 0.4)

        Behavior on color { ColorAnimation { duration: 160 } }

        // Shadow on hover
        Rectangle {
            anchors.centerIn: parent
            width: parent.width + 2
            height: parent.height + 4
            radius: parent.radius
            z: -1
            color: "#000000"
            opacity: root.isHovered ? 0.35 : 0.1
            Behavior on opacity { NumberAnimation { duration: 160 } }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        // Artwork
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: width
            Layout.alignment: Qt.AlignHCenter

            Rectangle {
                anchors.fill: parent
                radius: model.kind === "artist" ? width / 2 : Appearance.rounding.small
                color: Appearance.colors.surfaceContainerHighest
                clip: true

                Image {
                    anchors.fill: parent
                    source: model.hasCover ? model.coverUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: 200
                    sourceSize.height: 200
                    visible: model.hasCover
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: model.kind === "artist" ? "person" : "album"
                    iconSize: 36
                    color: Appearance.colors.onSurfaceVariant
                    visible: !model.hasCover
                }

                // Play overlay button on hover
                PlayHeroButton {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 8
                    size: 38
                    opacity: root.isHovered ? 1.0 : 0.0
                    scale: root.isHovered ? 1.0 : 0.7
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                    Behavior on scale {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutBack
                            easing.overshoot: 2.0
                        }
                    }
                    onClicked: backend.openCard(model.index)
                }
            }
        }

        // Title and Subtitle
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                text: model.title
                color: Appearance.colors.onSurface
                font.pixelSize: Appearance.fontSize.small
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Text {
                text: model.subtitle
                color: Appearance.colors.onSurfaceVariant
                font.pixelSize: Appearance.fontSize.smaller
                elide: Text.ElideRight
                Layout.fillWidth: true
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
