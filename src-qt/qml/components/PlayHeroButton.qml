import QtQuick
import ymusic.ui

Item {
    id: root

    property bool playing: false
    property color color: Appearance.colors.primary
    property color iconColor: Appearance.colors.onPrimary
    property real size: 44
    signal clicked()

    implicitWidth: size
    implicitHeight: size

    scale: mouseArea.pressed ? 0.90 : (mouseArea.containsMouse ? 1.06 : 1.0)
    Behavior on scale { Bounce {} }

    MaterialShape {
        id: shapeItem
        anchors.fill: parent
        shape: "softCookie"
        morphTo: "cookie9"
        morph: root.playing ? 1 : 0
        Behavior on morph {
            NumberAnimation { duration: Appearance.reduceMotion ? 0 : 400; easing.type: Easing.InOutCubic }
        }
        color: mouseArea.containsMouse ? Appearance.colors.primaryHover : root.color
        spinAngle: spinAnim.currentAngle

        Behavior on color { ElementMoveFastColor {} }
    }

    NumberAnimation {
        id: spinAnim
        property real currentAngle: 0
        target: spinAnim
        property: "currentAngle"
        from: 0
        to: 360
        duration: 9000
        loops: Animation.Infinite
        running: root.visible && !Appearance.reduceMotion
        onRunningChanged: if (running) paused = !root.playing
    }

    Connections {
        target: root
        function onPlayingChanged() {
            if (spinAnim.running) spinAnim.paused = !root.playing;
        }
    }

    Item {
        id: glyph
        anchors.centerIn: parent
        width: Math.round(root.size * 0.52)
        height: width
        MaterialSymbol {
            anchors.centerIn: parent
            text: "play_arrow"
            iconSize: glyph.width
            color: root.iconColor
            opacity: root.playing ? 0 : 1
            scale: root.playing ? 0.65 : 1
            Behavior on opacity { NumberAnimation { duration: Appearance.reduceMotion ? 0 : 180 } }
            Behavior on scale { NumberAnimation { duration: Appearance.reduceMotion ? 0 : 280; easing.type: Easing.OutCubic } }
        }
        MaterialSymbol {
            anchors.centerIn: parent
            text: "pause"
            iconSize: glyph.width
            color: root.iconColor
            opacity: root.playing ? 1 : 0
            scale: root.playing ? 1 : 0.65
            Behavior on opacity { NumberAnimation { duration: Appearance.reduceMotion ? 0 : 180 } }
            Behavior on scale { NumberAnimation { duration: Appearance.reduceMotion ? 0 : 280; easing.type: Easing.OutCubic } }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
