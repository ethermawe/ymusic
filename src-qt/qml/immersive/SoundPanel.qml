pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import ymusic.ui

Item {
    id: root

    property MaterialScheme scheme: PlayerStyle.darkScheme
    readonly property color accent: scheme.primary
    readonly property color secondaryText: Qt.rgba(1, 1, 1, 0.65)
    readonly property bool tempoModified: Math.abs(backend.tempo - 1) > 0.01

    implicitHeight: column.implicitHeight

    component Card: Rectangle {
        default property alias content: cardColumn.data
        width: column.width
        implicitHeight: cardColumn.implicitHeight + 30
        radius: 20
        color: Qt.rgba(1, 1, 1, 0.07)

        Column {
            id: cardColumn
            x: 16
            y: 15
            width: parent.width - 32
            spacing: 14
        }
    }

    component ToggleRow: Item {
        id: rowItem
        property string title
        property bool value
        signal toggledTo(bool next)

        width: parent ? parent.width : 0
        height: 36

        StyledText {
            anchors.left: parent.left
            anchors.right: sw.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: rowItem.title
            color: "white"
            elide: Text.ElideRight
        }
        StyledSwitch {
            id: sw
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            scheme: root.scheme
            checked: rowItem.value
            onToggled: rowItem.toggledTo(checked)
        }
    }

    Column {
        id: column
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width, 420)
        spacing: 14

        Card {
            Item {
                width: parent.width
                height: 24
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Живой спектр"
                    font.weight: Font.DemiBold
                    color: "white"
                }
                StyledText {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: appSettings.visualizersEnabled ? "Активен" : "Выкл"
                    font.pixelSize: Appearance.fontSize.smaller
                    color: root.secondaryText
                }
            }

            SpectrumView {
                width: parent.width
                height: 96
                kind: SpectrumView.Equalizer
                wave: appSettings.visualizerShape === "wave"
                continuous: true
                sensitivity: appSettings.visualizerSensitivity
                active: backend.playing && appSettings.visualizersEnabled
            }
        }

        Card {
            Item {
                width: parent.width
                height: 28
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Скорость воспроизведения"
                    font.weight: Font.DemiBold
                    color: "white"
                }
                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: speedVal.implicitWidth + 16
                    height: 24
                    radius: 12
                    color: Qt.rgba(1, 1, 1, root.tempoModified ? 0.18 : 0.08)

                    StyledText {
                        id: speedVal
                        anchors.centerIn: parent
                        text: backend.tempo.toFixed(2) + "×"
                        tabularNumbers: true
                        font.pixelSize: Appearance.fontSize.smaller
                        font.weight: Font.DemiBold
                        color: "white"
                    }

                    TapHandler {
                        enabled: root.tempoModified
                        onTapped: {
                            backend.setTempo(1.0);
                            appSettings.playbackSpeed = 1.0;
                        }
                    }
                }
            }

            StyledSlider {
                width: parent.width
                scheme: root.scheme
                from: 0.5
                to: 2.0
                stepSize: 0.05
                snapMode: T.Slider.SnapAlways
                value: backend.tempo
                trackThickness: 10
                activeColor: root.accent
                inactiveColor: Qt.rgba(1, 1, 1, 0.16)
                onMoved: {
                    const v = Number(value.toFixed(2));
                    backend.setTempo(v);
                    appSettings.playbackSpeed = v;
                }
            }
        }

        Card {
            StyledText {
                text: "Визуализация экрана"
                font.weight: Font.DemiBold
                color: "white"
            }

            ToggleRow {
                title: "Визуализатор"
                value: appSettings.immersiveVisualizer
                onToggledTo: (next) => appSettings.immersiveVisualizer = next
            }
            ToggleRow {
                title: "Кольцевой режим"
                value: appSettings.circularVisualizer
                onToggledTo: (next) => appSettings.circularVisualizer = next
            }
            ToggleRow {
                title: "Волна вместо столбцов"
                value: appSettings.visualizerShape === "wave"
                onToggledTo: (next) => appSettings.visualizerShape = next ? "wave" : "bars"
            }
            ToggleRow {
                title: "Живой реактивный фон"
                value: appSettings.livingBackdrop
                onToggledTo: (next) => appSettings.livingBackdrop = next
            }
        }
    }
}
