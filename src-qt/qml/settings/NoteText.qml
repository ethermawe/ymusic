pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

StyledText {
    width: parent ? parent.width : 0
    leftPadding: 12
    rightPadding: 12
    topPadding: 4
    bottomPadding: 8
    wrapMode: Text.Wrap
    font.pixelSize: Appearance.fontSize.smaller
    color: Appearance.colors.onSurfaceVariant
}
