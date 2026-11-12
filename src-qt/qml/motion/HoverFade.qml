import QtQuick
import ymusic.ui

NumberAnimation {
    duration: Appearance.duration(350)
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Appearance.curves.standard
}
