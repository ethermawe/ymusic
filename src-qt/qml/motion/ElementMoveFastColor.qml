pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

ColorAnimation {
    duration: Appearance.duration(200)
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Appearance.curves.expressiveEffects
}
