import QtQuick
import QtQuick.Controls
import ymusic.sdk

AbstractButton {
    id: root

    enum Variant {
        Filled,
        Tonal,
        Outlined,
        Text
    }

    property int variant: TextButton.Filled
    property string symbol: ""
    property int iconSize: 18

    implicitWidth: Math.max(48, row.implicitWidth + 28)
    implicitHeight: 38
    hoverEnabled: true

    readonly property color fgColor: {
        if (variant === TextButton.Filled) return Theme.colors.onPrimary;
        if (variant === TextButton.Tonal) return Theme.colors.onPrimaryContainer;
        return Theme.colors.primary;
    }

    readonly property color bgColor: {
        if (variant === TextButton.Filled) return Theme.colors.primary;
        if (variant === TextButton.Tonal) return Theme.colors.primaryContainer;
        return "transparent";
    }

    background: Rectangle {
        radius: Theme.rounding.full
        color: root.bgColor
        border.width: root.variant === TextButton.Outlined ? 1 : 0
        border.color: Theme.colors.outlineVariant
        opacity: !root.enabled ? 0.45 : (root.down ? 0.85 : (root.hovered ? 0.92 : 1.0))
    }

    contentItem: Item {
        implicitWidth: row.implicitWidth
        implicitHeight: row.implicitHeight

        Row {
            id: row
            anchors.centerIn: parent
            spacing: root.symbol.length > 0 && root.text.length > 0 ? 8 : 0

            MaterialSymbol {
                visible: root.symbol.length > 0
                symbol: root.symbol
                iconSize: root.iconSize
                color: root.fgColor
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                visible: root.text.length > 0
                text: root.text
                font.weight: Font.Medium
                color: root.fgColor
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
