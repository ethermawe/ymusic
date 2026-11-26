pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ymusic.sdk 1.0

Item {
    id: root

    property var modApi: null
    property var slotContext: ({})

    readonly property int activePage: modApi ? modApi.currentPage : 0
    property bool showLabels: modApi ? Boolean(modApi.storageGet("showLabels", false)) : false
    readonly property bool tight: width < (showLabels ? 640 : 440)
    readonly property var pinnedList: modApi ? modApi.pinnedPlaylists : []

    Connections {
        target: root.modApi
        function onStorageChanged(key) {
            if (key === "showLabels" && root.modApi) {
                root.showLabels = Boolean(root.modApi.storageGet("showLabels", false));
            }
        }
    }

    Rectangle {
        id: pill
        anchors.centerIn: parent
        width: Math.min(root.width, pillRow.implicitWidth + 14)
        height: 44
        radius: height / 2
        color: Theme.colors.surfaceContainerHigh
        border.width: 1
        border.color: Theme.colors.layer0Border
        clip: true

        Behavior on width {
            enabled: !Theme.performanceMode && !Theme.reduceMotion
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        component PillDivider: Item {
            width: 10
            height: 20
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.centerIn: parent
                width: 1
                height: 18
                radius: 0.5
                color: Theme.colors.outlineVariant
                opacity: 0.55
            }
        }

        component NavPillButton: Item {
            id: navBtn
            property string symbol: ""
            property string label: ""
            property bool active: false
            property bool showText: root.showLabels && !root.tight
            signal clicked()
            signal secondaryClicked()

            anchors.verticalCenter: parent.verticalCenter
            height: 34
            implicitWidth: showText && label.length > 0 ? (btnRow.implicitWidth + 22) : 34
            width: implicitWidth

            Behavior on implicitWidth {
                enabled: !Theme.performanceMode && !Theme.reduceMotion
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: navBtn.active
                    ? (btnMouse.containsMouse ? Theme.colors.primaryContainerHover : Theme.colors.primaryContainer)
                    : (btnMouse.containsMouse ? Theme.colors.layer2Hover : "transparent")
            }

            Row {
                id: btnRow
                anchors.centerIn: parent
                spacing: 6

                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    symbol: navBtn.symbol
                    iconSize: 19
                    filled: navBtn.active
                    color: navBtn.active ? Theme.colors.onPrimaryContainer : Theme.colors.onSurfaceVariant
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: navBtn.showText && navBtn.label.length > 0
                    text: navBtn.label
                    font.pixelSize: Theme.fontSize.smaller
                    font.weight: navBtn.active ? Font.DemiBold : Font.Normal
                    color: navBtn.active ? Theme.colors.onPrimaryContainer : Theme.colors.onSurface
                }
            }

            MouseArea {
                id: btnMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton) navBtn.secondaryClicked();
                    else navBtn.clicked();
                }
            }

            ToolTip.visible: btnMouse.containsMouse && navBtn.label.length > 0
            ToolTip.delay: 450
            ToolTip.text: navBtn.label
        }

        Row {
            id: pillRow
            anchors.centerIn: parent
            height: parent.height
            spacing: 4

            NavPillButton {
                symbol: "person"
                label: (root.modApi && root.modApi.loggedIn) ? (root.modApi.userName || "Профиль") : "Войти / Настройки"
                showText: false
                onClicked: if (root.modApi) root.modApi.openSettings()
            }

            PillDivider {}

            NavPillButton {
                symbol: "waves"
                label: "Волна"
                active: root.activePage === 1
                onClicked: if (root.modApi) root.modApi.openWave()
            }

            NavPillButton {
                symbol: "home"
                label: "Главная"
                active: root.activePage === 0
                onClicked: if (root.modApi) root.modApi.openHome()
            }

            NavPillButton {
                symbol: "favorite"
                label: "Мне нравится"
                active: root.activePage === 2
                onClicked: if (root.modApi) root.modApi.openLikes()
            }

            NavPillButton {
                symbol: "download_done"
                label: "Загружено"
                active: root.activePage === 7
                onClicked: if (root.modApi) root.modApi.openDownloads()
            }

            NavPillButton {
                id: playlistsBtn
                symbol: "library_music"
                label: "Плейлисты"
                active: root.activePage === 3 || root.activePage === 6
                onClicked: if (root.modApi) root.modApi.openPlaylists()
                onSecondaryClicked: pinnedMenu.popup(playlistsBtn, 0, playlistsBtn.height + 6)
            }

            NavPillButton {
                symbol: "album"
                label: "Альбомы"
                active: root.activePage === 4
                onClicked: if (root.modApi) root.modApi.openAlbums()
            }

            NavPillButton {
                symbol: "group"
                label: "Артисты"
                active: root.activePage === 5
                onClicked: if (root.modApi) root.modApi.openArtists()
            }

            PillDivider {}

            NavPillButton {
                symbol: "settings"
                label: "Настройки"
                showText: false
                active: false
                onClicked: if (root.modApi) root.modApi.openSettings()
            }
        }
    }

    StyledMenu {
        id: pinnedMenu

        StyledMenuItem {
            text: "Создать плейлист…"
            symbol: "playlist_add"
            onTriggered: if (root.modApi) root.modApi.openCreatePlaylist()
        }

        StyledMenuSeparator {
            visible: root.pinnedList.length > 0
            height: visible ? implicitHeight : 0
        }

        property list<QtObject> _pinnedHelper: [
            Instantiator {
                model: root.pinnedList
                delegate: StyledMenuItem {
                    required property var modelData
                    text: modelData.title || "Плейлист"
                    symbol: "library_music"
                    onTriggered: {
                        if (root.modApi) {
                            root.modApi.openPlaylist(
                                String(modelData.uid ?? ""),
                                String(modelData.kind ?? ""),
                                String(modelData.title ?? "Плейлист")
                            );
                        }
                    }
                }
                onObjectAdded: (index, object) => pinnedMenu.insertItem(pinnedMenu.count, object)
                onObjectRemoved: (index, object) => pinnedMenu.removeItem(object)
            }
        ]
    }
}
