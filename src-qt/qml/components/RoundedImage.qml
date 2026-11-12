import QtQuick
import ymusic.ui

Item {
    id: root

    property url source: ""
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
    property bool fadeIn: true
    property int maximumPixelSize: 1536

    readonly property int decodePixelSize: {
        const dpr = Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1;
        const requested = Math.ceil(Math.max(width, height) * dpr);
        return Math.min(maximumPixelSize, Math.max(32, requested));
    }

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

    // Image provides its texture directly: no offscreen image/mask layers.
    Image {
        id: srcImage
        source: appSettings.coversEnabled ? root.source : ""
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        sourceSize.width: root.decodePixelSize
        sourceSize.height: root.decodePixelSize
        visible: false
    }

    ShaderEffect {
        anchors.fill: parent
        property variant source: srcImage
        property size itemSize: Qt.size(width, height)
        property real radius: root.radius
        readonly property real imageAspect: srcImage.implicitHeight > 0 ? srcImage.implicitWidth / srcImage.implicitHeight : 1
        readonly property real itemAspect: height > 0 ? width / height : 1
        property vector2d uvScale: root.fillMode === Image.PreserveAspectCrop
            ? (imageAspect > itemAspect ? Qt.vector2d(itemAspect / imageAspect, 1) : Qt.vector2d(1, imageAspect / itemAspect))
            : Qt.vector2d(1, 1)
        fragmentShader: "qrc:/shaders/rounded_image.frag.qsb"
        visible: root.hasValidImage
        opacity: root.hasValidImage ? 1 : 0
        Behavior on opacity {
            enabled: root.fadeIn && !Appearance.reduceMotion
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
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
