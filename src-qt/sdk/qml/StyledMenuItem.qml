import QtQuick
import QtQuick.Controls
import ymusic.sdk

MenuItem {
    id: root

    property string symbol: ""
    property bool destructive: false

    implicitHeight: 36

    background: Rectangle {
        radius: Theme.rounding.small
        color: root.highlighted ? Theme.colors.layer2Hover : "transparent"
    }

    contentItem: Row {
        spacing: 10
        leftPadding: 8
        rightPadding: 8

        MaterialSymbol {
            visible: root.symbol.length > 0
            symbol: root.symbol
            iconSize: 18
            color: root.destructive ? Theme.colors.error : Theme.colors.onSurfaceVariant
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            text: root.text
            color: root.destructive ? Theme.colors.error : Theme.colors.onSurface
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
