import QtQuick
import ymusic.sdk

StyledText {
    width: parent ? parent.width : implicitWidth
    wrapMode: Text.WordWrap
    font.pixelSize: Theme.fontSize.smaller
    color: Theme.colors.onSurfaceVariant
}
