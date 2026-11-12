import QtQuick
import ymusic.ui

ShaderEffect {
    id: root

    property color color: Appearance.colors.outlineVariant
    property real wavelength: 18
    property real amplitude: 2.2
    property real thickness: 1.5
    property bool running: false
    property real phase: 0
    property size itemSize: Qt.size(width, height)

    implicitHeight: 10
    implicitWidth: 100
    fragmentShader: "qrc:/shaders/wavy_line.frag.qsb"

    NumberAnimation on phase {
        from: 0
        to: 6.28318530718
        duration: 2200
        loops: Animation.Infinite
        running: root.running && root.visible && !Appearance.reduceMotion
    }
}
