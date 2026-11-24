pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ymusic.ui

Item {
    id: root

    property var modApi: null
    property var slotContext: ({})

    readonly property int activePage: UiState.activeModPageId.length > 0 ? -1 : backend.page
    readonly property bool showLabels: modApi ? Boolean(modApi.storageGet("showLabels", false)) : false
    readonly property bool tight: width < (showLabels ? 620 : 420)

    SoftShadow {
        anchors.fill: pill
        radius: pill.radius
        blur: 14
        offset: Qt.vector2d(0, 4)
        color: Qt.rgba(0, 0, 0, Appearance.colors.dark ? 0.28 : 0.12)
    }

    Rectangle {
        id: pill
        anchors.centerIn: parent
        width: Math.min(root.width, pillRow.implicitWidth + 14)
        height: 44
        radius: height / 2
        color: Appearance.colors.surfaceContainerHigh
        border.width: 1
        border.color: Appearance.colors.layer0Border
        clip: true

        component NavPillButton: RippleButton {
            id: navBtn
            property string symbol: ""
            property string label: ""
            property bool active: false
            property bool showText: root.showLabels && !root.tight

            height: 34
            implicitWidth: showText && label.length > 0 ? (btnRow.implicitWidth + 20) : 36
            padding: 0
            buttonRadius: height / 2
            colBackground: active ? Appearance.colors.primaryContainer : "transparent"
            colBackgroundHover: active ? Appearance.colors.primaryContainerHover : Appearance.colors.layer2Hover
            tooltip: label

            contentItem: Row {
                id: btnRow
                anchors.centerIn: parent
                spacing: 6

                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: navBtn.symbol
                    iconSize: 19
                    fill: navBtn.active ? 1 : 0
                    color: navBtn.active ? Appearance.colors.onPrimaryContainer : Appearance.colors.onSurfaceVariant
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: navBtn.showText && navBtn.label.length > 0
                    text: navBtn.label
                    font.pixelSize: Appearance.fontSize.smaller
                    font.weight: navBtn.active ? Font.DemiBold : Font.Normal
                    color: navBtn.active ? Appearance.colors.onPrimaryContainer : Appearance.colors.onSurface
                }
            }
        }

        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 2

            // User avatar pill
            RippleButton {
                width: 34
                height: 34
                padding: 3
                buttonRadius: width / 2
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.layer2Hover
                tooltip: backend.loggedIn ? (backend.userName || "Профиль") : "Войти / Настройки"
                onClicked: UiState.settingsRequested()

                contentItem: ArtworkImage {
                    anchors.fill: parent
                    circular: true
                    squiggly: false
                    source: backend.userHasAvatar ? backend.userAvatar : ""
                    placeholderSymbol: "person"
                    borderWidth: 1
                    borderColor: Appearance.colors.layer0Border
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 18
                radius: 0.5
                color: Appearance.colors.outlineVariant
                opacity: 0.6
            }

            NavPillButton {
                symbol: "waves"
                label: "Волна"
                active: root.activePage === 1
                onClicked: { UiState.closeModPage(); backend.startWave(); }
            }

            NavPillButton {
                symbol: "home"
                label: "Главная"
                active: root.activePage === 0
                onClicked: { UiState.closeModPage(); backend.loadHome(); }
            }

            NavPillButton {
                symbol: "favorite"
                label: "Мне нравится"
                active: root.activePage === 2
                onClicked: { UiState.closeModPage(); backend.loadLikes(); }
            }

            NavPillButton {
                symbol: "download_done"
                label: "Загружено"
                active: root.activePage === 7
                onClicked: { UiState.closeModPage(); backend.loadDownloads(); }
            }

            NavPillButton {
                id: playlistsBtn
                symbol: "library_music"
                label: "Плейлисты"
                active: root.activePage === 3 || root.activePage === 6
                onClicked: { UiState.closeModPage(); backend.loadPlaylists(); }
                onSecondaryClicked: pinnedMenu.popup(playlistsBtn, 0, playlistsBtn.height + 6)
            }

            NavPillButton {
                symbol: "album"
                label: "Альбомы"
                active: root.activePage === 4
                onClicked: { UiState.closeModPage(); backend.loadAlbums(); }
            }

            NavPillButton {
                symbol: "group"
                label: "Артисты"
                active: root.activePage === 5
                onClicked: { UiState.closeModPage(); backend.loadArtists(); }
            }

            // Mod pages from other installed mods
            Repeater {
                model: ModManager.reloadRevision >= 0 ? ModManager.slotEntries("sidebar.page") : []
                delegate: NavPillButton {
                    required property var modelData
                    symbol: modelData.symbol || "extension"
                    label: modelData.title || modelData.modName || ""
                    active: UiState.activeModPageId === modelData.modId
                    onClicked: UiState.openModPage(modelData.modId)
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 18
                radius: 0.5
                color: Appearance.colors.outlineVariant
                opacity: 0.6
            }

            NavPillButton {
                symbol: "settings"
                label: "Настройки"
                showText: false
                active: false
                onClicked: UiState.settingsRequested()
            }
        }
    }

    StyledMenu {
        id: pinnedMenu

        StyledMenuItem {
            text: "Создать плейлист…"
            symbol: "playlist_add"
            onTriggered: UiState.createPlaylistRequested()
        }

        StyledMenuSeparator {
            visible: backend.pinnedPlaylists.length > 0
            height: visible ? implicitHeight : 0
        }

        property list<QtObject> _pinnedHelper: [
            Instantiator {
                model: backend.pinnedPlaylists
                delegate: StyledMenuItem {
                    required property var modelData
                    text: modelData.title || "Плейлист"
                    symbol: "library_music"
                    onTriggered: {
                        UiState.closeModPage();
                        backend.feature({
                            action: "open_playlist",
                            uid: modelData.uid,
                            kind: modelData.kind,
                            title: modelData.title || "Плейлист"
                        });
                    }
                }
                onObjectAdded: (index, object) => pinnedMenu.insertItem(pinnedMenu.count, object)
                onObjectRemoved: (index, object) => pinnedMenu.removeItem(object)
            }
        ]
    }
}
