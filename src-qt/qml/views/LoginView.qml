pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ymusic.ui

ScrollView {
    id: root
    property bool tokenMode: false
    property bool showToken: false
    property bool codeCopied: false
    readonly property string tokenAuthUrl: "https://oauth.yandex.ru/authorize?response_type=token&client_id=23cabbbdc6cd418abb4b39c32c41195d"
    clip: true
    contentWidth: availableWidth

    function ensureDeviceCode() {
        if (root.tokenMode || backend.loggedIn || backend.loginBusy) return;
        root.codeCopied = false;
        backend.loginDevice();
    }

    function refreshDeviceCode() {
        root.codeCopied = false;
        if (backend.loginBusy) backend.cancelLogin();
        Qt.callLater(() => {
            if (!root.tokenMode && !backend.loggedIn) {
                backend.loginDevice();
            }
        });
    }

    function switchMode(useToken: bool) {
        if (root.tokenMode === useToken) return;
        root.tokenMode = useToken;
        root.codeCopied = false;
        if (useToken) {
            if (backend.loginBusy) backend.cancelLogin();
            else backend.clearStatus();
        } else {
            backend.clearStatus();
            Qt.callLater(root.ensureDeviceCode);
        }
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

    Component.onCompleted: Qt.callLater(root.ensureDeviceCode)
    onVisibleChanged: if (visible) Qt.callLater(root.ensureDeviceCode)

    Item {
        width: root.availableWidth
        height: Math.max(root.availableHeight, card.implicitHeight + 48)

        SoftShadow {
            anchors.fill: card
            radius: card.radius
            blur: 28
            offset: Qt.vector2d(0, 10)
            color: Qt.rgba(0, 0, 0, Appearance.colors.dark ? 0.36 : 0.10)
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(480, parent.width - 32)
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

                ShapeIcon {
                    Layout.alignment: Qt.AlignHCenter
                    size: 56
                    iconSize: 28
                    shape: "cookie9"
                    symbol: "music_note"
                    color: Appearance.colors.primaryContainer
                    iconColor: Appearance.colors.onPrimaryContainer
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    TitleText {
                        Layout.fillWidth: true
                        text: "Вход в Яндекс Музыку"
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: "Поддерживается Яндекс Ключ, SMS и любая 2FA."
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.fontSize.smaller
                        color: Appearance.colors.onSurfaceVariant
                    }
                }

                SegmentedControl {
                    Layout.alignment: Qt.AlignHCenter
                    currentIndex: root.tokenMode ? 1 : 0
                    segments: [
                        Segment { symbol: "qr_code_2"; text: "QR и браузер" },
                        Segment { symbol: "key"; text: "Токен" }
                    ]
                    onActivated: (index) => root.switchMode(index === 1)
                }

                // QR + Device Code login
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: !root.tokenMode
                    spacing: 14

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        width: 196
                        height: 196
                        radius: Appearance.rounding.large
                        color: "#ffffff"
                        border.width: 1
                        border.color: Appearance.colors.outlineVariant

                        Image {
                            id: qrImage
                            anchors.fill: parent
                            anchors.margins: 10
                            visible: backend.loginUrl.length > 0 && backend.loginCode.length > 0
                            source: visible ? ("image://qr/" + encodeURIComponent(backend.loginUrl)) : ""
                            sourceSize: Qt.size(256, 256)
                            fillMode: Image.PreserveAspectFit
                            smooth: false
                            mipmap: false
                            cache: false
                        }

                        LoadingSpinner {
                            anchors.centerIn: parent
                            running: !qrImage.visible && backend.loginBusy
                            visible: running
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: !qrImage.visible && !backend.loginBusy
                            text: "qr_code_2"
                            iconSize: 48
                            color: "#888888"
                        }
                    }

                    Rectangle {
                        id: codeBox
                        Layout.fillWidth: true
                        Layout.preferredHeight: 62
                        visible: backend.loginCode.length > 0
                        radius: Appearance.rounding.normal
                        color: codeHover.hovered
                            ? Appearance.colors.surfaceContainerHighest
                            : Appearance.colors.surfaceContainerHigh
                        border.color: Appearance.colors.primary
                        border.width: 1

                        Behavior on color { ElementMoveFastColor {} }

                        Row {
                            anchors.centerIn: parent
                            spacing: 10

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: backend.loginCode
                                color: Appearance.colors.primary
                                font.family: Appearance.monoFontFamily
                                font.pixelSize: 26
                                font.weight: Font.Bold
                                font.letterSpacing: 4
                            }

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.codeCopied ? "check" : "content_copy"
                                iconSize: 18
                                color: Appearance.colors.onSurfaceVariant
                            }
                        }

                        HoverHandler {
                            id: codeHover
                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            onTapped: {
                                backend.copyText(backend.loginCode);
                                root.codeCopied = true;
                                UiState.showToast("Код скопирован в буфер обмена");
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: backend.loginCode.length > 0
                            ? "Отсканируйте QR телефоном или откройте Яндекс в браузере и введите код выше — вход завершится автоматически."
                            : "Запрашиваем одноразовый код входа у Яндекса…"
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.fontSize.smaller
                        color: Appearance.colors.onSurfaceVariant
                        lineHeight: 1.3
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        TextButton {
                            Layout.fillWidth: true
                            variant: TextButton.Filled
                            symbol: "open_in_new"
                            text: "Открыть в браузере"
                            enabled: backend.loginUrl.length > 0 && backend.loginCode.length > 0
                            onClicked: {
                                backend.copyText(backend.loginCode);
                                root.codeCopied = true;
                                Qt.openUrlExternally(backend.loginUrl);
                                UiState.showToast("Код скопирован — вставьте его (Ctrl+V) в браузере");
                            }
                        }

                        TextButton {
                            variant: TextButton.Outlined
                            symbol: "refresh"
                            text: "Новый код"
                            onClicked: root.refreshDeviceCode()
                        }
                    }
                }

                // Token login
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.tokenMode
                    spacing: 12

                    StyledText {
                        Layout.fillWidth: true
                        text: "Откройте страницу Яндекса, подтвердите доступ и скопируйте ссылку из адресной строки (или сам OAuth-токен)."
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.fontSize.smaller
                        color: Appearance.colors.onSurfaceVariant
                        lineHeight: 1.3
                    }

                    TextButton {
                        Layout.fillWidth: true
                        variant: TextButton.Tonal
                        symbol: "open_in_new"
                        text: "Открыть страницу токена"
                        onClicked: Qt.openUrlExternally(root.tokenAuthUrl)
                    }

                    TextField {
                        id: tokenInput
                        Layout.fillWidth: true
                        implicitHeight: 46
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

                        IconButton {
                            symbol: root.showToken ? "visibility_off" : "visibility"
                            tooltip: root.showToken ? "Скрыть" : "Показать"
                            onClicked: root.showToken = !root.showToken
                        }

                        TextButton {
                            Layout.fillWidth: true
                            variant: TextButton.Tonal
                            symbol: "content_paste"
                            text: "Вставить и войти"
                            enabled: !backend.loginBusy
                            onClicked: root.submitClipboardToken()
                        }

                        TextButton {
                            Layout.fillWidth: true
                            variant: TextButton.Filled
                            text: backend.loginBusy ? "Проверяем…" : "Войти"
                            enabled: !backend.loginBusy && tokenInput.text.trim().length > 0
                            onClicked: backend.loginToken(tokenInput.text.trim())
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: backend.statusMessage.length > 0
                    text: backend.statusMessage
                    color: Appearance.colors.error
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.fontSize.smaller
                }

                TextButton {
                    Layout.fillWidth: true
                    variant: TextButton.Text
                    symbol: "download_done"
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
            }
        }
    }
}
