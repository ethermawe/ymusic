import QtQuick
import ymusic.sdk

Item {
    id: root

    property var energies: []
    property int barCount: 5
    property bool active: true
    property color barColor: Theme.colors.primary
    property real barWidth: 3
    property real barSpacing: 3
    property real maxHeight: 16
    property real minHeight: 4

    implicitWidth: Math.max(0, barCount * barWidth + Math.max(0, barCount - 1) * barSpacing)
    implicitHeight: maxHeight

    Row {
        anchors.centerIn: parent
        spacing: root.barSpacing

        Repeater {
            model: Math.max(0, root.barCount)
            delegate: Rectangle {
                required property int index

                readonly property real _energy: (root.energies && root.energies.length > 0)
                    ? Math.max(0, Math.min(1, Number(root.energies[index % root.energies.length] || 0)))
                    : 0

                width: root.barWidth
                radius: root.barWidth / 2
                anchors.verticalCenter: parent.verticalCenter
                color: root.barColor
                opacity: root.active ? 0.95 : 0.4
                height: root.active
                    ? Math.max(root.minHeight, Math.min(root.maxHeight, root.minHeight + _energy * (root.maxHeight - root.minHeight)))
                    : Math.min(root.maxHeight, root.minHeight + (index === Math.floor(root.barCount / 2) ? 3 : 0))

                Behavior on height {
                    enabled: !Theme.performanceMode
                    NumberAnimation { duration: 75 }
                }
            }
        }
    }
}
