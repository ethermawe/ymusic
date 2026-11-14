pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

Item {
    id: root

    property MaterialScheme scheme: PlayerStyle.darkScheme
    readonly property int settleMs: 420
    readonly property int stepMs: 30
    readonly property int depth: 12

    EmptyState {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 80
        Reveal.shown: !backend.hasTrack && backend.queue.count === 0
        scheme: root.scheme
        symbol: "queue_music"
        title: "Очередь пуста"
        description: "Добавьте треки или запустите Мою волну"
    }

    ListView {
        id: list
        anchors.fill: parent
        Reveal.shown: backend.hasTrack || backend.queue.count > 0
        model: backend.queue
        spacing: 10
        topMargin: 30
        bottomMargin: 30
        leftMargin: 8
        rightMargin: 8
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        FastWheel { target: list }

        layer.enabled: true
        layer.effect: ShaderEffect {
            property variant source
            property real edge: 0.08
            fragmentShader: "qrc:/shaders/edge_fade.frag.qsb"
        }

        delegate: ImmersiveQueueRow {
            required property int index
            required property var model
            width: list.width - list.leftMargin - list.rightMargin
            trackTitle: model.title
            trackArtists: model.artists
            artworkUrl: model.hasCover ? model.coverUrl : ""
            available: model.available
            current: model.isCurrent
            scheme: root.scheme
            onClicked: backend.trackAction(model.id, 3)
        }

        displaced: Transition {
            enabled: !Appearance.performanceMode
            SequentialAnimation {
                PauseAnimation { duration: Math.min(Math.max(ViewTransition.index, 0), root.depth) * root.stepMs }
                NumberAnimation {
                    property: "y"
                    duration: root.settleMs
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.curves.expressiveDefaultSpatial
                }
            }
        }
    }
}
