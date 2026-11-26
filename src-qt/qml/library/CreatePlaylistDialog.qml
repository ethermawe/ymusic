pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import ymusic.ui

StyledDialog {
    id: root

    property bool busy: false
    property string errorMessage: ""

    headline: "Новый плейлист"
    symbol: "playlist_add"
    iconShape: "bun"
    preferredWidth: 440
    closePolicy: busy ? T.Popup.NoAutoClose : (T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutside)

    onOpened: {
        name.inputItem.forceActiveFocus();
        errorMessage = "";
    }

    OutlinedTextField {
        id: name
        width: parent.width
        placeholder: "Название плейлиста"
        enabled: !root.busy
        onTextEdited: if (text.length > 100) text = text.slice(0, 100)
        onAccepted: if (!root.busy && text.trim().length > 0 && Backend.loggedIn) root.createPlaylist()
    }

    Item {
        width: parent.width
        height: 44

        StyledText {
            anchors.left: parent.left
            anchors.right: privatePlaylist.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: "Приватный плейлист"
            font.pixelSize: Appearance.fontSize.small
        }
        StyledSwitch {
            id: privatePlaylist
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: true
            enabled: !root.busy
        }
    }

    StyledText {
        width: parent.width
        text: root.busy ? "Создаём плейлист…" : root.errorMessage
        visible: text.length > 0
        wrapMode: Text.WordWrap
        color: root.busy ? Appearance.colors.onSurfaceVariant : Appearance.colors.error
    }

    function createPlaylist() {
        root.busy = true;
        root.errorMessage = "";
        Backend.feature({action: "create_playlist", title: name.text.trim(), private: privatePlaylist.checked});
    }

    buttons: [
        TextButton {
            text: "Отмена"
            variant: TextButton.Text
            enabled: !root.busy
            onClicked: root.close()
        },
        TextButton {
            text: root.busy ? "Создаём…" : "Создать"
            variant: TextButton.Filled
            wavy: enabled
            enabled: !root.busy && name.text.trim().length > 0 && Backend.loggedIn
            onClicked: root.createPlaylist()
        }
    ]

    Connections {
        target: Backend
        function onFeatureResult(result) {
            if (result.type !== "create_playlist" || !root.busy) return;
            root.busy = false;
            if (result.ok) {
                name.inputItem.clear();
                root.accept();
                Backend.clearStatus();
            } else {
                root.errorMessage = result.message;
            }
        }
        function onAuthChanged() {
            if (!Backend.loggedIn) {
                root.busy = false;
                root.close();
            }
        }
    }
}
