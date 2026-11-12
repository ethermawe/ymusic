import QtQuick
import ymusic.ui

IconButton {
    id: root

    property int effect: TransportButton.None

    enum Effect { None, NudgeLeft, NudgeRight, Bounce }

    onClicked: {
        if (effect === TransportButton.Bounce) {
            bounce.restart();
        } else if (effect === TransportButton.NudgeLeft || effect === TransportButton.NudgeRight) {
            nudge.restart();
        }
    }

    transform: Translate { id: shift }

    SequentialAnimation {
        id: nudge
        NumberAnimation {
            target: shift
            property: "x"
            to: root.effect === TransportButton.NudgeLeft ? -4 : 4
            duration: 90
            easing.type: Easing.OutCubic
        }
        NumberAnimation { target: shift; property: "x"; to: 0; duration: 300; easing.type: Easing.OutBack }
    }

    SequentialAnimation {
        id: bounce
        NumberAnimation { target: root; property: "scale"; to: 1.14; duration: 100; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "scale"; to: 1; duration: 300; easing.type: Easing.OutBack }
    }
}
