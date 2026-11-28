import QtQuick
import QtQuick.Controls
import ymusic.sdk

Menu {
    id: root

    padding: 6

    background: Rectangle {
        implicitWidth: 200
        radius: Theme.rounding.normal
        color: Theme.colors.surfaceContainerHigh
        border.width: 1
        border.color: Theme.colors.outlineVariant
    }
}
