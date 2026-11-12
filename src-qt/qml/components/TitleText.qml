import QtQuick
import ymusic.ui

StyledText {
    id: root

    property string level: "title" // "display", "headline", "title"

    font.pixelSize: level === "display" ? Appearance.fontSize.display
                  : level === "headline" ? Appearance.fontSize.headline
                  : Appearance.fontSize.title
    font.weight: Font.Bold
    font.letterSpacing: level === "display" ? -0.5 : 0
}
