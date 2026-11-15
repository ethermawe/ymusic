import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ymusic.ui

ScrollView {
    id: root
    property bool tokenMode: false
    property bool showToken: false
    property bool codeCopied: false
    property bool autoOpenOnCode: false
    readonly property string tokenAuthUrl: "https://oauth.yandex.ru/authorize?response_type=token&client_id=23cabbbdc6cd418abb4b39c32c41195d"
    clip: true
    contentWidth: availableWidth

    function switchMode(useToken) {
        if (root.tokenMode === useToken) return;
        root.tokenMode = useToken;
        root.autoOpenOnCode = false;
        root.codeCopied = false;
        if (backend.loginBusy) backend.cancelLogin();
        else backend.clearStatus();
    }

    function submitClipboardToken() {
        const clip = backend.clipboardText().trim();
        if (clip.length === 0) {
            UiState.showToast("Буфер обмена пуст — сначала скопируйте ссылку или токен.");
            return;
        }
        tokenInput.text = clip;
        backend.loginToken(clip);
    }

    component ActionButton: Button {
        id: control
        property bool primary: false
        implicitHeight: 44
        padding: 12
        hoverEnabled: true
        opacity: enabled ? 1 : 0.5
        contentItem: Text {
            text: control.text
            font.family: Appearance.fontFamily
            font.pixelSize: Appearance.fontSize.small
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: control.primary ? Appearance.colors.onPrimary : Appearance.colors.onSurface
            elide: Text.ElideRight
        }
        background: Rectangle {
            radius: Appearance.rounding.full
            color: control.primary
                   ? (control.hovered ? Appearance.colors.primaryHover : Appearance.colors.primary)
                   : (control.hovered ? Appearance.colors.surfaceContainerHighest : Appearance.colors.surfaceContainerHigh)
            Behavior on color { ColorAnimation { duration: 140 } }
        }
    }

    Item {
        width: root.availableWidth
        height: Math.max(root.availableHeight, card.implicitHeight + 48)

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(460, parent.width - 32)
            implicitHeight: form.implicitHeight + 48
            height: implicitHeight
            radius: Appearance.rounding.veryLarge
            color: Appearance.colors.surfaceContainerLow
            border.width: 1
            border.color: Appearance.colors.outlineVariant

            ColumnLayout {
                id: form
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 24
                spacing: 16

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "music_note"
                    iconSize: 44
                    color: Appearance.colors.primary
                }
                TitleText {
                    Layout.fillWidth: true
                    text: "Ваша музыка — здесь"
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
                StyledText {
                    Layout.fillWidth: true
                    text: "Войдите в Яндекс, чтобы слушать свою коллекцию и Мою волну."
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.onSurfaceVariant
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    ActionButton {
                        Layout.fillWidth: true
                        text: "Быстрый вход (код)"
                        primary: !root.tokenMode
                        onClicked: root.switchMode(false)
                    }
                    ActionButton {
                        Layout.fillWidth: true
                        text: "Токен / ссылка"
                        primary: root.tokenMode
                        onClicked: root.switchMode(true)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: !root.tokenMode
                    spacing: 12

                    StyledText {
                        Layout.fillWidth: true
                        text: "1. Нажмите кнопку — код скопируется в буфер и откроется Яндекс\n2. Вставьте код (Ctrl+V) и подтвердите вход\n3. Клиент войдёт автоматически"
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.onSurfaceVariant
                        lineHeight: 1.3
                    }

                    ActionButton {
                        Layout.fillWidth: true
                        visible: backend.loginCode.length === 0 || !backend.loginBusy
                        text: backend.loginBusy ? "Получаем код…" : "Войти через браузер"
                        primary: true
                        enabled: !backend.loginBusy
                        onClicked: {
                            root.codeCopied = false;
                            root.autoOpenOnCode = true;
                            backend.loginDevice();
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 72
                        visible: backend.loginBusy && backend.loginCode.length > 0
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.surfaceContainerHighest
                        border.color: Appearance.colors.primary
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: backend.loginCode
                            color: Appearance.colors.primary
                            font.family: Appearance.monoFontFamily
                            font.pixelSize: 28
                            font.weight: Font.Bold
                            font.letterSpacing: 4
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { backend.copyText(backend.loginCode); root.codeCopied = true; }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: backend.loginBusy && backend.loginCode.length > 0
                        spacing: 8
                        ActionButton {
                            Layout.fillWidth: true
                            text: root.codeCopied ? "Скопирован" : "Копировать"
                            onClicked: { backend.copyText(backend.loginCode); root.codeCopied = true; }
                        }
                        ActionButton {
                            Layout.fillWidth: true
                            text: "Открыть Яндекс"
                            primary: true
                            enabled: backend.loginUrl.length > 0
                            onClicked: {
                                backend.copyText(backend.loginCode);
                                root.codeCopied = true;
                                Qt.openUrlExternally(backend.loginUrl);
                            }
                        }
                        ActionButton {
                            text: "Отмена"
                            onClicked: {
                                root.autoOpenOnCode = false;
                                root.codeCopied = false;
                                backend.cancelLogin();
                            }
                        }
                    }
                    ActionButton {
                        Layout.fillWidth: true
                        visible: backend.loginBusy && backend.loginCode.length === 0
                        text: "Отмена"
                        onClicked: {
                            root.autoOpenOnCode = false;
                            backend.cancelLogin();
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: backend.loginBusy && backend.loginCode.length > 0
                        text: root.codeCopied
                              ? "Код уже в буфере (Ctrl+V). Ждём подтверждения в браузере…"
                              : "Ждём подтверждения в браузере…"
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.onSurfaceVariant
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.tokenMode
                    spacing: 12
                    StyledText {
                        Layout.fillWidth: true
                        text: "Откройте страницу Яндекса, подтвердите доступ и скопируйте ссылку из адресной строки (или сам OAuth-токен)."
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.onSurfaceVariant
                        lineHeight: 1.3
                    }
                    ActionButton {
                        Layout.fillWidth: true
                        text: "Открыть страницу токена"
                        onClicked: Qt.openUrlExternally(root.tokenAuthUrl)
                    }
                    TextField {
                        id: tokenInput
                        Layout.fillWidth: true
                        implicitHeight: 48
                        placeholderText: "Токен или ссылка (#access_token=...)"
                        echoMode: root.showToken ? TextInput.Normal : TextInput.Password
                        enabled: !backend.loginBusy
                        selectByMouse: true
                        color: Appearance.colors.onSurface
                        placeholderTextColor: Appearance.colors.onSurfaceVariant
                        leftPadding: 14
                        rightPadding: 14
                        background: Rectangle {
                            radius: Appearance.rounding.small
                            color: Appearance.colors.surfaceContainerHighest
                            border.width: 1
                            border.color: tokenInput.activeFocus ? Appearance.colors.primary : Appearance.colors.outlineVariant
                        }
                        onAccepted: if (text.trim().length > 0 && !backend.loginBusy) backend.loginToken(text.trim())
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        ActionButton {
                            text: root.showToken ? "Скрыть" : "Показать"
                            onClicked: root.showToken = !root.showToken
                        }
                        ActionButton {
                            Layout.fillWidth: true
                            text: "Вставить и войти"
                            enabled: !backend.loginBusy
                            onClicked: root.submitClipboardToken()
                        }
                        ActionButton {
                            Layout.fillWidth: true
                            text: backend.loginBusy ? "Проверяем…" : "Войти"
                            primary: true
                            enabled: !backend.loginBusy && tokenInput.text.trim().length > 0
                            onClicked: backend.loginToken(tokenInput.text.trim())
                        }
                    }
                    ActionButton {
                        Layout.fillWidth: true
                        visible: backend.loginBusy
                        text: "Отмена"
                        onClicked: backend.cancelLogin()
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: backend.statusMessage.length > 0
                    text: backend.statusMessage
                    color: Appearance.colors.error
                    wrapMode: Text.WordWrap
                }

                ActionButton {
                    Layout.fillWidth: true
                    text: "Открыть загрузки (офлайн)"
                    onClicked: {
                        if (backend.loginBusy) backend.cancelLogin();
                        backend.loadDownloads();
                    }
                }
            }
        }
    }

    Connections {
        target: backend
        function onAuthChanged() {
            if (backend.loggedIn) {
                tokenInput.clear();
                root.showToken = false;
                root.codeCopied = false;
                root.autoOpenOnCode = false;
                return;
            }
            if (backend.loginBusy && backend.loginCode.length > 0) {
                backend.copyText(backend.loginCode);
                root.codeCopied = true;
                if (root.autoOpenOnCode && backend.loginUrl.length > 0) {
                    root.autoOpenOnCode = false;
                    Qt.openUrlExternally(backend.loginUrl);
                }
            }
        }
    }
}
