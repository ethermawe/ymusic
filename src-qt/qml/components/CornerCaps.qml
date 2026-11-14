pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

Item {
    id: root

    property real radius
    property color color

    component Corner: Item {
        id: corner

        required property real across
        required property real down

        width: root.radius
        height: root.radius
        clip: true

        Rectangle {
            x: corner.across * root.radius - 2 * root.radius
            y: corner.down * root.radius - 2 * root.radius
            width: 4 * root.radius
            height: 4 * root.radius
            radius: 2 * root.radius
            color: "transparent"
            border.width: root.radius
            border.color: root.color
        }
    }

    Corner { across: 1; down: 1 }
    Corner { x: root.width - width; across: 0; down: 1 }
    Corner { y: root.height - height; across: 1; down: 0 }
    Corner { x: root.width - width; y: root.height - height; across: 0; down: 0 }
}
