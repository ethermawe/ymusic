pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

Item {
    id: root

    property MaterialScheme scheme: Appearance.colors
    property color activeColor: scheme.primary
    property color trackColor: scheme.secondaryContainer
    property real positionMs: backend.positionSecs * 1000
    property real durationMs: backend.durationSecs * 1000
    property bool playing: backend.playing
    property bool expanded: hover.hovered || scrub.editing
    property real restThickness: 4
    property real expandedThickness: 6
    property real positionAnchorMs: positionMs
    property real clockAnchor: progressClock.value
    readonly property real runningPositionMs: root.playing && !Appearance.reduceMotion
                                              ? Math.min(root.durationMs, root.positionAnchorMs + (progressClock.value - root.clockAnchor) * 1000)
                                              : root.positionMs
    readonly property real displayPositionMs: scrub.editing && root.scrubPosition >= 0 ? root.scrubPosition : root.runningPositionMs
    readonly property real fraction: durationMs > 0 ? Math.min(1, Math.max(0, displayPositionMs / durationMs)) : 0
    property real scrubPosition: -1
    readonly property bool scrubbing: scrub.editing
    property bool followsCrossfade: false
    property real handoverFrom: 0
    property real handover: 0
    readonly property real shownFraction: fraction + (handoverFrom - fraction) * handover

    implicitHeight: 24
    enabled: backend.hasTrack && durationMs > 0

    onPositionMsChanged: {
        positionAnchorMs = positionMs
        clockAnchor = progressClock.value
    }
    onPlayingChanged: {
        positionAnchorMs = positionMs
        clockAnchor = progressClock.value
    }

    AmbientClock {
        id: progressClock
        speed: root.playing && root.visible && root.durationMs > 0 && !Appearance.reduceMotion ? 1 : 0
    }

    ScrubSession {
        id: scrub
    }

    Connections {
        target: backend
        function onTrackInstanceIdChanged() {
            scrub.cancel()
            root.scrubPosition = -1
            handoverAnimation.stop()
            root.handover = 0
        }
    }

    NumberAnimation {
        id: handoverAnimation
        target: root
        property: "handover"
        from: 1
        to: 0
        easing.type: Easing.InOutCubic
    }

    ShaderEffect {
        id: line

        anchors.fill: parent
        property size itemSize: Qt.size(width, height)
        property real progress: root.shownFraction
        property real amplitude: root.playing && !Appearance.reduceMotion && !appSettings.noShapes
                                 ? (root.expanded ? 2.4 : 1.6) : 0
        property real wavelength: 34
        property real phase: root.visible ? -(UiState.spin * 4.36) % (2 * Math.PI) : 0
        property real thickness: root.expanded ? root.expandedThickness : root.restThickness
        property real handleWidth: root.expanded ? 4 : 0
        property real handleHeight: 18
        property real gap: 4
        property color activeColor: root.activeColor
        property color trackColor: root.trackColor
        property color handleColor: root.activeColor
        fragmentShader: "qrc:/shaders/wavy_progress.frag.qsb"
        opacity: backend.hasTrack ? 1 : 0.45

        Behavior on amplitude {
            NumberAnimation { duration: Appearance.motion(400); easing.type: Easing.OutCubic }
        }
        Behavior on thickness {
            ElementMoveFast {}
        }
        Behavior on handleWidth {
            ElementMoveFast {}
        }
    }

    HoverHandler {
        id: hover
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        preventStealing: true

        function positionAt(x: real): real {
            return Math.max(0, Math.min(1, x / width)) * root.durationMs
        }

        onPressed: (mouse) => {
            scrub.begin(backend.trackInstanceId)
            root.scrubPosition = positionAt(mouse.x)
        }
        onPositionChanged: (mouse) => {
            if (scrub.acceptsChanges(backend.trackInstanceId)) {
                root.scrubPosition = positionAt(mouse.x)
            }
        }
        onReleased: {
            const target = scrub.finish(backend.trackInstanceId, root.scrubPosition)
            if (target >= 0 && root.durationMs > 0) {
                backend.seek(target / root.durationMs)
            }
            root.scrubPosition = -1
        }
        onCanceled: {
            scrub.finish(0, -1)
            root.scrubPosition = -1
        }
    }
}
