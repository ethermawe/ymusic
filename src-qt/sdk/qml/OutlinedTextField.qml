import QtQuick
import QtQuick.Controls
import ymusic.sdk

TextField {
    id: root

    property alias placeholder: root.placeholderText

    color: Theme.colors.onSurface
    placeholderTextColor: Theme.colors.onSurfaceVariant
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize.normal
    leftPadding: 12
    rightPadding: 12
    topPadding: 8
    bottomPadding: 8
    implicitHeight: 40

    background: Rectangle {
        radius: Theme.rounding.small
        color: Theme.colors.surfaceContainerLowest
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? Theme.colors.primary : Theme.colors.outlineVariant
    }
}
