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

RippleButton {
    id: root

    enum Variant {
        Standard,
        Filled,
        Tonal,
        Outlined
    }

    property int variant: IconButton.Standard
    property string burst
    property string symbol
    property real iconSize: 24
    property real iconRotation: 0
    property real size: 40
    property bool fillWhenToggled: true
    property bool alwaysFilled: false
    property bool toggleable: false
    property color iconColor: {
        switch (variant) {
        case IconButton.Filled:
            return toggled || !toggleable ? scheme.onPrimary : scheme.primary
        case IconButton.Tonal:
            return toggled ? scheme.onSecondaryContainer : scheme.onSurfaceVariant
        default:
            return toggled ? scheme.primary : scheme.onSurfaceVariant
        }
    }

    implicitWidth: size
    implicitHeight: size
    padding: 0
    buttonRadius: Appearance.rounding.full
    colBackground: {
        switch (variant) {
        case IconButton.Filled:
            return toggled || !toggleable ? scheme.primary : scheme.surfaceContainerHighest
        case IconButton.Tonal:
            return toggled ? scheme.secondaryContainer : scheme.surfaceContainerHighest
        default:
            return "transparent"
        }
    }
    colBackgroundHover: {
        switch (variant) {
        case IconButton.Filled:
            return toggled || !toggleable ? scheme.primaryHover : scheme.surfaceContainerHighestHover
        case IconButton.Tonal:
            return toggled ? scheme.secondaryContainerHover : scheme.surfaceContainerHighestHover
        default:
            return scheme.layer1Hover
        }
    }
    colBackgroundToggled: variant === IconButton.Standard || variant === IconButton.Outlined ? "transparent" : colBackground
    colBackgroundToggledHover: variant === IconButton.Standard || variant === IconButton.Outlined ? scheme.layer1Hover : colBackgroundHover
    colRipple: variant === IconButton.Filled ? scheme.primaryActive : scheme.layer1Active
    colRippleToggled: colRipple
    backgroundItem.border.width: variant === IconButton.Outlined && !toggled ? 1 : (visualFocus ? 2 : 0)
    backgroundItem.border.color: variant === IconButton.Outlined && !visualFocus ? scheme.outlineVariant : scheme.secondary

    contentItem: Item {
        MaterialSymbol {
            anchors.centerIn: parent
            text: root.symbol
            iconSize: root.iconSize
            fill: root.alwaysFilled || (root.toggled && root.fillWhenToggled) ? 1 : 0
            color: root.iconColor
            rotation: root.iconRotation

            Behavior on color {
                ElementMoveFastColor {}
            }
            Behavior on rotation {
                enabled: !Appearance.performanceMode
                ElementMoveSmall {}
            }
        }
    }

    onClicked: if (burst.length > 0) UiState.burst(root, burst)
}
