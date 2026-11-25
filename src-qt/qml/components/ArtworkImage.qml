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

    property url source
    property real radius: Appearance.sizes.artworkRadius
    property bool circular: false
    property real borderWidth: 0
    property color borderColor: Qt.rgba(1, 1, 1, 0.12)
    property bool crossfade: false
    property bool fades: true
    property int revealDuration: 0
    property double sourceChangedAt: 0
    property string placeholderSymbol: "music_note"
    property string fallbackKey: source.toString().length > 0 ? source.toString() : placeholderSymbol
    property bool cache: true
    property bool showArtwork: true
    property bool loading: false
    property color blankTopColor: Appearance.colors.surfaceContainerHigh
    property color blankBottomColor: Appearance.colors.surfaceContainer
    readonly property bool ready: showArtwork && front.status === Image.Ready && appSettings.coversEnabled && source.toString().length > 0
    readonly property bool showArtPlaceholder: showArtwork && !loading && (!appSettings.coversEnabled || source.toString().length === 0 || front.status === Image.Error)
    property int maximumPixelSize: 2048
    readonly property int pixelSize: {
        const ratio = Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
        const pixels = Math.min(maximumPixelSize, Math.max(16, Math.ceil(Math.max(width, height) * ratio / 32) * 32))
        return Math.ceil(pixels / ratio)
    }
    readonly property bool sameCover: back.status === Image.Ready && back.source.toString() === front.source.toString()

    property real waviness: 0
    property real wavelength: 22
    readonly property real wavePhase: waveDrift.value
    property real dim: 0
    property bool squiggly: true
    property real squiggleAmplitudeBoost: 1
    readonly property bool showsSquiggle: circular && squiggly && !appSettings.noShapes && Math.min(width, height) >= 40
    property color squiggleColor: Appearance.colors.primary
    property bool squiggleFollowsPlayback: false
    property bool squiggleTurning: hover.hovered
    property real squiggleSpin: 0
    property real squiggleSpeed: squiggleTurning && !Appearance.reduceMotion && !UiState.pointerResting ? 1 : 0
    Behavior on squiggleSpeed {
        NumberAnimation { duration: 700; easing.type: Easing.InOutSine }
    }

    readonly property real squiggleThickness: Math.max(2, Math.min(width, height) * 0.02)
    readonly property real baseSquiggleAmplitude: Math.max(1.4, squiggleThickness * 0.7)
    readonly property real squiggleAmplitude: baseSquiggleAmplitude * squiggleAmplitudeBoost
    readonly property real squiggleWaves: {
        const middle = Math.min(width, height) / 2 - baseSquiggleAmplitude - squiggleThickness / 2 - 0.75
        return Math.max(8, Math.round(2 * Math.PI * middle / (8 * squiggleThickness)))
    }
    readonly property real squigglePhase: squiggleFollowsPlayback && visible ? (squiggleWaves * 0.1 * UiState.spin) % (2 * Math.PI)
                                                                  : squiggleSpin
    readonly property real squiggleMiddle: Math.min(width, height) / 2 - squiggleAmplitude - squiggleThickness / 2 - 0.75
    readonly property real effectiveRadius: circular ? Math.min(face.width, face.height) / 2 : radius

    onSourceChanged: {
        sourceChangedAt = Date.now()
        if (source.toString().length === 0) {
            back.source = ""
        }
    }

    function artworkUrl(url: url): string {
        const text = url.toString()
        if (text.length === 0) {
            return ""
        }
        return text.startsWith("image://") ? text : "image://art/" + encodeURIComponent(text)
    }

    component Layer: ShaderEffect {
        required property Item image
        property real imageAspect: 1
        readonly property real itemAspect: height > 0 ? width / height : 1
        property variant source: image
        property size itemSize: Qt.size(width, height)
        property real radius
        property real borderWidth
        property color borderColor
        property size uvScale: imageAspect > itemAspect ? Qt.size(itemAspect / imageAspect, 1) : Qt.size(1, imageAspect / itemAspect)
        property point uvOffset: Qt.point((1 - uvScale.width) / 2, (1 - uvScale.height) / 2)
        property real waviness: appSettings.noShapes ? 0 : root.waviness
        property real wavelength: root.wavelength
        property real phase: root.wavePhase
        property real ringWaves: root.showsSquiggle ? root.squiggleWaves : 0
        property real ringAmplitude: root.squiggleAmplitude
        property real ringThickness: root.squiggleThickness
        property real ringPhase: root.squigglePhase
        property color ringColor: root.squiggleColor
        property real reveal: 1
        property real dim: root.dim

        anchors.fill: parent
        fragmentShader: "qrc:/shaders/rounded_image.frag.qsb"
    }

    Drift {
        id: waveDrift
        active: Math.abs(root.waviness) > 0.01 && root.visible && !appSettings.noShapes
        speed: 2 * Math.PI / 2.4
    }

    HoverHandler {
        id: hover
        enabled: root.showsSquiggle
    }

    FrameAnimation {
        running: root.showsSquiggle && !root.squiggleFollowsPlayback && root.squiggleSpeed > 0 && root.visible
        onTriggered: root.squiggleSpin = (root.squiggleSpin + frameTime * root.squiggleSpeed * root.squiggleWaves * 0.075)
                                         % (2 * Math.PI)
    }

    Item {
        id: face
        anchors.fill: parent

        // Calm neutral placeholder while a real cover loads; avoids flashing colorful fallback art.
        Rectangle {
            anchors.centerIn: parent
            width: root.showsSquiggle ? Math.max(0, (root.squiggleMiddle - root.squiggleAmplitude) * 2) : parent.width
            height: root.showsSquiggle ? width : parent.height
            radius: root.showsSquiggle ? width / 2 : root.effectiveRadius
            color: Appearance.colors.surfaceContainerHigh
            border.width: root.borderWidth
            border.color: root.borderColor
            visible: root.showArtwork && !root.showArtPlaceholder && !backLayer.visible && (!root.ready || frontLayer.opacity < 1)
        }

        Item {
            id: blankFill
            width: 128
            height: 128
            visible: false
            layer.enabled: !root.showArtwork
            layer.smooth: true

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: root.blankTopColor }
                    GradientStop { position: 1.0; color: root.blankBottomColor }
                }
            }
        }

        Layer {
            image: blankFill
            radius: root.effectiveRadius
            borderWidth: root.borderWidth
            borderColor: root.borderColor
            visible: !root.showArtwork
        }

        Image {
            id: placeholder
            anchors.fill: parent
            visible: false
            asynchronous: true
            source: root.showArtPlaceholder
                ? root.artworkUrl("ymusic-cover:/" + (Theme.dark ? "dark" : "light")
                                  + "?key=" + encodeURIComponent(root.fallbackKey))
                : ""
            sourceSize: Qt.size(root.pixelSize, root.pixelSize)
        }

        Layer {
            image: placeholder
            radius: root.effectiveRadius
            borderWidth: root.borderWidth
            borderColor: root.borderColor
            visible: root.showArtPlaceholder && !backLayer.visible && (!root.ready || frontLayer.opacity < 1)
        }

        Image {
            id: back
            visible: false
            asynchronous: true
            cache: root.cache
        }

        Image {
            id: front
            visible: false
            asynchronous: true
            cache: root.cache
            source: root.showArtwork && appSettings.coversEnabled ? root.artworkUrl(root.source) : ""
            sourceSize: Qt.size(root.pixelSize, root.pixelSize)
            onStatusChanged: {
                if (status === Image.Error) {
                    back.source = ""
                    return
                }
                if (status !== Image.Ready) {
                    return
                }

                sweep.stop()
                frontLayer.reveal = 1
                const elapsed = Date.now() - root.sourceChangedAt
                if (root.fades && !root.sameCover) {
                    const sweepLeft = root.revealDuration - elapsed
                    if (root.crossfade && back.status === Image.Ready && sweepLeft > 400 && !Appearance.reduceMotion) {
                        fadeIn.stop()
                        frontLayer.opacity = 1
                        frontLayer.reveal = 0
                        sweep.duration = sweepLeft
                        sweep.restart()
                    } else if (elapsed < 80) {
                        // Cached/instant covers appear cleanly without fading over a placeholder.
                        fadeIn.stop()
                        frontLayer.opacity = 1
                        root.keepShown()
                    } else {
                        frontLayer.opacity = 0
                        fadeIn.restart()
                    }
                } else {
                    fadeIn.stop()
                    frontLayer.opacity = 1
                    root.keepShown()
                }
            }
        }

        Layer {
            id: backLayer
            image: back
            imageAspect: back.implicitHeight > 0 ? back.implicitWidth / back.implicitHeight : 1
            radius: root.effectiveRadius
            borderWidth: root.borderWidth
            borderColor: root.borderColor
            visible: root.showArtwork && back.status === Image.Ready && (root.sameCover || root.crossfade)
                     && (!root.ready || frontLayer.opacity < 1 || frontLayer.reveal < 1)
        }

        Layer {
            id: frontLayer
            image: front
            imageAspect: front.implicitHeight > 0 ? front.implicitWidth / front.implicitHeight : 1
            radius: root.effectiveRadius
            borderWidth: root.borderWidth
            borderColor: root.borderColor
            visible: root.ready
        }
    }

    NumberAnimation {
        id: fadeIn
        target: frontLayer
        property: "opacity"
        from: 0
        to: 1
        duration: Appearance.duration(280)
        easing.type: Easing.OutCubic
        onFinished: root.keepShown()
    }

    NumberAnimation {
        id: sweep
        target: frontLayer
        property: "reveal"
        from: 0
        to: 1
        easing.type: Easing.InOutSine
        onFinished: root.keepShown()
    }

    function keepShown() {
        back.source = ""
        back.sourceSize = front.sourceSize
        back.source = front.source
    }
}
