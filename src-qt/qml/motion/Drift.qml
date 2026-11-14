pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

FrameAnimation {
    id: root

    property bool active: false
    property real speed: 1
    property real period: 2 * Math.PI
    property real value: 0
    property real rate: active && !Appearance.reduceMotion && !UiState.pointerResting ? speed : 0

    Behavior on rate {
        NumberAnimation { duration: 650; easing.type: Easing.InOutSine }
    }

    running: Math.abs(rate) > 0.0001
    onTriggered: value = (value + rate * frameTime) % period
}
