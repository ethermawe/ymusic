import QtQuick
import QtQuick.Layouts
import ymusic.ui

Item {
    id: root

    property string title: ""
    property string symbol: "auto_awesome"
    property bool showsAction: false
    property string actionText: "Смотреть все"
    signal actionClicked()

    implicitHeight: 40
    implicitWidth: 400

    RowLayout {
        anchors.fill: parent
        spacing: 12

        RowLayout {
            Layout.preferredWidth: implicitWidth
            Layout.maximumWidth: implicitWidth
            spacing: 12

        // Badge with MaterialShape flower
        Item {
            Layout.minimumWidth: 32
            Layout.preferredWidth: 32
            Layout.maximumWidth: 32
            Layout.preferredHeight: 32
            Layout.alignment: Qt.AlignVCenter

            MaterialShape {
                anchors.fill: parent
                shape: "cookie9"
                color: Appearance.colors.primaryContainer
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.symbol
                iconSize: 18
                color: Appearance.colors.primary
            }
        }

        // Section Title
        TitleText {
            id: titleItem
            text: root.title
            level: "title"
            color: Appearance.colors.onSurface
            Layout.alignment: Qt.AlignVCenter
        }
        }

        // Expanding Wavy Line
        WavyLine {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredHeight: 10
            wavelength: 18
            amplitude: 2.2
            color: Qt.rgba(Appearance.colors.outlineVariant.r,
                           Appearance.colors.outlineVariant.g,
                           Appearance.colors.outlineVariant.b, 0.4)
            // Stay in the layout even when narrow; visibility depending on
            // allocated width causes a layout/visibility feedback loop.
            opacity: width > 24 ? 1 : 0
        }

        // Action Pill Button
        Rectangle {
            id: actionPill
            visible: root.showsAction
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredHeight: 32
            Layout.preferredWidth: actionRow.implicitWidth + 24
            Layout.maximumWidth: actionRow.implicitWidth + 24
            radius: Appearance.rounding.full
            color: actionMouse.containsMouse ? Appearance.colors.surfaceContainerHighest : Appearance.colors.surfaceContainerHigh
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            scale: actionMouse.pressed ? 0.94 : (actionMouse.containsMouse ? 1.04 : 1.0)
            Behavior on scale { Bounce {} }
            Behavior on color { ElementMoveFastColor {} }

            RowLayout {
                id: actionRow
                anchors.centerIn: parent
                spacing: 6

                StyledText {
                    text: root.actionText
                    color: Appearance.colors.onSurface
                    font.pixelSize: Appearance.fontSize.smaller
                    font.weight: Font.Medium
                }

                MaterialSymbol {
                    text: "arrow_forward"
                    iconSize: 15
                    color: Appearance.colors.onSurfaceVariant
                }
            }

            MouseArea {
                id: actionMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.actionClicked()
            }
        }
    }
}
