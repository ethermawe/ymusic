import QtQuick
import ymusic.ui

Item {
    id: root
    property var modApi: null
    property var slotContext: ({})
    property bool showBadge: modApi ? Boolean(modApi.storageGet("showImmersiveBadge", true)) : true

    Rectangle {
        visible: root.showBadge && root.modApi && root.modApi.hasTrack
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 24
        width: badgeText.implicitWidth + 24
        height: 30
        radius: 15
        color: Qt.rgba(0, 0, 0, 0.36)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.16)
        opacity: root.slotContext && root.slotContext.controlsOpacity !== undefined ? root.slotContext.controlsOpacity : 1

        StyledText {
            id: badgeText
            anchors.centerIn: parent
            text: "Hello Mod • " + (root.modApi ? root.modApi.storageGet("playedCount", 0) : 0) + " треков"
            font.pixelSize: Appearance.fontSize.smaller
            color: "white"
        }
    }
}
