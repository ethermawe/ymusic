pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import ymusic.ui

Item {
    id: root

    required property Window window
    property Item backdropSource
    property bool windowControlsOnRight: false
    property bool inspectorShown: false
    readonly property bool compact: width < 560
    readonly property real buttonSize: width < 400 ? 30 : (compact ? 36 : 42)
    readonly property real searchRightEdge: rightControls.x - 10
    readonly property real searchLeftEdge: back.x + (back.visible ? back.width + 10 : 0)
    readonly property real reservedSearchWidth: Math.max(120, Math.min(320, searchRightEdge - searchLeftEdge))

    function focusSearch() {
        search.focusField()
    }

    implicitHeight: Appearance.sizes.topBarHeight

    DragHandler {
        target: null
        grabPermissions: PointerHandler.CanTakeOverFromAnything
        onActiveChanged: if (active) root.window.startSystemMove()
    }
    TapHandler {
        acceptedButtons: Qt.LeftButton
        onDoubleTapped: root.window.visibility === Window.Maximized ? root.window.showNormal() : root.window.showMaximized()
    }

    Item {
        id: toolbarButtons
        anchors.fill: parent

        ToolbarButton {
            id: back
            effect: ToolbarButton.NudgeLeft
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            size: root.buttonSize
            iconSize: root.compact ? 20 : 24
            symbol: "arrow_back"
            shape: "arrow"
            shapeAngle: -90
            turnsOnHover: false
            visible: backend.canGoBack
            enabled: backend.canGoBack
            onClicked: backend.goBack()
            tooltip: qsTr("Назад")
        }

        Row {
            id: rightControls
            anchors.right: parent.right
            anchors.rightMargin: 12 + (root.windowControlsOnRight && !root.inspectorShown ? 96 : 0)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            ToolbarButton {
                id: overflow
                effect: ToolbarButton.Spin
                size: root.buttonSize
                iconSize: root.compact ? 20 : 24
                shape: "cookie9"
                anchors.verticalCenter: parent.verticalCenter
                symbol: "more_vert"
                onClicked: playbackMenu.popupAt(overflow, 0, overflow.height)
                tooltip: qsTr("Воспроизведение и настройки")
            }
        }
    }

    Rectangle {
        id: searchMask
        width: search.width
        height: search.height
        radius: height / 2
        layer.enabled: true
        visible: false
    }

    Item {
        id: searchBlur
        anchors.fill: search
        z: 8
        visible: search.editing && !!root.backdropSource

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Appearance.colors.layer1
        }

        ShaderEffectSource {
            id: searchBackdrop
            anchors.fill: parent
            sourceItem: root.backdropSource
            live: searchBlur.visible
            hideSource: false
            sourceRect: {
                const origin = root.mapToItem(root.backdropSource, search.x, search.y)
                return Qt.rect(origin.x, origin.y, search.width, search.height)
            }
            textureSize: Qt.size(Math.max(1, Math.ceil(search.width)), Math.max(1, Math.ceil(search.height)))
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: searchBackdrop
            blurEnabled: true
            blur: 0.8
            blurMax: 48
            maskEnabled: true
            maskSource: searchMask
        }
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Qt.alpha(Appearance.colors.surfaceContainerHighest, 0.18)
        }
    }

    SearchField {
        id: search
        x: root.searchRightEdge - width
        anchors.verticalCenter: parent.verticalCenter
        z: editing ? 9 : 0
        width: {
            if (!visible) return 0
            return editing ? Math.max(140, Math.min(340, root.searchRightEdge - root.searchLeftEdge)) : root.reservedSearchWidth
        }
        placeholder: qsTr("Поиск музыки…")
        onAccepted: {
            if (text.trim().length > 0) {
                backend.search(text.trim())
            }
        }

        Behavior on width {
            ElementMoveSmall {}
        }
    }

    MenuLoader {
        id: playbackMenu
        sourceComponent: PlaybackMenu {}
    }
}
