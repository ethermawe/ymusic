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
import QtQuick.Templates as T
import ymusic.ui

Loader {
    id: root

    active: false

    Item { id: popupAnchor }

    function popupAt(anchor: Item, x: real, y: real) {
        active = true
        const menu = item as T.Menu
        if (menu.visible) {
            menu.close()
            return
        }
        menu.contentItem.forceLayout()
        const popupParent = anchor.Window.window ? anchor.Window.window.contentItem : anchor.parent
        const position = anchor.parent.mapToItem(popupParent, anchor.x, anchor.y)
        popupAnchor.parent = popupParent
        popupAnchor.x = position.x
        popupAnchor.y = position.y
        popupAnchor.width = anchor.width
        popupAnchor.height = anchor.height
        menu.closePolicy = T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutsideParent
        menu.popup(popupAnchor, x, y)
    }

    function popupHere() {
        active = true
        const menu = item as T.Menu
        menu.contentItem.forceLayout()
        menu.popup()
    }
}
