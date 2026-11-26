import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ymusic.sdk

Item {
    id: root

    property string text: ""
    property bool checked: false
    signal toggledTo(bool value)

    width: parent ? parent.width : 0
    implicitHeight: Math.max(36, row.implicitHeight + 8)

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: 12

        StyledText {
            Layout.fillWidth: true
            text: root.text
            wrapMode: Text.WordWrap
        }

        Switch {
            id: sw
            checked: root.checked
            onToggled: root.toggledTo(checked)
        }
    }
}
