import QtQuick
import ymusic.ui

Item {
    id: root

    property color color: Appearance.colors.primary

    width: 0
    height: 0
    z: 100
    enabled: false

    readonly property var particles: [
        { dx: -24, dy: -32, rot: -26, size: 11, delay: 0 },
        { dx: -12, dy: -46, rot: -14, size: 13, delay: 35 },
        { dx:   0, dy: -54, rot:   4, size: 14, delay: 15 },
        { dx:  13, dy: -45, rot:  16, size: 12, delay: 45 },
        { dx:  25, dy: -30, rot:  28, size: 10, delay: 10 },
        { dx: -18, dy: -20, rot: -20, size:  9, delay: 60 },
        { dx:  19, dy: -22, rot:  22, size:  9, delay: 55 }
    ]

    function trigger() {
        if (Appearance.reduceMotion) return;
        for (let i = 0; i < repeater.count; ++i) {
            const item = repeater.itemAt(i);
            if (item) item.startBurst();
        }
    }

    Repeater {
        id: repeater
        model: root.particles

        delegate: Item {
            id: particle
            required property var modelData

            width: modelData.size
            height: modelData.size
            x: -width / 2
            y: -height / 2
            opacity: 0
            scale: 0.25
            visible: opacity > 0 || burstAnim.running

            function startBurst() {
                burstAnim.stop();
                x = -width / 2;
                y = -height / 2;
                rotation = 0;
                scale = 0.25;
                opacity = 0;
                burstAnim.start();
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: "favorite"
                iconSize: particle.modelData.size
                color: root.color
            }

            SequentialAnimation {
                id: burstAnim

                PauseAnimation {
                    duration: particle.modelData.delay
                }

                ParallelAnimation {
                    NumberAnimation {
                        target: particle
                        property: "x"
                        to: -particle.width / 2 + particle.modelData.dx
                        duration: Appearance.motion(680)
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: particle
                        property: "y"
                        to: -particle.height / 2 + particle.modelData.dy
                        duration: Appearance.motion(680)
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: particle
                        property: "rotation"
                        to: particle.modelData.rot
                        duration: Appearance.motion(680)
                        easing.type: Easing.OutQuad
                    }
                    SequentialAnimation {
                        NumberAnimation {
                            target: particle
                            property: "scale"
                            to: 1.1
                            duration: Appearance.motion(200)
                            easing.type: Easing.OutBack
                        }
                        NumberAnimation {
                            target: particle
                            property: "scale"
                            to: 0.5
                            duration: Appearance.motion(480)
                            easing.type: Easing.InQuad
                        }
                    }
                    SequentialAnimation {
                        NumberAnimation {
                            target: particle
                            property: "opacity"
                            to: 0.95
                            duration: Appearance.motion(110)
                            easing.type: Easing.OutQuad
                        }
                        PauseAnimation {
                            duration: Appearance.motion(210)
                        }
                        NumberAnimation {
                            target: particle
                            property: "opacity"
                            to: 0.0
                            duration: Appearance.motion(360)
                            easing.type: Easing.InQuad
                        }
                    }
                }
            }
        }
    }
}
