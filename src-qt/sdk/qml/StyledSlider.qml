import QtQuick
import ymusic.sdk

Item {
    id: root

    property real value: 0.0
    property real from: 0.0
    property real to: 1.0
    property color accentColor: Theme.colors.primary
    property color trackColor: Theme.withAlpha(Theme.colors.onSurface, 0.16)

    readonly property alias pressed: dragArea.pressed

    signal moved(real newValue)
    signal releasedValue(real finalValue)

    implicitWidth: 160
    implicitHeight: 20
    opacity: enabled ? 1.0 : 0.45

    property real _dragValue: 0.0

    readonly property real _span: Math.max(0.000001, to - from)
    readonly property real _effectiveValue: dragArea.pressed ? _dragValue : value
    readonly property real _ratio: Math.max(0, Math.min(1, (_effectiveValue - from) / _span))

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: dragArea.containsMouse || dragArea.pressed ? 5 : 4
        radius: height / 2
        color: root.trackColor

        Behavior on height {
            enabled: !Theme.performanceMode
            NumberAnimation { duration: 100 }
        }

        Rectangle {
            width: Math.max(0, Math.min(parent.width, parent.width * root._ratio))
            height: parent.height
            radius: parent.radius
            color: root.accentColor
        }
    }

    Rectangle {
        id: thumb
        width: dragArea.pressed ? 15 : (dragArea.containsMouse ? 13 : 11)
        height: width
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(root.width - width, root.width * root._ratio - width / 2))
        color: Theme.colors.onSurface
        border.width: 2
        border.color: root.accentColor

        Behavior on width {
            enabled: !Theme.performanceMode
            NumberAnimation { duration: 100 }
        }
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

        function valueAt(mx) {
            const pos = Math.max(0, Math.min(1, mx / Math.max(1, root.width)));
            return root.from + pos * root._span;
        }

        onPressed: (mouse) => {
            root._dragValue = valueAt(mouse.x);
            root.moved(root._dragValue);
        }
        onPositionChanged: (mouse) => {
            if (pressed) {
                root._dragValue = valueAt(mouse.x);
                root.moved(root._dragValue);
            }
        }
        onReleased: (mouse) => {
            root._dragValue = valueAt(mouse.x);
            root.releasedValue(root._dragValue);
        }
    }
}
