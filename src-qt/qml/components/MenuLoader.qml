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
