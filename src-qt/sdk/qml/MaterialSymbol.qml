import QtQuick
import ymusic.sdk

Text {
    property string symbol: ""
    property int iconSize: 20
    property bool filled: false

    text: symbol
    font.family: Theme.iconFontFamily
    font.pixelSize: iconSize
    color: Theme.colors.onSurface
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    renderType: Text.QtRendering
}
