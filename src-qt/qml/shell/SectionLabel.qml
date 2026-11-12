import QtQuick
import ymusic.ui

Item {
    id: root

    property string text
    property alias trailing: trailingSlot.data

    implicitHeight: 36
    implicitWidth: 180

    Row {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 12
        spacing: 10

        StyledText {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            font.pixelSize: Appearance.fontSize.smallest
            font.weight: Font.Bold
            font.capitalization: Font.AllUppercase
            color: Appearance.colors.onSurfaceVariant
            opacity: 0.8
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width - label.width - trailingSlot.width - 24)
            height: 1
            color: Qt.rgba(Appearance.colors.outlineVariant.r,
                           Appearance.colors.outlineVariant.g,
                           Appearance.colors.outlineVariant.b, 0.4)
        }

        Row {
            id: trailingSlot
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
