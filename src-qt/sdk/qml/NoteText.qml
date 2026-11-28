import QtQuick
import ymusic.sdk

StyledText {
    width: parent ? parent.width : implicitWidth
    leftPadding: 12
    rightPadding: 12
    topPadding: 4
    bottomPadding: 8
    wrapMode: Text.Wrap
    font.pixelSize: Theme.fontSize.smaller
    color: Theme.colors.onSurfaceVariant
}
