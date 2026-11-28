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
    readonly property color secondaryText: Qt.rgba(1, 1, 1, 0.6)
    readonly property list<string> fades: ["none", "finalSeconds", "entire"]
    readonly property list<string> explanations: [
        "Воспроизведение просто остановится, когда таймер закончится",
        "Громкость плавно снизится за последние 10 секунд",
        "Громкость будет плавно снижаться на протяжении всего таймера"
    ]
    readonly property int fadeIndex: Math.max(0, fades.indexOf(AppSettings.sleepTimerFade))

    property int hours: 0
    property int minutes: 30
    property int seconds: 0
    readonly property int duration: hours * 3600 + minutes * 60 + (AppSettings.debuggingEnabled ? seconds : 0)

    property int remaining: 0

    function refresh() {
        const deadline = Backend.sleepTimerDeadline;
        remaining = Backend.sleepTimerRunning && deadline
            ? Math.max(0, Math.ceil((deadline.getTime() - Date.now()) / 1000))
            : 0;
    }

    function positional(total: int): string {
        const h = Math.floor(total / 3600);
        const m = Math.floor((total % 3600) / 60);
        const s = total % 60;
        return h + ":" + String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0");
    }

    implicitHeight: column.implicitHeight + 44

    Timer {
        interval: 1000
        repeat: true
        running: Backend.sleepTimerRunning && root.visible
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
    Connections {
        target: Backend
        function onSleepTimerChanged() { root.refresh() }
    }

    component Stepper: Rectangle {
        id: stepper

        property int value
        property int maximum
        property string unit
        signal stepped(int value)

        implicitWidth: row.implicitWidth + 8
        implicitHeight: 44
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.08)

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 2

            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                scheme: root.scheme
                symbol: "remove"
                size: 36
                iconSize: 20
                iconColor: "white"
                colBackgroundHover: Qt.rgba(1, 1, 1, 0.1)
                enabled: stepper.value > 0
                autoRepeat: true
                onClicked: stepper.stepped(stepper.value - 1)
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: 64
                horizontalAlignment: Text.AlignHCenter
                text: stepper.value + " " + stepper.unit
                tabularNumbers: true
                font.weight: Font.Medium
                color: "white"
            }
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                scheme: root.scheme
                symbol: "add"
                size: 36
                iconSize: 20
                iconColor: "white"
                colBackgroundHover: Qt.rgba(1, 1, 1, 0.1)
                enabled: stepper.value < stepper.maximum
                autoRepeat: true
                onClicked: stepper.stepped(stepper.value + 1)
            }
        }

        WheelHandler {
            onWheel: (event) => {
                if (event.angleDelta.y === 0) {
                    event.accepted = false;
                    return;
                }
                const step = event.angleDelta.y > 0 ? 1 : -1;
                const next = Math.min(stepper.maximum, Math.max(0, stepper.value + step));
                if (next !== stepper.value) {
                    stepper.stepped(next);
                }
                event.accepted = true;
            }
        }
    }

    Column {
        id: column
        y: 44
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width, 380)
        spacing: 18

        Item {
            width: parent.width
            height: Backend.sleepTimerRunning ? countdown.implicitHeight : pickers.implicitHeight

            Behavior on height {
                ElementMove {}
            }

            Row {
                id: pickers
                anchors.centerIn: parent
                spacing: 12
                opacity: Backend.sleepTimerRunning ? 0 : 1
                visible: opacity > 0

                Behavior on opacity {
                    NumberAnimation { duration: Appearance.duration(240); easing.type: Easing.InOutQuad }
                }

                Stepper {
                    value: root.hours
                    maximum: 12
                    unit: "ч"
                    onStepped: (value) => root.hours = value
                }
                Stepper {
                    value: root.minutes
                    maximum: 59
                    unit: "мин"
                    onStepped: (value) => root.minutes = value
                }
                Stepper {
                    visible: AppSettings.debuggingEnabled
                    value: root.seconds
                    maximum: 59
                    unit: "с"
                    onStepped: (value) => root.seconds = value
                }
            }

            Item {
                id: countdown
                anchors.centerIn: parent
                implicitWidth: 236
                implicitHeight: 236
                width: implicitWidth
                height: implicitHeight
                opacity: Backend.sleepTimerRunning ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    NumberAnimation { duration: Appearance.duration(240); easing.type: Easing.InOutQuad }
                }

                SquiggleRing {
                    anchors.fill: parent
                    color: root.scheme.primary
                    trackColor: Qt.rgba(1, 1, 1, 0.14)
                    thickness: 5
                    amplitude: 3
                    wavelength: 24
                    progress: Backend.sleepTimerTotalSecs > 0 ? Math.min(1, root.remaining / Backend.sleepTimerTotalSecs) : 0

                    Behavior on progress {
                        NumberAnimation { duration: 1000 }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 6

                    RollingText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.positional(root.remaining)
                        pixelSize: 40
                        weight: Font.Bold
                        rounded: true
                        color: "white"
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "до остановки музыки"
                        color: root.secondaryText
                    }
                }
            }
        }

        SegmentedControl {
            id: fadePicker
            width: parent.width
            segmentWidth: (width - 2 * inset) / 3
            scheme: root.scheme
            trackColor: Qt.rgba(1, 1, 1, 0.08)
            indicatorColor: Qt.rgba(1, 1, 1, 0.92)
            contentColor: Qt.rgba(1, 1, 1, 0.8)
            selectedContentColor: "#141414"
            currentIndex: root.fadeIndex
            enabled: !Backend.sleepTimerRunning
            opacity: enabled ? 1 : 0.38
            segments: [
                Segment { text: "Сразу" },
                Segment { text: "10 сек" },
                Segment { text: "Плавно" }
            ]
            onActivated: (index) => AppSettings.sleepTimerFade = root.fades[index]
        }

        Column {
            width: parent.width
            spacing: 8

            TextButton {
                anchors.horizontalCenter: parent.horizontalCenter
                scheme: root.scheme
                symbol: Backend.sleepTimerRunning ? "close" : "bedtime"
                text: Backend.sleepTimerRunning ? "Отменить таймер" : "Запустить таймер"
                colBackground: Qt.rgba(1, 1, 1, 0.14)
                colBackgroundHover: Qt.rgba(1, 1, 1, 0.2)
                colRipple: Qt.rgba(1, 1, 1, 0.24)
                labelColor: Backend.sleepTimerRunning ? root.scheme.error : "white"
                enabled: Backend.sleepTimerRunning || root.duration > 0
                onClicked: {
                    if (Backend.sleepTimerRunning) {
                        Backend.cancelSleepTimer();
                    } else {
                        Backend.startSleepTimer(root.duration, AppSettings.sleepTimerFade);
                    }
                }
            }

            StyledText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.explanations[root.fadeIndex]
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.fontSize.smaller
                color: root.secondaryText
                animateChange: true
                changeDistanceY: 0
            }
        }
    }
}
