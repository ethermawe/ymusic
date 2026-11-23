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

    property list<Segment> segments
    property int currentIndex: -1
    property MaterialScheme scheme: Appearance.colors
    property color trackColor: scheme.surfaceContainerHigh
    property color indicatorColor: scheme.secondaryContainer
    property color contentColor: scheme.onSurfaceVariant
    property color selectedContentColor: scheme.onSecondaryContainer
    property real segmentHeight: 36
    property real horizontalPadding: 14
    property real iconSize: 20
    property real segmentWidth: 0
    property bool wrap: false
    property real maxWidth: 0
    property real naturalWidth: 0
    readonly property real inset: 4

    signal activated(int index)

    function updateNaturalWidth() {
        let sum = 2 * inset
        for (let i = 0; i < repeater.count; ++i) {
            const item = repeater.itemAt(i) as RippleButton
            if (item) {
                sum += segmentWidth > 0 ? segmentWidth : item.implicitWidth
            }
        }
        naturalWidth = sum
    }

    onHorizontalPaddingChanged: updateNaturalWidth()
    onSegmentWidthChanged: updateNaturalWidth()

    implicitWidth: (wrap && maxWidth > 0)
        ? Math.min(maxWidth, flow.implicitWidth + 2 * inset)
        : Math.max(naturalWidth, flow.implicitWidth + 2 * inset)
    implicitHeight: Math.max(segmentHeight, flow.implicitHeight) + 2 * inset

    property Item selectedSegment: null
    property bool built: false
    property bool sliding: false
    property int placedIndex: -1
    Component.onCompleted: {
        placedIndex = currentIndex
        selectedSegment = currentIndex >= 0 ? repeater.itemAt(currentIndex) : null
        Qt.callLater(() => root.built = true)
    }
    onCurrentIndexChanged: {
        sliding = built && placedIndex >= 0 && currentIndex >= 0
        placedIndex = currentIndex
        selectedSegment = currentIndex >= 0 ? repeater.itemAt(currentIndex) : null
    }

    Rectangle {
        anchors.fill: parent
        radius: (root.wrap && flow.implicitHeight > root.segmentHeight + 4) ? 18 : height / 2
        color: root.trackColor
    }

    Repeater {
        id: tints
        model: repeater.count

        delegate: Rectangle {
            id: tint

            required property int index
            readonly property RippleButton segment: repeater.count > index ? repeater.itemAt(index) as RippleButton : null

            x: segment ? flow.x + segment.x : 0
            y: segment ? flow.y + segment.y : root.inset
            width: segment ? segment.width : 0
            height: root.segmentHeight
            radius: height / 2
            color: segment && segment.hovered ? Appearance.fadeable(root.scheme.layer1Hover, "transparent")
                                              : Appearance.fadeable("transparent", root.scheme.layer1Hover)

            Behavior on color {
                ElementMoveFastColor {}
            }

            Ripple {
                id: ripple
                anchors.fill: parent
                cornerRadius: tint.radius
                color: root.scheme.layer1Active
            }

            Connections {
                target: tint.segment
                function onPressed() {
                    ripple.start(tint.segment.pressX, tint.segment.pressY)
                }
                function onReleased() {
                    ripple.release()
                }
                function onCanceled() {
                    ripple.release()
                }
            }

            MouseArea {
                id: disabledHover
                anchors.fill: parent
                enabled: tint.segment !== null && !tint.segment.enabled && tint.segment.tooltip.length > 0
                hoverEnabled: enabled
                acceptedButtons: Qt.NoButton
            }

            Loader {
                anchors.fill: parent
                active: disabledHover.containsMouse && disabledHover.enabled
                sourceComponent: StyledToolTip {
                    visible: true
                    text: tint.segment ? tint.segment.tooltip : ""
                }
            }
        }
    }

    Rectangle {
        id: indicator
        objectName: "selectionIndicator"

        readonly property Item target: root.selectedSegment

        visible: target !== null
        x: target ? flow.x + target.x : 0
        y: target ? flow.y + target.y : root.inset
        width: target ? target.width : 0
        height: root.segmentHeight
        radius: height / 2
        color: root.indicatorColor

        Behavior on x {
            enabled: root.sliding
            ElementMove {}
        }
        Behavior on y {
            enabled: root.sliding
            ElementMove {}
        }
        Behavior on width {
            enabled: root.sliding
            ElementMove {}
        }
    }

    Flow {
        id: flow
        x: root.inset
        y: root.inset
        spacing: root.wrap ? 4 : 0
        width: (root.wrap && root.maxWidth > 0)
            ? Math.max(1, root.maxWidth - 2 * root.inset)
            : Math.max(0, root.naturalWidth - 2 * root.inset)

        Repeater {
            id: repeater
            model: root.segments
            onItemAdded: (index, item) => {
                if (index === root.currentIndex) root.selectedSegment = item
                root.updateNaturalWidth()
            }
            onItemRemoved: (index, item) => {
                if (root.selectedSegment === item) root.selectedSegment = null
                root.updateNaturalWidth()
            }

            delegate: RippleButton {
                id: segment

                required property int index
                required property Segment modelData
                readonly property bool selected: index === root.currentIndex
                readonly property color foreground: selected ? root.selectedContentColor : root.contentColor

                onImplicitWidthChanged: root.updateNaturalWidth()

                width: root.segmentWidth > 0 ? root.segmentWidth : implicitWidth
                height: root.segmentHeight
                leftPadding: root.horizontalPadding
                rightPadding: root.horizontalPadding
                topPadding: 0
                bottomPadding: 0
                scheme: root.scheme
                enabled: modelData.enabled
                buttonRadius: height / 2
                colBackground: "transparent"
                colBackgroundHover: "transparent"
                rippleEnabled: false
                tooltip: modelData.tooltip
                onClicked: root.activated(index)

                contentItem: Item {
                    implicitWidth: content.naturalWidth
                    implicitHeight: content.implicitHeight

                    Row {
                        id: content
                        readonly property real naturalWidth: label.implicitWidth + (symbol.visible ? symbol.implicitWidth + spacing : 0)
                        anchors.centerIn: parent
                        width: Math.min(naturalWidth, parent.width)
                        spacing: 6

                        MaterialSymbol {
                            id: symbol
                            anchors.verticalCenter: parent.verticalCenter
                            visible: segment.modelData.symbol.length > 0
                            text: segment.modelData.symbol
                            iconSize: root.iconSize
                            fill: segment.selected ? 1 : 0
                            color: segment.foreground

                            Behavior on color {
                                ElementMoveFastColor {}
                            }
                        }
                        StyledText {
                            id: label
                            objectName: "segmentLabel"
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(0, content.width - (symbol.visible ? symbol.width + content.spacing : 0))
                            visible: segment.modelData.text.length > 0
                            text: segment.modelData.text
                            font.pixelSize: Appearance.fontSize.smallie
                            fontSizeMode: Text.Fit
                            minimumPixelSize: Math.min(10, font.pixelSize)
                            elide: Text.ElideRight
                            font.weight: Font.Medium
                            color: segment.foreground

                            Behavior on color {
                                ElementMoveFastColor {}
                            }
                        }
                    }
                }
            }
        }
    }
}
