import QtQuick
import ymusic.ui

Item {
    id: root

    property bool active: false
    property color color: Appearance.colors.primary
    property real barWidth: 3
    property real maxBarHeight: 16
    property real minBarHeight: 3
    property real spacing: 2

    implicitWidth: 4 * barWidth + 3 * spacing
    implicitHeight: maxBarHeight

    Row {
        anchors.centerIn: parent
        width: root.implicitWidth
        height: root.maxBarHeight
        spacing: root.spacing

        // Bar 1
        Rectangle {
            id: bar1
            width: root.barWidth
            height: root.minBarHeight
            radius: root.barWidth / 2
            color: root.color
            anchors.bottom: parent.bottom

            SequentialAnimation on height {
                running: root.active && root.visible && !Appearance.reduceMotion
                loops: Animation.Infinite
                NumberAnimation { to: root.maxBarHeight * 0.9; duration: 320; easing.type: Easing.InOutQuad }
                NumberAnimation { to: root.minBarHeight; duration: 280; easing.type: Easing.InOutQuad }
            }
        }

        // Bar 2
        Rectangle {
            id: bar2
            width: root.barWidth
            height: root.minBarHeight
            radius: root.barWidth / 2
            color: root.color
            anchors.bottom: parent.bottom

            SequentialAnimation on height {
                running: root.active && root.visible && !Appearance.reduceMotion
                loops: Animation.Infinite
                NumberAnimation { to: root.maxBarHeight * 0.5; duration: 210; easing.type: Easing.InOutQuad }
                NumberAnimation { to: root.maxBarHeight; duration: 310; easing.type: Easing.InOutQuad }
                NumberAnimation { to: root.minBarHeight; duration: 250; easing.type: Easing.InOutQuad }
            }
        }

        // Bar 3
        Rectangle {
            id: bar3
            width: root.barWidth
            height: root.minBarHeight
            radius: root.barWidth / 2
            color: root.color
            anchors.bottom: parent.bottom

            SequentialAnimation on height {
                running: root.active && root.visible && !Appearance.reduceMotion
                loops: Animation.Infinite
                NumberAnimation { to: root.maxBarHeight; duration: 380; easing.type: Easing.InOutQuad }
                NumberAnimation { to: root.minBarHeight; duration: 340; easing.type: Easing.InOutQuad }
            }
        }

        // Bar 4
        Rectangle {
            id: bar4
            width: root.barWidth
            height: root.minBarHeight
            radius: root.barWidth / 2
            color: root.color
            anchors.bottom: parent.bottom

            SequentialAnimation on height {
                running: root.active && root.visible && !Appearance.reduceMotion
                loops: Animation.Infinite
                NumberAnimation { to: root.maxBarHeight * 0.7; duration: 260; easing.type: Easing.InOutQuad }
                NumberAnimation { to: root.minBarHeight; duration: 290; easing.type: Easing.InOutQuad }
            }
        }
    }
}
