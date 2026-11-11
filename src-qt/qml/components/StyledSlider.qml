import QtQuick
import ymusic.ui

Item {
    id: root

    property real value: 0.0 // 0.0 to 1.0
    property real trackHeight: 4
    property real activeTrackHeight: 6
    property color trackColor: Qt.rgba(1, 1, 1, 0.15)
    property color fillColor: Appearance.colors.primary
    property color hoverFillColor: Appearance.colors.primaryHover
    property color thumbColor: Appearance.colors.onPrimary
    property bool interactive: true
    property bool showThumb: true

    signal userSeek(real fraction)

    implicitHeight: 20
    implicitWidth: 200

    readonly property bool isHovered: mouseArea.containsMouse
    readonly property bool isDragging: mouseArea.pressed

    property real visualProgress: isDragging ? dragProgress : value
    property real dragProgress: 0.0

    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: (root.isHovered || root.isDragging) ? root.activeTrackHeight : root.trackHeight
        radius: height / 2
        color: root.trackColor

        Behavior on height {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Rectangle {
            id: fill
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.max(0, Math.min(parent.width, parent.width * root.visualProgress))
            radius: parent.radius
            color: (root.isHovered || root.isDragging) ? root.hoverFillColor : root.fillColor

            Behavior on color {
                ColorAnimation { duration: 140 }
            }
        }
    }

    Rectangle {
        id: thumb
        visible: root.showThumb
        width: (root.isHovered || root.isDragging) ? 12 : 0
        height: width
        radius: width / 2
        color: root.thumbColor
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(parent.width - width, parent.width * root.visualProgress - width / 2))

        scale: (root.isHovered || root.isDragging) ? 1.0 : 0.0
        Behavior on scale {
            NumberAnimation {
                duration: 160
                easing.type: Easing.OutBack
                easing.overshoot: 1.8
            }
        }
        Behavior on width {
            NumberAnimation { duration: 140 }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: root.interactive
        enabled: root.interactive
        cursorShape: Qt.PointingHandCursor

        onPressed: (mouse) => {
            root.dragProgress = Math.max(0.0, Math.min(1.0, mouse.x / width))
        }

        onPositionChanged: (mouse) => {
            if (pressed) {
                root.dragProgress = Math.max(0.0, Math.min(1.0, mouse.x / width))
            }
        }

        onReleased: (mouse) => {
            var target = Math.max(0.0, Math.min(1.0, mouse.x / width))
            root.userSeek(target)
        }
    }
}
