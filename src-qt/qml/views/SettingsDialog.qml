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
import QtQuick.Controls.Basic
import QtQuick.Templates as T
import ymusic.ui

T.Popup {
    id: root

    property int page: 0
    property string activeModTabId: ""
    readonly property var modTabs: ModManager.reloadRevision >= 0 ? ModManager.slotEntries("settings.tab") : []
    readonly property list<string> titles: [
        "Оформление", "Плеер и фон", "Звук",
        "Анимации", "Интеграции", "Моды", "Система"
    ]
    readonly property list<string> symbols: [
        "palette", "wallpaper", "play_circle",
        "animation", "extension", "widgets", "tune"
    ]
    readonly property list<string> shapes: [
        "clover4", "flower", "cookie9",
        "gem", "sunny", "softBurst", "cookie12"
    ]

    parent: T.Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(860, parent ? parent.width - 48 : 860)
    height: Math.min(640, parent ? parent.height - 48 : 640)
    modal: true
    focus: true
    closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutside
    padding: 0
    popupType: T.Popup.Item

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Appearance.duration(150) }
        NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: Appearance.motion(380); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.curves.expressiveFastSpatial }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; to: 0; duration: Appearance.duration(120) }
        NumberAnimation { property: "scale"; to: 0.97; duration: Appearance.duration(120) }
    }

    T.Overlay.modal: Rectangle {
        color: Appearance.colors.scrimOverlay
    }

    background: Rectangle {
        radius: Appearance.rounding.large + 8
        color: Appearance.colors.layer0
        border.width: 1
        border.color: Appearance.colors.layer0Border
    }

    contentItem: Item {
        Shortcut {
            sequences: [StandardKey.Close]
            enabled: root.opened
            onActivated: root.close()
        }

        Flickable {
            id: railScroller
            objectName: "settingsRail"
            x: 12
            width: 108
            height: parent.height
            contentHeight: rail.implicitHeight + 32
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            clip: true

            ScrollBar.vertical: StyledScrollBar {}

            Column {
                id: rail
                y: 16
                width: railScroller.width
                spacing: 4

                Repeater {
                    model: root.titles.length

                    delegate: RippleButton {
                        id: destination

                        required property int index
                        readonly property bool selected: root.activeModTabId.length === 0 && root.page === index

                        width: rail.width
                        implicitHeight: 68
                        padding: 0
                        colBackground: "transparent"
                        colBackgroundHover: "transparent"
                        rippleEnabled: false
                        onClicked: {
                            root.activeModTabId = "";
                            root.page = index;
                        }

                        contentItem: Column {
                            spacing: 4

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 56
                                height: 32
                                radius: height / 2
                                color: Qt.alpha(Appearance.colors.layer1Hover, !destination.selected && destination.hovered ? 1 : 0)

                                Behavior on color {
                                    ElementMoveFastColor {}
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    Reveal.shown: !destination.selected
                                    text: root.symbols[destination.index]
                                    iconSize: 22
                                    color: Appearance.colors.onSurfaceVariant
                                }
                                ShapeIcon {
                                    anchors.centerIn: parent
                                    Reveal.shown: destination.selected
                                    Reveal.overshoot: 2.4
                                    size: 38
                                    iconSize: 20
                                    shape: root.shapes[destination.index]
                                    symbol: root.symbols[destination.index]
                                    hovered: destination.hovered
                                }
                            }

                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: rail.width
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: root.titles[destination.index]
                                font.pixelSize: Appearance.fontSize.smaller
                                font.weight: destination.selected ? Font.DemiBold : Font.Normal
                                color: destination.selected ? Appearance.colors.onSurface : Appearance.colors.onSurfaceVariant
                            }
                        }
                    }
                }

                Repeater {
                    model: root.modTabs

                    delegate: RippleButton {
                        id: modDest
                        required property var modelData
                        readonly property bool selected: root.activeModTabId === modelData.modId

                        width: rail.width
                        implicitHeight: 68
                        padding: 0
                        colBackground: "transparent"
                        colBackgroundHover: "transparent"
                        rippleEnabled: false
                        onClicked: root.activeModTabId = modelData.modId

                        contentItem: Column {
                            spacing: 4

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 56
                                height: 32
                                radius: height / 2
                                color: Qt.alpha(Appearance.colors.layer1Hover, !modDest.selected && modDest.hovered ? 1 : 0)

                                Behavior on color {
                                    ElementMoveFastColor {}
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    Reveal.shown: !modDest.selected
                                    text: modDest.modelData.settingsTabSymbol || "widgets"
                                    iconSize: 22
                                    color: Appearance.colors.onSurfaceVariant
                                }
                                ShapeIcon {
                                    anchors.centerIn: parent
                                    Reveal.shown: modDest.selected
                                    Reveal.overshoot: 2.4
                                    size: 38
                                    iconSize: 20
                                    shape: modDest.modelData.settingsTabShape || "flower"
                                    symbol: modDest.modelData.settingsTabSymbol || "widgets"
                                    hovered: modDest.hovered
                                }
                            }

                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: rail.width
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: modDest.modelData.settingsTabTitle || modDest.modelData.modName || ""
                                font.pixelSize: Appearance.fontSize.smaller
                                font.weight: modDest.selected ? Font.DemiBold : Font.Normal
                                color: modDest.selected ? Appearance.colors.onSurface : Appearance.colors.onSurfaceVariant
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.left: railScroller.right
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.top: parent.top
            anchors.topMargin: 8
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            radius: Appearance.rounding.large
            color: Appearance.colors.layer1

            Stickers {
                anchors.fill: parent
                anchors.margins: 6
                key: root.activeModTabId.length > 0 ? root.activeModTabId : root.titles[root.page]
                count: 4
                minimumSize: 90
                maximumSize: 220
                clipRadius: Appearance.rounding.large - 6
            }

            Flickable {
                id: scroller
                anchors.fill: parent
                anchors.margins: 20
                contentHeight: pages.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                FastWheel { target: scroller }

                SettingsPages {
                    id: pages
                    width: scroller.width
                    page: root.page
                    activeModTabId: root.activeModTabId

                    onPageChanged: {
                        scroller.contentY = 0;
                        if (!Appearance.performanceMode && !Appearance.reduceMotion) {
                            arrive.restart();
                        }
                    }
                    onActiveModTabIdChanged: {
                        scroller.contentY = 0;
                        if (!Appearance.performanceMode && !Appearance.reduceMotion) {
                            arrive.restart();
                        }
                    }

                    ParallelAnimation {
                        id: arrive
                        NumberAnimation { target: pages; property: "opacity"; from: 0.4; to: 1; duration: Appearance.duration(180); easing.type: Easing.OutCubic }
                        NumberAnimation { target: pages; property: "y"; from: 12; to: 0; duration: Appearance.motion(260); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.curves.expressiveFastSpatial }
                    }
                }

                ScrollBar.vertical: StyledScrollBar {}
            }
        }

        ToolbarButton {
            anchors.top: parent.top
            anchors.topMargin: 18
            anchors.right: parent.right
            anchors.rightMargin: 18
            z: 2
            shape: "cookie6"
            symbol: "close"
            onClicked: root.close()
            tooltip: "Закрыть"
        }
    }
}
