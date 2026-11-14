pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

NumberAnimation {
    duration: Appearance.motion(350)
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Appearance.curves.expressiveFastSpatial
}
