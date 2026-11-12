import QtQuick
import ymusic.ui

Row {
    id: root

    property string text: ""
    property real pixelSize: Appearance.fontSize.normal
    property int weight: Font.Normal
    property color color: Appearance.colors.onSurfaceVariant
    property string family: "monospace"

    Repeater {
        model: root.text.length

        delegate: Item {
            required property int index
            readonly property string character: root.text.charAt(index)
            property bool ready: false
            width: current.implicitWidth
            height: current.implicitHeight
            clip: true

            onCharacterChanged: {
                previous.text = current.text;
                current.text = character;
                if (ready && !Appearance.reduceMotion) roll.restart();
            }

            Text {
                id: previous
                opacity: 0
                font.family: root.family
                font.pixelSize: root.pixelSize
                font.weight: root.weight
                color: root.color
            }

            Text {
                id: current
                font.family: root.family
                font.pixelSize: root.pixelSize
                font.weight: root.weight
                color: root.color
                Component.onCompleted: {
                    text = character;
                    ready = true;
                }
            }

            ParallelAnimation {
                id: roll
                NumberAnimation { target: current; property: "y"; from: -current.height; to: 0; duration: 220; easing.type: Easing.OutCubic }
                NumberAnimation { target: current; property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
                NumberAnimation { target: previous; property: "y"; from: 0; to: current.height; duration: 220; easing.type: Easing.OutCubic }
                NumberAnimation { target: previous; property: "opacity"; from: 1; to: 0; duration: 220; easing.type: Easing.OutCubic }
            }
        }
    }
}
