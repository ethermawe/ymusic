import QtQuick
import ymusic.ui

NumberAnimation {
    duration: Appearance.motion(500)
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Appearance.curves.expressiveDefaultSpatial
}
