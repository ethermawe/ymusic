pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

// Compatibility wrapper delegating legacy RoundedImage usages to Swiftify's ArtworkImage.
ArtworkImage {
    id: root

    property string fallbackSymbol: "music_note"
    property real fallbackIconSize: Math.min(width, height) * 0.45
    property color fallbackColor: Appearance.colors.surfaceContainerHighest
    property bool fadeIn: true
    property int fillMode: Image.PreserveAspectCrop
    property size sourceSize: Qt.size(0, 0)
    property int status: ready ? Image.Ready : Image.Null
    readonly property bool hasValidImage: ready

    maximumPixelSize: sourceSize.width > 0 || sourceSize.height > 0 ? Math.max(sourceSize.width, sourceSize.height) : 2048
    placeholderSymbol: fallbackSymbol
    fades: fadeIn
}
