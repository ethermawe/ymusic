import QtQuick
import ymusic.sdk

Column {
    id: root

    property string title: ""
    property string symbol: ""
    default property alias content: rows.data

    width: parent ? parent.width : 0
    spacing: 8

    Row {
        spacing: 10
        leftPadding: 2
        visible: root.title.length > 0

        HoverHandler {
            id: headerHover
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.symbol.length > 0
            width: 34
            height: 34
            radius: headerHover.hovered ? 11 : 17
            color: Theme.colors.primaryContainer

            Behavior on radius {
                enabled: !Theme.performanceMode && !Theme.reduceMotion
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                symbol: root.symbol
                iconSize: 18
                color: Theme.colors.onPrimaryContainer
            }
        }

        TitleText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.title
            font.pixelSize: Theme.fontSize.larger || (Theme.fontSize.large + 2)
        }
    }

    Rectangle {
        width: parent.width
        implicitHeight: rows.implicitHeight + 16
        radius: Theme.rounding.normal
        color: Theme.colors.layer1

        Column {
            id: rows
            x: 8
            y: 8
            width: parent.width - 16
            spacing: 2
        }
    }
}
