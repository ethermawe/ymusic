import QtQuick
import ymusic.sdk

Rectangle {
    id: root

    property string text: ""
    property string symbol: ""
    property bool selected: false
    property bool clickable: true

    signal clicked()

    readonly property color fgColor: selected
        ? Theme.colors.onPrimaryContainer
        : Theme.colors.onSurface

    implicitWidth: Math.max(40, contentRow.implicitWidth + 24)
    implicitHeight: 32
    radius: Theme.rounding.small
    color: selected
        ? (mouseArea.containsMouse && clickable
            ? Theme.colors.primaryContainerHover
            : Theme.colors.primaryContainer)
        : (mouseArea.containsMouse && clickable
            ? Theme.colors.layer2Hover
            : Theme.colors.surfaceContainerHigh)
    border.width: selected ? 0 : 1
    border.color: Theme.colors.outlineVariant
    opacity: !enabled ? 0.45 : (mouseArea.pressed && clickable ? 0.86 : 1.0)

    Behavior on color {
        enabled: !Theme.performanceMode
        ColorAnimation { duration: 120 }
    }

    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: root.symbol.length > 0 && root.text.length > 0 ? 6 : 0

        MaterialSymbol {
            visible: root.symbol.length > 0
            anchors.verticalCenter: parent.verticalCenter
            symbol: root.symbol
            iconSize: 16
            color: root.fgColor
        }

        StyledText {
            visible: root.text.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            font.pixelSize: Theme.fontSize.small
            font.weight: root.selected ? Font.DemiBold : Font.Medium
            color: root.fgColor
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled && root.clickable
        cursorShape: root.clickable && root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }
}
