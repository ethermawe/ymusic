pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

ShapeButton {
    id: root

    property real size: 48
    property bool playing: backend.playing
    property color iconColor: Appearance.colors.onPrimary
    property real iconSize: Math.round(size * 0.52)

    implicitWidth: size
    implicitHeight: size

    shape: "softCookie"
    morphTo: "cookie9"
    morphed: playing
    spinRate: 25
    tooltip: playing ? qsTr("Пауза") : qsTr("Воспроизвести")

    onPlayingChanged: if (!Appearance.performanceMode) pop.restart()
    onClicked: if (!playing) UiState.burst(root, "play")

    contentItem: Item {
        MaterialSymbol {
            id: glyph
            anchors.centerIn: parent
            text: root.playing ? "pause" : "play_arrow"
            iconSize: root.iconSize
            fill: 1
            color: root.iconColor
        }
    }

    NumberAnimation {
        id: pop
        target: glyph
        property: "scale"
        from: 0.55
        to: 1
        duration: 480
        easing.type: Easing.OutBack
        easing.overshoot: 2.6
    }
}
