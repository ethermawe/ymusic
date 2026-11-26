pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

Item {
    id: root

    required property Item sceneRoot
    property bool picking: false
    property bool showModSlots: false
    property var highlightedInfo: ({})
    property var modSlotRects: []

    signal itemPicked(var item)
    signal pickingCancelled()

    property var hoveredInfo: ({})

    function refreshModSlots() {
        if (!showModSlots || !sceneRoot) {
            modSlotRects = [];
            return;
        }
        modSlotRects = devTools.findModSlots(sceneRoot);
    }

    onShowModSlotsChanged: refreshModSlots()
    onWidthChanged: if (showModSlots) refreshModSlots()
    onHeightChanged: if (showModSlots) refreshModSlots()
    onPickingChanged: if (!picking) hoveredInfo = ({})

    visible: picking || showModSlots || (highlightedInfo && highlightedInfo.width > 0)

    Timer {
        interval: 800
        repeat: true
        running: root.showModSlots && root.visible
        onTriggered: root.refreshModSlots()
    }

    // Highlighted ModSlotHost wireframes
    Repeater {
        model: root.showModSlots ? root.modSlotRects : []

        delegate: Rectangle {
            required property var modelData
            x: modelData.x || 0
            y: modelData.y || 0
            width: Math.max(24, modelData.width || 0)
            height: Math.max(18, modelData.height || 0)
            color: Qt.rgba(0.95, 0.65, 0.2, 0.08)
            border.width: 1
            border.color: "#e09f3e"
            radius: 4

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                width: slotTag.implicitWidth + 8
                height: 16
                radius: 3
                color: "#1a1b1f"
                border.width: 1
                border.color: "#e09f3e"

                Text {
                    id: slotTag
                    anchors.centerIn: parent
                    text: modelData.slotName || ""
                    font.family: Appearance.monoFontFamily
                    font.pixelSize: 10
                    color: "#f4c97a"
                }
            }
        }
    }

    // Selected item highlight (when not actively picking)
    Rectangle {
        visible: !root.picking && root.highlightedInfo && (root.highlightedInfo.width || 0) > 0
        x: root.highlightedInfo.sceneX || 0
        y: root.highlightedInfo.sceneY || 0
        width: root.highlightedInfo.width || 0
        height: root.highlightedInfo.height || 0
        color: Qt.alpha(Appearance.colors.primary, 0.1)
        border.width: 1
        border.color: Appearance.colors.primary
        radius: 2
    }

    // Active hover highlight during Element Picker mode
    Rectangle {
        id: hoverBox
        visible: root.picking && root.hoveredInfo && (root.hoveredInfo.width || 0) > 0
        x: root.hoveredInfo.sceneX || 0
        y: root.hoveredInfo.sceneY || 0
        width: root.hoveredInfo.width || 0
        height: root.hoveredInfo.height || 0
        color: Qt.alpha(Appearance.colors.primary, 0.14)
        border.width: 1
        border.color: Appearance.colors.primary
        radius: 2

        Rectangle {
            x: 0
            y: hoverBox.y > 24 ? -22 : hoverBox.height + 4
            width: hoverLabel.implicitWidth + 12
            height: 20
            radius: 4
            color: "#141518"
            border.width: 1
            border.color: Appearance.colors.primary

            Text {
                id: hoverLabel
                anchors.centerIn: parent
                text: (root.hoveredInfo.type || "Item")
                    + (root.hoveredInfo.objectName ? (" #" + root.hoveredInfo.objectName) : "")
                    + " · " + Math.round(root.hoveredInfo.width || 0) + "×" + Math.round(root.hoveredInfo.height || 0)
                font.family: Appearance.monoFontFamily
                font.pixelSize: 11
                color: "#eceef2"
            }
        }
    }

    // Picker banner at top center
    Rectangle {
        visible: root.picking
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 12
        width: pickHint.implicitWidth + 20
        height: 28
        radius: 6
        color: "#141518"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.14)

        Text {
            id: pickHint
            anchors.centerIn: parent
            text: "Инспектор: кликните по элементу · ПКМ или Esc — отмена"
            font.family: Appearance.fontFamily
            font.pixelSize: 12
            color: "#eceef2"
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.picking
        visible: root.picking
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.CrossCursor

        onPositionChanged: (mouse) => {
            const hit = devTools.pickItemAt(root.sceneRoot, mouse.x, mouse.y, root);
            root.hoveredInfo = hit ? devTools.inspectItem(hit, root.sceneRoot) : ({});
        }
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                root.picking = false;
                root.pickingCancelled();
                return;
            }
            const hit = devTools.pickItemAt(root.sceneRoot, mouse.x, mouse.y, root);
            root.picking = false;
            if (hit) {
                root.itemPicked(hit);
            }
        }
    }
}
