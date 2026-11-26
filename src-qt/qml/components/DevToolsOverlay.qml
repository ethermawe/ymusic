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
            color: Qt.alpha(Appearance.colors.tertiary, 0.12)
            border.width: 1
            border.color: Appearance.colors.tertiary
            radius: Appearance.rounding.verySmall

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                width: slotTag.implicitWidth + 10
                height: 18
                radius: Appearance.rounding.verySmall
                color: Appearance.colors.tertiaryContainer

                StyledText {
                    id: slotTag
                    anchors.centerIn: parent
                    text: modelData.slotName || ""
                    font.family: Appearance.monoFontFamily
                    font.pixelSize: 10
                    color: Appearance.colors.onTertiaryContainer
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
        color: Qt.alpha(Appearance.colors.primary, 0.12)
        border.width: 1.5
        border.color: Appearance.colors.primary
        radius: 4
    }

    // Active hover highlight during Element Picker mode
    Rectangle {
        id: hoverBox
        visible: root.picking && root.hoveredInfo && (root.hoveredInfo.width || 0) > 0
        x: root.hoveredInfo.sceneX || 0
        y: root.hoveredInfo.sceneY || 0
        width: root.hoveredInfo.width || 0
        height: root.hoveredInfo.height || 0
        color: Qt.alpha(Appearance.colors.primary, 0.16)
        border.width: 1.5
        border.color: Appearance.colors.primary
        radius: 4

        Rectangle {
            x: 0
            y: hoverBox.y > 28 ? -26 : hoverBox.height + 6
            width: hoverLabel.implicitWidth + 14
            height: 22
            radius: Appearance.rounding.verySmall
            color: Appearance.colors.surfaceContainerHighest
            border.width: 1
            border.color: Appearance.colors.outlineVariant

            StyledText {
                id: hoverLabel
                anchors.centerIn: parent
                text: (root.hoveredInfo.type || "Item")
                    + (root.hoveredInfo.objectName ? (" #" + root.hoveredInfo.objectName) : "")
                    + " · " + Math.round(root.hoveredInfo.width || 0) + "×" + Math.round(root.hoveredInfo.height || 0)
                font.family: Appearance.monoFontFamily
                font.pixelSize: 11
                color: Appearance.colors.onSurface
            }
        }
    }

    // Picker hint pill at top center
    Rectangle {
        visible: root.picking
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 12
        width: pickHint.implicitWidth + 24
        height: 32
        radius: height / 2
        color: Appearance.colors.surfaceContainerHighest
        border.width: 1
        border.color: Appearance.colors.outlineVariant

        StyledText {
            id: pickHint
            anchors.centerIn: parent
            text: "Инспектор: кликните по элементу · ПКМ или Esc для отмены"
            font.pixelSize: Appearance.fontSize.smaller
            color: Appearance.colors.onSurface
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
