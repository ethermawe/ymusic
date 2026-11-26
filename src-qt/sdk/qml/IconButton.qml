import QtQuick
import QtQuick.Controls
import ymusic.sdk

AbstractButton {
    id: root

    property var scheme: Theme.colors
    property string symbol: ""
    property int size: 36
    property int iconSize: 20
    property string tooltip: ""
    property color iconColor: (scheme ? scheme.onSurface : Theme.colors.onSurface)

    implicitWidth: size
    implicitHeight: size
    hoverEnabled: true

    background: Rectangle {
        radius: root.height / 2
        color: root.down
            ? Theme.withAlpha(root.scheme ? root.scheme.onSurface : Theme.colors.onSurface, 0.16)
            : (root.hovered
                ? (root.scheme ? root.scheme.layer2Hover : Theme.colors.layer2Hover)
                : "transparent")
    }

    contentItem: MaterialSymbol {
        symbol: root.symbol
        iconSize: root.iconSize
        color: root.enabled ? root.iconColor : Theme.withAlpha(root.iconColor, 0.45)
    }

    ToolTip.visible: root.hovered && root.tooltip.length > 0
    ToolTip.delay: 450
    ToolTip.text: root.tooltip
}
