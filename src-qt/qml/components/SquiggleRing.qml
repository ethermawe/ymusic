pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

ShaderEffect {
    id: root

    property color color: Appearance.colors.primary
    property color trackColor: Qt.rgba(color.r, color.g, color.b, 0.24)
    property real thickness: 2.5
    property real amplitude: 2
    property real wavelength: 16
    property real progress: 1
    property real speed: 0.35

    property size itemSize: Qt.size(width, height)
    property real radius: Math.max(1, Math.min(width, height) / 2 - amplitude - thickness / 2 - 0.5)
    property real waves: appSettings.noShapes ? 0 : Math.max(5, Math.round(2 * Math.PI * radius / wavelength))
    property real phase: visible ? (waves * speed * UiState.spin) % (2 * Math.PI) : 0

    fragmentShader: "qrc:/shaders/squiggle_ring.frag.qsb"
}
