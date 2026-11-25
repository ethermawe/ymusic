pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

Item {
    id: root

    property bool shown: false
    property bool everShown: false
    property string transitionKey: ""
    property real enterOffsetY: 12
    property real enterScaleFrom: 0.988

    property bool _settled: false
    property real _offsetY: 0
    property real _scaleValue: 1

    visible: shown
    enabled: shown
    opacity: shown ? 1 : 0
    transformOrigin: Item.Center
    scale: _scaleValue
    transform: Translate {
        y: root._offsetY
    }

    function _snapState(visibleState: bool) {
        enterAnim.stop()
        opacity = visibleState ? 1 : 0
        _offsetY = 0
        _scaleValue = 1
    }

    function triggerEnter() {
        if (!shown) return
        if (Appearance.performanceMode || Appearance.reduceMotion) {
            _snapState(true)
            return
        }
        enterAnim.stop()
        opacity = 0.45
        _offsetY = enterOffsetY
        _scaleValue = enterScaleFrom
        enterAnim.start()
    }

    Component.onCompleted: {
        _settled = true
        if (shown) everShown = true
        _snapState(shown)
    }

    onShownChanged: {
        if (shown) everShown = true
        if (!_settled) return
        if (shown) {
            triggerEnter()
        } else {
            _snapState(false)
        }
    }

    onTransitionKeyChanged: {
        if (!_settled || !shown) return
        triggerEnter()
    }

    ParallelAnimation {
        id: enterAnim

        NumberAnimation {
            target: root
            property: "opacity"
            to: 1
            duration: Appearance.duration(170)
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "_offsetY"
            to: 0
            duration: Appearance.motion(240)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.curves.expressiveFastSpatial
        }
        NumberAnimation {
            target: root
            property: "_scaleValue"
            to: 1
            duration: Appearance.motion(240)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.curves.expressiveFastSpatial
        }
    }
}
