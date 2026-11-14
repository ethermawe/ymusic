pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

StyledText {
    property string level: "title"

    font.pixelSize: level === "display" ? Appearance.fontSize.display
                  : level === "headline" ? Appearance.fontSize.headline : Appearance.fontSize.title
    font.weight: Font.Bold
    font.letterSpacing: level === "display" ? -0.4 : 0
    font.variableAxes: ({ "ROND": 100, "wdth": 110, "wght": 720 })
}
