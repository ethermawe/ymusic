import QtQuick
import ymusic.ui

Text {
    id: root

    property var links: []
    property string fallbackText: ""
    property bool clickable: true
    property bool fallbackClickable: false
    property bool handleDefaultFallback: true
    signal artistActivated()
    signal fallbackActivated()

    function escapeHtml(s) {
        return String(s || "")
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;");
    }

    function buildRichText() {
        const list = root.links || [];
        const c = root.color.toString();
        if (!root.clickable || list.length === 0) {
            return escapeHtml(root.fallbackText);
        }
        let parts = [];
        for (let i = 0; i < list.length; i++) {
            const item = list[i];
            if (!item || !item.name) continue;
            const id = String(item.id || "");
            const name = escapeHtml(item.name);
            if (!id) {
                parts.push(name);
            } else {
                const inner = root.hoveredLink === id ? ("<u>" + name + "</u>") : name;
                parts.push('<a href="' + escapeHtml(id) + '" style="text-decoration:none; color:' + c + ';">' + inner + '</a>');
            }
        }
        return parts.length > 0 ? parts.join(", ") : escapeHtml(root.fallbackText);
    }

    textFormat: Text.RichText
    text: buildRichText()
    color: Appearance.colors.onSurfaceVariant
    linkColor: color
    font.family: Appearance.fontFamily
    font.pixelSize: Appearance.fontSize.smaller
    font.underline: (!root.links || root.links.length === 0) && root.clickable && root.fallbackClickable && fallbackHover.hovered
    clip: true

    onLinkActivated: (link) => {
        if (root.clickable && link) {
            backend.openArtist(link);
            root.artistActivated();
        }
    }

    HoverHandler {
        id: fallbackHover
        cursorShape: root.clickable && (root.hoveredLink.length > 0 || ((!root.links || root.links.length === 0) && root.fallbackClickable))
            ? Qt.PointingHandCursor
            : Qt.ArrowCursor
    }

    TapHandler {
        enabled: root.clickable && (!root.links || root.links.length === 0) && root.fallbackClickable
        onTapped: {
            if (root.handleDefaultFallback) {
                backend.openNowArtist();
                root.artistActivated();
            } else {
                root.fallbackActivated();
            }
        }
    }
}
