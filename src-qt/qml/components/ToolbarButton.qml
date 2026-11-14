pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

IconButton {
    id: root

    enum Effect {
        Pop,
        NudgeLeft,
        NudgeRight,
        Spin
    }

    property int effect: ToolbarButton.Pop
    property string shape: "cookie9"
    property real shapeAngle: 0
    property bool turnsOnHover: true
    property color shapeColor: scheme.surfaceContainerHigh
    property color shapeHoverColor: scheme.secondaryContainer
    property color shapePressedColor: scheme.secondaryContainerActive

    size: 46
    iconSize: 26
    colBackgroundHover: "transparent"
    colBackgroundToggledHover: "transparent"
    rippleEnabled: false
    scale: down ? 0.86 : (hovered && enabled ? 1.08 : 1)

    onClicked: {
        if (Appearance.performanceMode) {
            return
        }
        switch (effect) {
        case ToolbarButton.NudgeLeft:
        case ToolbarButton.NudgeRight:
            nudge.restart()
            break
        case ToolbarButton.Spin:
            spin.restart()
            break
        default:
            popIn.restart()
        }
    }

    transform: [
        Translate {
            id: shift
        },
        Rotation {
            id: turn
            origin.x: root.width / 2
            origin.y: root.height / 2
        },
        Scale {
            id: pop
            origin.x: root.width / 2
            origin.y: root.height / 2
        }
    ]

    MaterialShape {
        id: backing

        anchors.centerIn: parent
        width: root.width
        height: root.height
        z: -0.5
        shape: root.shape
        spinAngle: root.shapeAngle + drift.value
        color: root.down ? root.shapePressedColor : (root.hovered && root.enabled ? root.shapeHoverColor : root.shapeColor)
        opacity: root.enabled ? 1 : 0.38
        scale: root.hovered && root.enabled ? 1 : 0.9

        Behavior on opacity {
            NumberAnimation { duration: Appearance.duration(140); easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            enabled: !Appearance.performanceMode
            Bounce {}
        }

        Behavior on color {
            ElementMoveFastColor {}
        }

        Drift {
            id: drift
            active: root.turnsOnHover && root.hovered && root.visible
            speed: 40
            period: 360
        }
    }

    SequentialAnimation {
        id: nudge
        NumberAnimation {
            target: shift
            property: "x"
            to: root.effect === ToolbarButton.NudgeLeft ? -6 : 6
            duration: 90
            easing.type: Easing.OutCubic
        }
        NumberAnimation { target: shift; property: "x"; to: 0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
    }

    NumberAnimation {
        id: spin
        target: turn
        property: "angle"
        from: 0
        to: 180
        duration: 520
        easing.type: Easing.OutBack
        easing.overshoot: 1.6
    }

    SequentialAnimation {
        id: popIn
        ParallelAnimation {
            NumberAnimation { target: pop; property: "xScale"; to: 1.22; duration: 100; easing.type: Easing.OutCubic }
            NumberAnimation { target: pop; property: "yScale"; to: 1.22; duration: 100; easing.type: Easing.OutCubic }
        }
        ParallelAnimation {
            NumberAnimation { target: pop; property: "xScale"; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.6 }
            NumberAnimation { target: pop; property: "yScale"; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.6 }
        }
    }
}
