import QtQuick
import QtQuick.Effects
import ymusic.ui

Item {
    id: root

    property alias source: srcImage.source
    property alias status: srcImage.status
    property alias asynchronous: srcImage.asynchronous
    property alias cache: srcImage.cache
    property alias fillMode: srcImage.fillMode
    property alias sourceSize: srcImage.sourceSize
    property real radius: Appearance.rounding.small
    property string fallbackSymbol: "music_note"
    property real fallbackIconSize: Math.min(width, height) * 0.45
    property color fallbackColor: Appearance.colors.surfaceContainerHighest
    property real borderWidth: 0
    property color borderColor: Qt.rgba(1, 1, 1, 0.08)

    readonly property bool hasValidImage: srcImage.status === Image.Ready && source.toString().length > 0

    implicitWidth: 40
    implicitHeight: 40

    // Background placeholder with true rounded corners
    Rectangle {
        id: bgPlaceholder
        anchors.fill: parent
        radius: root.radius
        color: root.fallbackColor

        MaterialSymbol {
            anchors.centerIn: parent
            text: root.fallbackSymbol
            iconSize: root.fallbackIconSize
            color: Appearance.colors.onSurfaceVariant
            visible: !root.hasValidImage
        }
    }

    // Source Image (hidden from direct render, texture fed into MultiEffect)
    Image {
        id: srcImage
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        visible: false
    }

    // Mask Item with smooth rounded corners
    Rectangle {
        id: maskRect
        anchors.fill: parent
        radius: root.radius
        color: "#ffffff"
        layer.enabled: true
        visible: false
    }

    // Hardware GPU masked image with smooth subpixel rounded corners
    MultiEffect {
        anchors.fill: parent
        source: srcImage
        maskEnabled: true
        maskSource: maskRect
        visible: root.hasValidImage
    }

    // Optional border overlay with matching radius
    Rectangle {
        id: borderOverlay
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: root.borderWidth
        border.color: root.borderColor
        visible: root.borderWidth > 0
        z: 2
    }
}
