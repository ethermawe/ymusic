import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ymusic.ui

Dialog {
    id: root
    property bool busy: false
    property string errorMessage: ""
    title: "Новый плейлист"
    modal: true
    focus: true
    anchors.centerIn: parent
    width: Math.min(440, parent ? parent.width - 32 : 440)
    padding: 24
    closePolicy: busy ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onOpened: { name.forceActiveFocus(); errorMessage = ""; }
    background: Rectangle {
        radius: Appearance.rounding.large
        color: Appearance.colors.surfaceContainerHigh
        border.width: 1
        border.color: Appearance.colors.outlineVariant
    }
    header: Label { text: root.title; padding: 24; font.pixelSize: 22; color: Appearance.colors.onSurface }
    contentItem: ColumnLayout {
        spacing: 16
        TextField {
            id: name
            Layout.fillWidth: true
            placeholderText: "Название плейлиста"
            maximumLength: 100
            enabled: !root.busy
            selectByMouse: true
            color: Appearance.colors.onSurface
            placeholderTextColor: Appearance.colors.onSurfaceVariant
            background: Rectangle { color: Appearance.colors.surfaceContainerLowest; radius: 10 }
        }
        StyledCheckBox {
            id: privatePlaylist
            text: "Приватный плейлист"
            checked: true
            enabled: !root.busy
            palette.windowText: Appearance.colors.onSurface
        }
        StyledText {
            Layout.fillWidth: true
            text: root.busy ? "Создаём плейлист…" : root.errorMessage
            visible: text.length > 0
            wrapMode: Text.WordWrap
        }
    }
    // Intercept the button box: do not close until the server confirms success.
    footer: RowLayout {
        spacing: 12
        Item { Layout.fillWidth: true }
        StyledButton {
            Layout.bottomMargin: 20
            text: "Отмена"
            enabled: !root.busy
            onClicked: root.close()
        }
        StyledButton {
            Layout.bottomMargin: 20
            Layout.rightMargin: 24
            text: root.busy ? "Создаём…" : "Создать"
            highlighted: true
            enabled: !root.busy && name.text.trim().length > 0 && backend.loggedIn
            onClicked: {
            root.busy = true;
            root.errorMessage = "";
            backend.feature({action: "create_playlist", title: name.text.trim(), private: privatePlaylist.checked});
            }
        }
    }
    Connections {
        target: backend
        function onFeatureResult(result) {
            if (result.type !== "create_playlist" || !root.busy) return;
            root.busy = false;
            if (result.ok) { name.clear(); root.close(); backend.clearStatus(); }
            else root.errorMessage = result.message;
        }
        function onAuthChanged() { if (!backend.loggedIn) { root.busy = false; root.close(); } }
    }
}
