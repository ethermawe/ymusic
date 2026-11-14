pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

ShaderEffect {
    id: root

    property color color: Appearance.colors.primary
    property bool hovered: false
    property bool pressed: false

    property size itemSize: Qt.size(width, height)
    property real cornerRadius: Math.min(width, height) / 2
    property real amplitude: appSettings.noShapes ? 0 : (pressed ? 4 : (hovered ? 3.2 : 2.2))
    property real wavelength: 15
    readonly property real phase: drift.value

    Behavior on amplitude {
        enabled: !Appearance.performanceMode
        Bounce {}
    }

    Drift {
        id: drift
        active: root.hovered && root.visible && !appSettings.noShapes
        speed: 2 * Math.PI / 1.6
    }

    fragmentShader: "qrc:/shaders/wavy_pill.frag.qsb"
}
