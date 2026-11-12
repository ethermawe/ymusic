import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ymusic.ui

Popup {
    id: root
    property int page: 0
    readonly property var titles: ["Интерфейс", "Графика", "Загрузки", "Аккаунт"]
    readonly property var symbols: ["interface", "settings", "download_done", "person"]
    readonly property var shapes: ["flower", "cookie9", "clover4", "softCookie"]
    property string errorMessage: ""
    modal: true
    focus: true
    width: Math.min(860, parent ? parent.width - 32 : 860)
    height: Math.min(640, parent ? parent.height - 32 : 640)
    anchors.centerIn: parent
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onPageChanged: { settingsFlickable.contentY = 0; errorMessage = ""; }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Appearance.reduceMotion ? 0 : 160 }
        NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Appearance.reduceMotion ? 0 : 260; easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; to: 0; duration: Appearance.reduceMotion ? 0 : 120 }
    }
    Overlay.modal: Rectangle { color: "#80000000" }
    background: Rectangle {
        radius: Appearance.rounding.veryLarge
        color: Appearance.colors.surfaceContainerLowest
        border.width: 1
        border.color: Appearance.colors.outlineVariant
    }

    component Note: StyledText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: Appearance.colors.onSurfaceVariant
        font.pixelSize: Appearance.fontSize.smaller
    }
    component Card: Rectangle {
        id: card
        default property alias contents: body.data
        Layout.fillWidth: true
        implicitHeight: body.implicitHeight + 16
        radius: Appearance.rounding.normal
        color: Appearance.colors.surfaceContainerLow
        ColumnLayout {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            spacing: 4
        }
    }
    component ToggleRow: ItemDelegate {
        id: control
        property string description: ""
        property bool value: false
        signal changedTo(bool value)
        Layout.fillWidth: true
        implicitHeight: Math.max(72, labels.implicitHeight + 24)
        padding: 12
        Accessible.name: text
        onClicked: changedTo(!value)
        background: Rectangle {
            radius: Appearance.rounding.small
            color: control.hovered ? Appearance.colors.surfaceContainerHigh : "transparent"
            Behavior on color { ColorAnimation { duration: Appearance.duration(140) } }
        }
        contentItem: RowLayout {
            spacing: 16
            ColumnLayout {
                id: labels
                Layout.fillWidth: true
                spacing: 5
                StyledText {
                    Layout.fillWidth: true
                    text: control.text
                    font.weight: Font.Medium
                    wrapMode: Text.WordWrap
                }
                Note { text: control.description }
            }
            Rectangle {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 28
                radius: 14
                color: control.value ? Appearance.colors.primary : Appearance.colors.surfaceContainerHighest
                border.width: control.value ? 0 : 1
                border.color: Appearance.colors.outline
                Rectangle {
                    x: control.value ? 24 : 4
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20; height: 20; radius: 10
                    color: control.value ? Appearance.colors.onPrimary : Appearance.colors.onSurfaceVariant
                    Behavior on x { NumberAnimation { duration: Appearance.reduceMotion ? 0 : 180; easing.type: Easing.OutCubic } }
                }
            }
        }
    }
    component ActionRow: ItemDelegate {
        id: action
        property string description: ""
        Layout.fillWidth: true
        implicitHeight: Math.max(64, actionLabels.implicitHeight + 24)
        padding: 12
        contentItem: RowLayout {
            ColumnLayout {
                id: actionLabels
                Layout.fillWidth: true
                StyledText { Layout.fillWidth: true; text: action.text; wrapMode: Text.WordWrap; font.weight: Font.Medium }
                Note { text: action.description; visible: text.length > 0 }
            }
            MaterialSymbol { text: "chevron_right"; iconSize: 20; color: Appearance.colors.onSurfaceVariant }
        }
        background: Rectangle {
            radius: Appearance.rounding.small
            color: action.hovered ? Appearance.colors.surfaceContainerHigh : "transparent"
        }
    }

    contentItem: Item {
        Flickable {
            id: railScroller
            x: 8; y: 12
            width: 108
            height: parent.height - 24
            contentHeight: rail.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: rail
                width: railScroller.width
                spacing: 8
                Repeater {
                    model: root.titles.length
                    delegate: ItemDelegate {
                        id: destination
                        required property int index
                        readonly property bool selected: root.page === index
                        width: rail.width
                        height: 82
                        padding: 4
                        onClicked: root.page = index
                        background: Item {}
                        contentItem: Column {
                            spacing: 8
                            Item {
                                width: 56; height: 38
                                anchors.horizontalCenter: parent.horizontalCenter
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 19
                                    color: destination.hovered && !destination.selected ? Appearance.colors.surfaceContainerHigh : "transparent"
                                }
                                MaterialShape {
                                    anchors.centerIn: parent
                                    width: 38; height: 38
                                    shape: root.shapes[destination.index]
                                    color: Appearance.colors.primaryContainer
                                    opacity: destination.selected ? 1 : 0
                                    scale: destination.selected ? 1 : 0.6
                                    spinAngle: destination.hovered ? 20 : 0
                                    Behavior on opacity { NumberAnimation { duration: Appearance.duration(160) } }
                                    Behavior on scale { NumberAnimation { duration: Appearance.motion(280); easing.type: Easing.OutBack } }
                                    Behavior on spinAngle { NumberAnimation { duration: Appearance.motion(280); easing.type: Easing.OutBack } }
                                }
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: root.symbols[destination.index]
                                    iconSize: 21
                                    color: destination.selected ? Appearance.colors.onPrimaryContainer : Appearance.colors.onSurfaceVariant
                                }
                            }
                            StyledText {
                                width: parent.width
                                text: root.titles[destination.index]
                                horizontalAlignment: Text.AlignHCenter
                                font.pixelSize: Appearance.fontSize.smaller
                                font.weight: destination.selected ? Font.DemiBold : Font.Normal
                                color: destination.selected ? Appearance.colors.onSurface : Appearance.colors.onSurfaceVariant
                            }
                        }
                    }
                }
            }
            ScrollBar.vertical: ScrollBar {}
        }

        Rectangle {
            anchors.left: railScroller.right
            anchors.leftMargin: 8
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 8
            radius: Appearance.rounding.large
            color: Appearance.colors.surfaceContainer

            Flickable {
                anchors.fill: parent
                anchors.margins: 24
                anchors.topMargin: 64
                clip: true
                id: settingsFlickable
                contentWidth: width
                contentHeight: settingsContent.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}
                ColumnLayout {
                    id: settingsContent
                    width: settingsFlickable.width
                    spacing: 16
                    TitleText {
                        Layout.fillWidth: true
                        text: root.titles[root.page]
                        font.pixelSize: Appearance.fontSize.headline
                        wrapMode: Text.WordWrap
                    }
                    Note {
                        text: ["Внешний вид и движение — под ваши предпочтения.",
                               "Настройки отрисовки и расхода ресурсов.",
                               "Музыка, сохранённая на этом устройстве.",
                               "Ваш аккаунт Яндекс Музыки."][root.page]
                    }
                    Card {
                        visible: root.page === 0
                        ToggleRow {
                            text: "Движение при воспроизведении"
                            description: "Вращение Play, волны, индикаторы и перелистывание цифр."
                            value: appSettings.motionEnabled
                            onChangedTo: (value) => appSettings.motionEnabled = value
                        }
                        ToggleRow {
                            text: "Обложки и аватары"
                            description: "Отключите, чтобы уменьшить расход памяти и сетевые запросы."
                            value: appSettings.coversEnabled
                            onChangedTo: (value) => appSettings.coversEnabled = value
                        }
                    }
                    Card {
                        visible: root.page === 1
                        ToggleRow {
                            text: "Сглаживание SVG"
                            description: "MSAA ×4: более ровные края, дополнительные GPU-буферы."
                            value: appSettings.iconAntialiasing
                            onChangedTo: (value) => appSettings.iconAntialiasing = value
                        }
                    }
                    Card {
                        visible: root.page === 1
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.margins: 12
                            spacing: 12
                            StyledText { text: "Графический API"; font.weight: Font.Medium }
                            ComboBox {
                                Layout.fillWidth: true
                                model: ["Автоматически (Qt)", "Vulkan", "OpenGL"]
                                currentIndex: appSettings.graphicsBackend === "vulkan" ? 1 : (appSettings.graphicsBackend === "opengl" ? 2 : 0)
                                onActivated: (index) => appSettings.graphicsBackend = ["auto", "vulkan", "opengl"][index]
                                palette.button: Appearance.colors.surfaceContainerHighest
                                palette.buttonText: Appearance.colors.onSurface
                                palette.base: Appearance.colors.surfaceContainerHigh
                                palette.text: Appearance.colors.onSurface
                                palette.highlight: Appearance.colors.primaryContainer
                                palette.highlightedText: Appearance.colors.onSurface
                                Accessible.name: "Графический API"
                            }
                            Note { text: "Применится после перезапуска. Если Vulkan работает нестабильно, выберите OpenGL. Параметры --graphics и QSG_RHI_BACKEND имеют приоритет." }
                        }
                    }
                    Card {
                        visible: root.page === 2
                        ActionRow {
                            text: "Открыть загруженные треки"
                            description: "Список треков, размер загрузок и удаление файлов."
                            onClicked: { backend.loadDownloads(); root.close(); }
                        }
                        ActionRow {
                            text: "Папка загрузок"
                            description: "Открыть сохранённое аудио в файловом менеджере."
                            onClicked: if (!appSettings.openOfflineFolder()) root.errorMessage = "Не удалось открыть папку загрузок."
                        }
                    }
                    Card {
                        visible: root.page === 3
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.margins: 12
                            spacing: 14
                            RoundedImage {
                                Layout.preferredWidth: 48; Layout.preferredHeight: 48
                                source: backend.userHasAvatar ? backend.userAvatar : ""
                                radius: 24
                                fallbackSymbol: "person"
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                StyledText {
                                    Layout.fillWidth: true
                                    text: backend.loggedIn ? backend.userName : "Вы не вошли в аккаунт"
                                    elide: Text.ElideRight
                                    font.weight: Font.DemiBold
                                }
                                Note { text: backend.loggedIn ? "Яндекс Музыка" : "Загрузки доступны без входа." }
                            }
                        }
                        ActionRow {
                            text: backend.loggedIn ? "Выйти из аккаунта" : "Перейти ко входу"
                            description: backend.loggedIn ? "Загруженные файлы останутся на устройстве." : "Вход по коду устройства или OAuth-токену."
                            onClicked: {
                                if (backend.loggedIn) logoutConfirmation.open();
                                else { backend.loadHome(); root.close(); }
                            }
                        }
                    }
                    Note {
                        visible: root.errorMessage.length > 0
                        text: root.errorMessage
                        color: Appearance.colors.error
                    }
                    Note { text: "Настройки сохраняются автоматически." }
                }
            }
            IconButton {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 12
                symbol: "close"
                tooltip: "Закрыть настройки"
                onClicked: root.close()
            }
        }
    }

    Dialog {
        id: logoutConfirmation
        parent: Overlay.overlay
        anchors.centerIn: parent
        title: "Выйти из аккаунта?"
        modal: true
        standardButtons: Dialog.Yes | Dialog.Cancel
        Label { text: "Загруженная музыка останется на устройстве." }
        onAccepted: { backend.logout(); root.close(); }
    }
    Connections {
        target: appSettings
        function onSaveFailed() { root.errorMessage = "Не удалось сохранить настройки. Проверьте свободное место и права доступа." }
    }
}
