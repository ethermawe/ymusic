import QtQuick
import QtQuick.Controls.Basic
import ymusic.ui

CheckBox {
    id: root
    implicitHeight: 40
    spacing: 12
    leftPadding: 0
    rightPadding: 4
    hoverEnabled: true
    opacity: enabled ? 1 : 0.45
    indicator: Rectangle {
        x: root.leftPadding
        y: (root.height - height) / 2
        implicitWidth: 22
        implicitHeight: 22
        radius: 6
        color: root.checked ? Appearance.colors.primary : Appearance.colors.surfaceContainerLowest
        border.width: root.checked ? 0 : 2
        border.color: root.visualFocus || root.hovered ? Appearance.colors.primary : Appearance.colors.outline
        MaterialSymbol {
            anchors.centerIn: parent
            text: "check"
            iconSize: 17
            color: Appearance.colors.onPrimary
            visible: root.checked
        }
    }
    contentItem: Text {
        leftPadding: root.indicator.width + root.spacing
        text: root.text
        font.family: Appearance.fontFamily
        font.pixelSize: Appearance.fontSize.small
        color: Appearance.colors.onSurface
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
}
