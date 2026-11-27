import QtQuick
import ymusic.sdk

Rectangle {
    id: root

    property string text: ""
    property string symbol: ""
    // "primary" | "secondary" | "tertiary" | "error" | "neutral"
    property string tone: "primary"

    readonly property color bgColor: {
        if (tone === "secondary") return Theme.colors.secondaryContainer;
        if (tone === "tertiary") return Theme.colors.tertiaryContainer;
        if (tone === "error") return Theme.colors.errorContainer;
        if (tone === "neutral") return Theme.colors.surfaceContainerHigh;
        return Theme.colors.primaryContainer;
    }

    readonly property color fgColor: {
        if (tone === "secondary") return Theme.colors.onSurface;
        if (tone === "tertiary") return Theme.colors.onTertiaryContainer;
        if (tone === "error") return Theme.colors.onErrorContainer;
        if (tone === "neutral") return Theme.colors.onSurfaceVariant;
        return Theme.colors.onPrimaryContainer;
    }

    implicitWidth: Math.max(22, contentRow.implicitWidth + 14)
    implicitHeight: 22
    radius: height / 2
    color: bgColor

    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: root.symbol.length > 0 && root.text.length > 0 ? 4 : 0

        MaterialSymbol {
            visible: root.symbol.length > 0
            anchors.verticalCenter: parent.verticalCenter
            symbol: root.symbol
            iconSize: 13
            color: root.fgColor
        }

        StyledText {
            visible: root.text.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            font.pixelSize: Theme.fontSize.smallest
            font.weight: Font.DemiBold
            color: root.fgColor
        }
    }
}
