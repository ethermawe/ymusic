import QtQuick
import ymusic.ui

NumberAnimation {
    duration: Appearance.motion(400)
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Appearance.curves.expressiveDefaultSpatial
}
