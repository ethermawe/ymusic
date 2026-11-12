import QtQuick
import ymusic.ui

Item {
    id: root

    property real value: 0.0 // 0.0 to 1.0
    property real trackHeight: 4
    property real activeTrackHeight: 6
    property color trackColor: Qt.rgba(1, 1, 1, 0.15)
    property color fillColor: Appearance.colors.primary
    property color hoverFillColor: Appearance.colors.primaryHover
    property color thumbColor: Appearance.colors.onPrimary
    property bool interactive: true
    property bool showThumb: true
    property bool animatedWave: false
    property bool playing: false

    signal userSeek(real fraction)

    implicitHeight: 20
    implicitWidth: 200

    readonly property bool isHovered: mouseArea.containsMouse
    readonly property bool isDragging: mouseArea.pressed

    // Keep the committed pointer position until the async backend acknowledges
    // it. Otherwise releasing the pointer briefly restores the old value.
    readonly property real visualProgress: isDragging || awaitingCommit ? dragProgress : value
    property real dragProgress: 0.0
    property bool awaitingCommit: false
    onValueChanged: {
        if (awaitingCommit && Math.abs(value - dragProgress) < 0.002) {
            awaitingCommit = false;
            commitTimeout.stop();
        }
    }
    Timer {
        id: commitTimeout
        interval: 1000
        onTriggered: root.awaitingCommit = false
    }

    ShaderEffect {
        id: progressShader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        // Keep the rendering area fixed and leave room for the full wave,
        // antialiasing fringe and handle, including during hover transitions.
        height: Math.max(root.height, root.activeTrackHeight + 8, 22)
        property size itemSize: Qt.size(width, height)
        property real progress: Math.max(0, Math.min(1, root.visualProgress))
        property real amplitude: root.animatedWave && root.playing && !Appearance.reduceMotion
                                 ? (root.isHovered || root.isDragging ? 2.4 : 1.6) : 0
        property real wavelength: 34
        property real phase: 0
        property real thickness: root.isHovered || root.isDragging ? root.activeTrackHeight : root.trackHeight
        property real handleWidth: root.showThumb && (root.animatedWave || root.isHovered || root.isDragging) ? 4 : 0
        property real handleHeight: 18
        property real gap: 4
        property color activeColor: (root.isHovered || root.isDragging) ? root.hoverFillColor : root.fillColor
        property color trackColor: root.trackColor
        property color handleColor: root.animatedWave ? root.fillColor : root.thumbColor
        fragmentShader: "qrc:/shaders/wavy_progress.frag.qsb"

        Behavior on thickness { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on amplitude { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on handleWidth { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        NumberAnimation on phase {
            from: 0
            to: 6.283185
            duration: 2200
            loops: Animation.Infinite
            running: root.animatedWave && root.playing && root.visible && !Appearance.reduceMotion
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: root.interactive
        enabled: root.interactive
        preventStealing: true
        cursorShape: Qt.PointingHandCursor

        onPressed: (mouse) => {
            commitTimeout.stop();
            root.awaitingCommit = true;
            root.dragProgress = Math.max(0.0, Math.min(1.0, mouse.x / width))
        }

        onPositionChanged: (mouse) => {
            if (pressed) {
                root.dragProgress = Math.max(0.0, Math.min(1.0, mouse.x / width))
            }
        }

        onReleased: (mouse) => {
            var target = Math.max(0.0, Math.min(1.0, mouse.x / width))
            root.dragProgress = target;
            commitTimeout.restart();
            root.userSeek(target)
        }
        onCanceled: {
            commitTimeout.stop();
            root.awaitingCommit = false;
        }
    }
}
