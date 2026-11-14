import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ymusic.ui

Dialog {
    id: root
    property string trackId: ""
    property string trackTitle: ""
    property var playlists: []
    property bool loading: false
    property bool submitting: false
    property string errorMessage: ""
    property string selectedKind: ""
    property string selectedTitle: ""
    readonly property var filtered: {
        const query = search.text.trim().toLocaleLowerCase();
        return playlists.filter(p => p.title.toLocaleLowerCase().indexOf(query) >= 0);
    }

    title: "Добавить в плейлист"
    modal: true
    focus: true
    anchors.centerIn: parent
    width: Math.min(500, parent ? parent.width - 32 : 500)
    height: Math.min(600, parent ? parent.height - 32 : 600)
    padding: 20
    spacing: 16
    closePolicy: submitting ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside

    function choose(id, title) {
        trackId = id;
        trackTitle = title;
        playlists = [];
        selectedKind = "";
        selectedTitle = "";
        search.clear();
        open();
        reload();
    }
    function reload() {
        loading = true;
        errorMessage = "";
        backend.loadPlaylistChoices(trackId);
    }

    component Action: Button {
        id: control
        property bool primary: false
        implicitHeight: 42
        horizontalPadding: 18
        opacity: enabled ? 1 : 0.45
        contentItem: Text {
            text: control.text
            font.family: Appearance.fontFamily
            font.pixelSize: Appearance.fontSize.small
            font.weight: Font.Medium
            color: control.primary ? Appearance.colors.onPrimary : Appearance.colors.onSurface
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            radius: Appearance.rounding.full
            color: control.primary
                   ? (control.hovered ? Appearance.colors.primaryHover : Appearance.colors.primary)
                   : (control.hovered ? Appearance.colors.surfaceContainerHighest : Appearance.colors.surfaceContainerLow)
        }
    }

    background: Rectangle {
        radius: Appearance.rounding.veryLarge
        color: Appearance.colors.surfaceContainer
        border.width: 1
        border.color: Appearance.colors.outlineVariant
    }
    header: RowLayout {
        spacing: 12
        MaterialSymbol {
            Layout.leftMargin: 20
            Layout.topMargin: 20
            text: "library_music"
            iconSize: 24
            color: Appearance.colors.primary
        }
        TitleText {
            Layout.topMargin: 20
            Layout.fillWidth: true
            text: root.title
            font.pixelSize: Appearance.fontSize.title
            elide: Text.ElideRight
        }
        IconButton {
            Layout.topMargin: 16
            Layout.rightMargin: 12
            symbol: "close"
            enabled: !root.submitting
            onClicked: root.close()
        }
    }
    contentItem: ColumnLayout {
        spacing: 14
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: trackInfo.implicitHeight + 24
            radius: Appearance.rounding.normal
            color: Appearance.colors.surfaceContainerLow
            ColumnLayout {
                id: trackInfo
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 14
                spacing: 4
                StyledText {
                    text: "ВЫБРАННЫЙ ТРЕК"
                    font.pixelSize: Appearance.fontSize.smallest
                    font.weight: Font.Bold
                    color: Appearance.colors.primary
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.trackTitle
                    textFormat: Text.PlainText
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
            }
        }

        TextField {
            id: search
            Layout.fillWidth: true
            implicitHeight: 44
            placeholderText: "Найти свой плейлист…"
            enabled: !root.loading && !root.submitting
            selectByMouse: true
            leftPadding: 14
            rightPadding: 14
            color: Appearance.colors.onSurface
            placeholderTextColor: Appearance.colors.onSurfaceVariant
            background: Rectangle {
                radius: Appearance.rounding.small
                color: Appearance.colors.surfaceContainerLow
                border.width: 1
                border.color: search.activeFocus ? Appearance.colors.primary : Appearance.colors.outlineVariant
            }
        }

        RowLayout {
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                text: root.loading ? "Загружаем плейлисты…" : "Ваши плейлисты · " + root.playlists.length
                font.pixelSize: Appearance.fontSize.smaller
                color: Appearance.colors.onSurfaceVariant
            }
            IconButton {
                symbol: "library_music"
                tooltip: "Создать плейлист"
                size: 30
                enabled: !root.loading && !root.submitting
                onClicked: newPlaylist.open()
            }
            IconButton {
                symbol: "repeat"
                size: 30
                tooltip: "Обновить список"
                enabled: !root.loading && !root.submitting
                onClicked: root.reload()
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 80
            ListView {
                id: list
                anchors.fill: parent
                clip: true
                maximumFlickVelocity: 5000
                flickDeceleration: 2400
                model: root.filtered
                FastWheel {}
                spacing: 6
                visible: !root.loading
                delegate: ItemDelegate {
                    id: entry
                    required property var modelData
                    readonly property bool chosen: root.selectedKind === modelData.kind
                    width: list.width
                    height: 68
                    enabled: !root.submitting && backend.loggedIn
                    padding: 10
                    contentItem: RowLayout {
                        spacing: 12
                        RoundedImage {
                            Layout.preferredWidth: 46
                            Layout.preferredHeight: 46
                            radius: 10
                            source: entry.modelData.cover_url || ""
                            fallbackSymbol: "library_music"
                            sourceSize: Qt.size(92, 92)
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            StyledText {
                                Layout.fillWidth: true
                                text: entry.modelData.title
                                textFormat: Text.PlainText
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: entry.modelData.subtitle || "Ваш плейлист"
                                textFormat: Text.PlainText
                                font.pixelSize: Appearance.fontSize.smaller
                                color: Appearance.colors.onSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }
                        Rectangle {
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            radius: 10
                            color: entry.chosen ? Appearance.colors.primary : "transparent"
                            border.width: entry.chosen ? 0 : 2
                            border.color: Appearance.colors.outline
                            Rectangle {
                                anchors.centerIn: parent
                                width: 8; height: 8; radius: 4
                                color: Appearance.colors.onPrimary
                                visible: entry.chosen
                            }
                        }
                    }
                    background: Rectangle {
                        radius: Appearance.rounding.normal
                        color: entry.chosen ? Appearance.colors.primaryContainer
                            : (entry.hovered ? Appearance.colors.surfaceContainerHighest : Appearance.colors.surfaceContainerLow)
                        border.width: entry.chosen ? 1 : 0
                        border.color: Appearance.colors.primary
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    onClicked: {
                        root.selectedKind = modelData.kind;
                        root.selectedTitle = modelData.title;
                    }
                }
                ScrollBar.vertical: ScrollBar {}
            }
            BusyIndicator {
                anchors.centerIn: parent
                running: root.loading
                visible: root.loading
                palette.dark: Appearance.colors.primary
            }
            StyledText {
                anchors.centerIn: parent
                width: parent.width - 24
                visible: !root.loading && root.filtered.length === 0
                text: root.playlists.length > 0 ? "Плейлисты не найдены.\nПопробуйте другой запрос."
                     : (root.errorMessage.length > 0 ? "Не удалось загрузить список.\nНажмите обновление, чтобы повторить." : "Пока нет собственных плейлистов.\nСоздайте плейлист в Яндекс Музыке.")
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: Appearance.colors.onSurfaceVariant
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.errorMessage.length > 0
            text: root.errorMessage
            textFormat: Text.PlainText
            color: Appearance.colors.error
            wrapMode: Text.WordWrap
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.selectedKind.length > 0 && !root.loading
            text: "В плейлист: " + root.selectedTitle
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Appearance.colors.onSurfaceVariant
            font.pixelSize: Appearance.fontSize.smaller
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Action {
                text: "Отмена"
                enabled: !root.submitting
                onClicked: root.close()
            }
            Action {
                Layout.fillWidth: true
                text: root.submitting ? "Добавляем…" : "Добавить"
                primary: true
                enabled: !root.loading && !root.submitting && root.selectedKind.length > 0 && backend.loggedIn
                onClicked: {
                    root.submitting = true;
                    root.errorMessage = "";
                    backend.addToPlaylist(root.trackId, root.selectedKind);
                }
            }
        }
    }

    Connections {
        target: backend
        function onPlaylistPickerResult(id, stage, choices, message) {
            if (id !== root.trackId || !root.visible) return;
            root.loading = false;
            root.submitting = false;
            if (stage === "done") { root.close(); return; }
            if (stage === "loaded") {
                root.playlists = choices;
                if (!choices.some(p => p.kind === root.selectedKind)) {
                    root.selectedKind = "";
                    root.selectedTitle = "";
                }
            } else root.errorMessage = message;
        }
        function onAuthChanged() {
            if (!backend.loggedIn) { root.submitting = false; root.loading = false; root.close(); }
        }
        function onFeatureResult(result) {
            if (result.type === "create_playlist" && result.ok && root.visible) root.reload();
        }
    }
    CreatePlaylistDialog { id: newPlaylist; parent: Overlay.overlay }
}
