import QtQuick
import QtQuick.Layouts
import ymusic.sdk

Card {
    id: root

    property string title: ""
    property string symbol: ""
    default property alias content: body.data

    width: parent ? parent.width : 0
    implicitHeight: container.implicitHeight + 28

    Column {
        id: container
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        RowLayout {
            width: parent.width
            spacing: 8
            visible: root.title.length > 0

            MaterialSymbol {
                visible: root.symbol.length > 0
                symbol: root.symbol
                iconSize: 20
                color: Theme.colors.primary
            }

            StyledText {
                Layout.fillWidth: true
                text: root.title
                font.pixelSize: Theme.fontSize.large
                font.weight: Font.DemiBold
            }
        }

        Column {
            id: body
            width: parent.width
            spacing: 10
        }
    }
}
