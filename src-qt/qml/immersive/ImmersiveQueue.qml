/*
 * Swiftify, a spotify player for desktop
 * Copyright (C) 2026  shred0s
 * Modified for ymusic (2026).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

Item {
    id: root

    property MaterialScheme scheme: PlayerStyle.darkScheme
    readonly property int settleMs: 420
    readonly property int stepMs: 30
    readonly property int depth: 12

    ModSlotHost {
        layoutMode: "row"
        spacing: 6
        z: 2
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 12
        anchors.topMargin: 6
        height: 32
        visible: implicitWidth > 0
        slotName: "immersive.queue.header"
        slotContext: ({
            scheme: root.scheme,
            count: backend.queue.count
        })
    }

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
            isAi: Boolean(model.isAi)
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
