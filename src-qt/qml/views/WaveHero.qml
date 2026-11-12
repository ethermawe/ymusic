import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ymusic.ui

Item {
    id: root
    property var selected: ({})
    property bool fetching: true
    property bool applying: false
    property string errorMessage: ""
    readonly property var groups: backend.waveSettings.groups || []
    readonly property bool inWave: backend.tracks.currentIndex >= 0
    readonly property string artwork: inWave && backend.hasCover ? backend.nowCover : backend.listCover
    readonly property bool compact: width < 760
    readonly property real artworkSize: compact ? 210 : Math.min(380, Math.max(250, (width - 104) * 0.31))
    readonly property bool changed: JSON.stringify(selected) !== JSON.stringify(backend.waveSettings.selected || {})
    implicitHeight: card.height + 76
    implicitWidth: 600

    function select(key, seed) {
        const next = Object.assign({}, selected);
        if (seed.length > 0) next[key] = seed;
        else delete next[key];
        selected = next;
    }
    function reload() {
        fetching = true;
        errorMessage = "";
        backend.feature({action: "wave_settings"});
    }
    Component.onCompleted: {
        selected = Object.assign({}, backend.waveSettings.selected || {});
        reload();
    }

    component Chip: Button {
        id: chip
        property bool chosen: false
        implicitHeight: 34
        implicitWidth: label.implicitWidth + 26
        leftPadding: 13
        rightPadding: 13
        hoverEnabled: true
        opacity: enabled ? 1 : 0.5
        contentItem: Text {
            id: label
            text: chip.text
            font.family: Appearance.fontFamily
            font.pixelSize: 12
            font.weight: chip.chosen ? Font.DemiBold : Font.Medium
            color: chip.chosen ? Appearance.colors.onPrimary : Appearance.colors.onSurface
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
        }
        background: Rectangle {
            radius: 11
            color: chip.chosen ? Appearance.colors.primary
                 : (chip.hovered ? Appearance.colors.surfaceContainerHighest : Appearance.colors.surfaceContainerHigh)
            border.width: chip.visualFocus ? 2 : 0
            border.color: Appearance.colors.primary
            Behavior on color { ColorAnimation { duration: Appearance.duration(150) } }
        }
    }

    Rectangle {
        id: card
        anchors.top: parent.top
        anchors.topMargin: 20
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 24
        height: content.implicitHeight + 48
        radius: 30
        color: Appearance.colors.surfaceContainerLow
        border.width: 1
        border.color: Appearance.colors.outlineVariant

        Image {
            id: backdrop
            visible: false
            source: appSettings.coversEnabled ? root.artwork : ""
            sourceSize: Qt.size(64, 64)
            smooth: true
            asynchronous: true
        }
        ShaderEffect {
            anchors.fill: parent
            property variant source: backdrop
            property size itemSize: Qt.size(width, height)
            property real radius: card.radius
            fragmentShader: "qrc:/shaders/artwork_backdrop.frag.qsb"
            visible: backdrop.status === Image.Ready
            opacity: 0.12
        }

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 24
            spacing: 24

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                MaterialSymbol { text: "my_wave"; iconSize: 24; color: Appearance.colors.primary }
                TitleText {
                    Layout.fillWidth: true
                    text: backend.listTitle || "Моя волна"
                    font.pixelSize: 26
                    elide: Text.ElideRight
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: root.compact ? 1 : 2
                columnSpacing: 24
                rowSpacing: 24

                ColumnLayout {
                    Layout.preferredWidth: root.compact ? content.width : root.artworkSize
                    Layout.maximumWidth: root.compact ? content.width : root.artworkSize
                    Layout.alignment: Qt.AlignTop
                    spacing: 14

                    Item {
                        Layout.preferredWidth: root.artworkSize
                        Layout.preferredHeight: width
                        Layout.alignment: Qt.AlignHCenter
                        RoundedImage {
                            id: cover
                            anchors.fill: parent
                            radius: 22
                            source: root.artwork
                            sourceSize: Qt.size(400, 400)
                            fallbackSymbol: "my_wave"
                            fallbackIconSize: 84
                            borderWidth: 1
                            borderColor: Appearance.colors.outlineVariant
                        }
                        Rectangle {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 12
                            width: 58; height: 58; radius: 21
                            color: Appearance.colors.surfaceContainerLowest
                            PlayHeroButton {
                                anchors.centerIn: parent
                                size: 52
                                playing: backend.playing && root.inWave
                                enabled: !root.applying && !backend.listLoading
                                onClicked: {
                                    if (root.inWave) backend.toggle();
                                    else if (backend.tracks.count > 0) backend.play(0);
                                    else backend.startWave();
                                }
                            }
                        }
                    }

                    TitleText {
                        Layout.fillWidth: true
                        text: root.inWave ? backend.nowTitle : "Ваш следующий любимый трек"
                        font.pixelSize: 22
                        maximumLineCount: 2
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        font.underline: titleHover.hovered && root.inWave && backend.nowHasAlbum
                        HoverHandler { id: titleHover; cursorShape: root.inWave && backend.nowHasAlbum ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        TapHandler { enabled: root.inWave && backend.nowHasAlbum; onTapped: backend.openNowAlbum() }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.inWave ? backend.nowArtists : "Поток, который меняется вместе с вами"
                        color: Appearance.colors.onSurfaceVariant
                        elide: Text.ElideRight
                        font.underline: artistHover.hovered && root.inWave && backend.nowHasArtist
                        HoverHandler { id: artistHover; cursorShape: root.inWave && backend.nowHasArtist ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        TapHandler { enabled: root.inWave && backend.nowHasArtist; onTapped: backend.openNowArtist() }
                    }
                    Rectangle {
                        Layout.alignment: Qt.AlignLeft
                        Layout.preferredWidth: 196
                        Layout.preferredHeight: 56
                        radius: 28
                        color: Appearance.colors.surfaceContainerHigh
                        border.width: 1
                        border.color: Appearance.colors.outlineVariant
                        RowLayout {
                        anchors.centerIn: parent
                        spacing: 8
                        IconButton {
                            symbol: "thumb_down"
                            size: 40
                            iconSize: 19
                            iconColor: Appearance.colors.onSurfaceVariant
                            tooltip: "Меньше такого"
                            enabled: root.inWave
                            onClicked: backend.dislikeNow()
                        }
                        IconButton {
                            symbol: backend.nowLiked && root.inWave ? "favorite" : "favorite_border"
                            size: 40
                            iconSize: 22
                            toggled: backend.nowLiked && root.inWave
                            tooltip: "Мне нравится"
                            enabled: root.inWave
                            onClicked: backend.toggleNowLike()
                        }
                        Rectangle {
                            Layout.preferredWidth: 1
                            Layout.preferredHeight: 22
                            Layout.leftMargin: 2
                            Layout.rightMargin: 2
                            color: Appearance.colors.outlineVariant
                        }
                        TransportButton {
                            symbol: "skip_next"
                            size: 42
                            iconSize: 26
                            iconColor: Appearance.colors.primary
                            effect: TransportButton.NudgeRight
                            tooltip: "Следующий трек"
                            enabled: root.inWave
                            onClicked: backend.next()
                        }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 18

                    RowLayout {
                        Layout.fillWidth: true
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            TitleText { text: "На вашей частоте"; font.pixelSize: 22 }
                            StyledText {
                                Layout.fillWidth: true
                                text: "Выберите, что хочется услышать сейчас"
                                color: Appearance.colors.onSurfaceVariant
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }
                        }
                        IconButton {
                            symbol: "repeat"
                            tooltip: "Обновить фильтры"
                            enabled: !root.fetching && !root.applying
                            onClicked: root.reload()
                        }
                    }

                    Repeater {
                        model: root.groups
                        delegate: ColumnLayout {
                            id: group
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 9
                            StyledText {
                                text: group.modelData.name
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                color: Appearance.colors.onSurfaceVariant
                            }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 6
                                Chip {
                                    text: "Без фильтра"
                                    chosen: !root.selected[group.modelData.key]
                                    enabled: !root.applying && !root.fetching
                                    onClicked: root.select(group.modelData.key, "")
                                }
                                Repeater {
                                    model: group.modelData.choices
                                    delegate: Chip {
                                        required property var modelData
                                        text: modelData.name
                                        chosen: root.selected[group.modelData.key] === modelData.seed
                                        enabled: !root.applying && !root.fetching
                                        onClicked: root.select(group.modelData.key, modelData.seed)
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.fetching || (!root.fetching && root.groups.length === 0)
                        text: root.fetching ? "Загружаем частоты…" : "Фильтры пока недоступны. Можно слушать обычную волну."
                        color: Appearance.colors.onSurfaceVariant
                        wrapMode: Text.WordWrap
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: root.errorMessage.length > 0
                        text: root.errorMessage
                        color: Appearance.colors.error
                        wrapMode: Text.WordWrap
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 8
                        StyledButton {
                            text: root.applying ? "Настраиваем…" : "Поймать волну"
                            highlighted: true
                            enabled: !root.applying && !root.fetching
                            onClicked: {
                                root.applying = true;
                                root.errorMessage = "";
                                backend.feature({action: "wave_apply", selected: root.selected});
                            }
                        }
                        IconButton {
                            symbol: "close"
                            tooltip: "Сбросить фильтры"
                            enabled: !root.applying && !root.fetching && Object.keys(root.selected).length > 0
                            onClicked: root.selected = ({})
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.changed ? "Есть изменения · запустим новый поток" : "Лайки и пропуски помогают волне узнать вас"
                        font.pixelSize: 11
                        color: Appearance.colors.onSurfaceVariant
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }

    StyledText {
        anchors.top: card.bottom
        anchors.topMargin: 22
        anchors.left: card.left
        text: "ДАЛЕЕ В ПОТОКЕ"
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 1.2
        color: Appearance.colors.onSurfaceVariant
    }

    Connections {
        target: backend
        function onFeatureResult(result) {
            if (result.type === "wave_settings") {
                root.fetching = false;
                root.errorMessage = "";
                root.selected = Object.assign({}, result.selected || {});
            } else if (result.type === "wave_error") {
                root.fetching = false;
                root.applying = false;
                root.errorMessage = result.message;
            } else if (result.type === "wave_applied") {
                root.applying = false;
                root.selected = Object.assign({}, result.selected || {});
            }
        }
    }
}
