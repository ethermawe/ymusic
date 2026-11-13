import QtQuick
import QtQuick.Templates as T
import ymusic.ui

T.AbstractButton {
    id: root

    property string symbol: ""
    property real iconSize: 20
    property real size: 36
    property color iconColor: Appearance.colors.onSurface
    property color activeIconColor: Appearance.colors.primary
    property bool toggled: false
    property bool heartBurst: false
    property string tooltip: ""

    implicitWidth: size
    implicitHeight: size
    hoverEnabled: true

    scale: down ? 0.90 : (hovered ? 1.06 : 1.0)
    Behavior on scale {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutBack
            easing.overshoot: 1.8
        }
    }

    background: Rectangle {
        anchors.fill: parent
        radius: root.size / 2
        color: root.toggled
               ? Qt.rgba(Appearance.colors.primary.r, Appearance.colors.primary.g, Appearance.colors.primary.b, 0.18)
               : (root.hovered ? Qt.rgba(1, 1, 1, 0.09) : "transparent")

        Behavior on color {
            ColorAnimation { duration: 140 }
        }
    }

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        text: root.symbol
        iconSize: root.iconSize
        color: root.toggled ? root.activeIconColor : root.iconColor

        Behavior on color {
            ColorAnimation { duration: 140 }
        }
    }

    LikeBurst {
        id: likeBurst
        anchors.centerIn: parent
        color: root.activeIconColor
    }

    onClicked: {
        if (root.heartBurst && !root.toggled) {
            likeBurst.trigger();
        }
    }
}
