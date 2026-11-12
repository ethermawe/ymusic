import QtQuick
import QtQuick.Layouts
import ymusic.ui

ColumnLayout {
    id: root

    property string symbol: "music_note"
    property string title: ""
    property string description: ""
    property color accent: Appearance.colors.primary

    spacing: 10
    implicitWidth: 320
    implicitHeight: content.implicitHeight

    ColumnLayout {
        id: content
        Layout.alignment: Qt.AlignHCenter
        Layout.maximumWidth: 420
        spacing: 10

        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 72
            Layout.preferredHeight: 72

            MaterialShape {
                anchors.fill: parent
                shape: "cookie9"
                color: Appearance.colors.primaryContainer
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.symbol
                iconSize: 32
                color: root.accent
            }
        }

        TitleText {
            Layout.fillWidth: true
            text: root.title
            level: "title"
            color: Appearance.colors.onSurface
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.description.length > 0
            text: root.description
            color: Appearance.colors.onSurfaceVariant
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }
    }
}
