import QtQuick
import QtQuick.Controls.Basic
import ymusic.ui

ComboBox {
    id: root
    implicitHeight: 46
    implicitWidth: 240
    leftPadding: 14
    rightPadding: 44
    hoverEnabled: true
    opacity: enabled ? 1 : 0.45
    contentItem: Text {
        text: root.displayText
        color: Appearance.colors.onSurface
        font.family: Appearance.fontFamily
        font.pixelSize: Appearance.fontSize.small
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: MaterialSymbol {
        x: root.width - width - 14
        y: (root.height - height) / 2
        text: "expand_more"
        iconSize: 20
        color: Appearance.colors.onSurfaceVariant
        rotation: root.popup.visible ? 180 : 0
        Behavior on rotation { NumberAnimation { duration: Appearance.motion(150); easing.type: Easing.OutCubic } }
    }
    background: Rectangle {
        radius: Appearance.rounding.small
        color: root.hovered ? Appearance.colors.surfaceContainerHighest : Appearance.colors.surfaceContainerHigh
        border.width: 1
        border.color: root.visualFocus || root.popup.visible ? Appearance.colors.primary : Appearance.colors.outlineVariant
    }
    delegate: ItemDelegate {
        id: option
        required property int index
        required property var modelData
        width: root.width - 12
        height: 42
        highlighted: root.highlightedIndex === index
        contentItem: Text {
            text: root.textAt(option.index)
            font.family: Appearance.fontFamily
            font.pixelSize: Appearance.fontSize.small
            font.weight: root.currentIndex === option.index ? Font.DemiBold : Font.Normal
            color: root.currentIndex === option.index ? Appearance.colors.onPrimaryContainer : Appearance.colors.onSurface
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            radius: Appearance.rounding.small
            color: root.currentIndex === option.index ? Appearance.colors.primaryContainer
                 : (option.highlighted ? Appearance.colors.surfaceContainerHighest : "transparent")
        }
    }
    popup: Popup {
        y: root.height + 6
        width: root.width
        padding: 6
        implicitHeight: Math.min(280, options.contentHeight + 12)
        contentItem: ListView {
            id: options
            clip: true
            implicitHeight: contentHeight
            model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds
            ScrollIndicator.vertical: ScrollIndicator {}
        }
        background: Rectangle {
            radius: Appearance.rounding.normal
            color: Appearance.colors.surfaceContainerHigh
            border.width: 1
            border.color: Appearance.colors.outlineVariant
        }
    }
}
