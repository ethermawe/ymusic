pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

Item {
    id: root

    property string shape: "cookie9"
    property bool keepsShape: false
    property string hoverShape
    property bool hovered: false
    property string symbol
    property real size: 40
    property real iconSize: Math.round(size * 0.5)
    property real fill: 1
    property color color: Appearance.colors.secondaryContainer
    property color iconColor: Appearance.colors.onSecondaryContainer

    readonly property string target: hovered && hoverShape.length > 0 ? hoverShape : shape
    property string fromShape: target
    property real progress: 1
    property bool settled: false

    implicitWidth: size
    implicitHeight: size

    Component.onCompleted: settled = true

    onTargetChanged: {
        if (!settled || Appearance.performanceMode) {
            fromShape = target
            progress = 1
            return
        }
        fromShape = progress >= 0.5 ? body.morphTo : body.shape
        progress = 0
        settle.restart()
    }

    NumberAnimation {
        id: settle
        target: root
        property: "progress"
        to: 1
        duration: 460
        easing.type: Easing.OutBack
        easing.overshoot: 2.2
    }

    MaterialShape {
        id: body
        anchors.fill: parent
        keepsShape: root.keepsShape
        shape: root.fromShape
        morphTo: root.target
        morph: root.progress
        color: root.color
        extent: 0.92
        spinAngle: root.hovered ? 24 : 0

        Behavior on spinAngle {
            enabled: !Appearance.performanceMode
            Bounce {}
        }
        Behavior on color {
            ElementMoveFastColor {}
        }
    }

    MaterialSymbol {
        anchors.centerIn: parent
        text: root.symbol
        iconSize: root.iconSize
        fill: root.fill
        color: root.iconColor
        rotation: root.hovered ? -10 : 0

        Behavior on rotation {
            enabled: !Appearance.performanceMode
            Bounce {}
        }
    }
}
