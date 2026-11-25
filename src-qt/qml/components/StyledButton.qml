import QtQuick
import QtQuick.Controls.Basic
import ymusic.ui

Button {
    id: root
    implicitHeight: 42
    implicitWidth: Math.max(88, implicitContentWidth + 32)
    leftPadding: 16
    rightPadding: 16
    hoverEnabled: true
    opacity: enabled ? 1 : 0.45
    scale: down ? 0.96 : (hovered ? 1.015 : 1)

    Behavior on scale {
        enabled: !Appearance.performanceMode
        Bounce {}
    }
    contentItem: Text {
        text: root.text
        font.family: Appearance.fontFamily
        font.pixelSize: Appearance.fontSize.small
        font.weight: Font.Medium
        color: root.highlighted ? Appearance.colors.onPrimary : Appearance.colors.onSurface
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: Rectangle {
        radius: Appearance.rounding.full
        color: root.highlighted
            ? (root.down || root.hovered ? Appearance.colors.primaryHover : Appearance.colors.primary)
            : (root.down || root.hovered ? Appearance.colors.surfaceContainerHighest : Appearance.colors.surfaceContainerHigh)
        border.width: root.visualFocus ? 2 : 0
        border.color: Appearance.colors.primary
        Behavior on color { ColorAnimation { duration: Appearance.duration(120) } }
    }
}
