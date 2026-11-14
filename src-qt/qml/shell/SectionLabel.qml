pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

Item {
    id: root

    property string text
    property bool compact: false
    property alias trailing: trailingSlot.data

    implicitHeight: compact ? 20 : 34
    implicitWidth: label.implicitWidth + 32

    StyledText {
        id: label
        visible: !root.compact
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        font.pixelSize: Appearance.fontSize.smaller
        font.weight: Font.DemiBold
        color: Appearance.colors.onSurfaceVariant
    }

    WavyLine {
        anchors.left: root.compact ? parent.left : label.right
        anchors.leftMargin: root.compact ? 12 : 10
        anchors.right: (!root.compact && trailingSlot.width > 0) ? trailingSlot.left : parent.right
        anchors.rightMargin: (!root.compact && trailingSlot.width > 0) ? 6 : 12
        anchors.verticalCenter: parent.verticalCenter
        color: Appearance.colors.outlineVariant
    }

    Row {
        id: trailingSlot
        visible: !root.compact
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
    }
}
