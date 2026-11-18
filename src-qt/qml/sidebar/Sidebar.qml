pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ymusic.ui

Item {
    id: root

    readonly property int activePage: backend.page
    property bool compact: false
    readonly property bool isCompact: compact
    signal settingsRequested()

    implicitWidth: isCompact ? 72 : 220

    Behavior on implicitWidth {
        enabled: !Appearance.performanceMode
        ElementMove {}
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.isCompact ? 10 : 12
        spacing: 10

        // User Profile Header
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 50
            radius: Appearance.rounding.normal
            color: Appearance.colors.surfaceContainerLow
            border.width: 1
            border.color: Appearance.colors.layer0Border

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: root.isCompact ? 0 : 10
                anchors.rightMargin: root.isCompact ? 0 : 8
                spacing: root.isCompact ? 0 : 10

                ArtworkImage {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    Layout.alignment: root.isCompact ? Qt.AlignHCenter | Qt.AlignVCenter : Qt.AlignVCenter
                    circular: true
                    squiggly: false
                    source: backend.userHasAvatar ? backend.userAvatar : ""
                    placeholderSymbol: "person"
                    borderWidth: 1
                    borderColor: Appearance.colors.layer0Border
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: !root.isCompact
                    text: backend.loggedIn ? backend.userName : qsTr("Гость")
                    font.pixelSize: Appearance.fontSize.small
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                IconButton {
                    symbol: "logout"
                    size: 28
                    iconSize: 16
                    tooltip: qsTr("Выйти из аккаунта")
                    visible: !root.isCompact && backend.loggedIn
                    onClicked: backend.logout()
                }
            }
        }

        Flickable {
            id: navigationFlickable
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: navColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            onContentHeightChanged: {
                const maxY = Math.max(0, contentHeight - height);
                if (contentY > maxY) contentY = maxY;
            }

            FastWheel { target: navigationFlickable }

            Column {
                id: navColumn
                width: parent.width
                spacing: 3

                NavigationItem {
                    width: parent.width
                    compact: root.isCompact
                    text: qsTr("Моя волна")
                    iconShape: "softBurst"
                    symbol: "waves"
                    selected: root.activePage === 1
                    onClicked: backend.startWave()
                }

                NavigationItem {
                    width: parent.width
                    compact: root.isCompact
                    text: qsTr("Главная")
                    iconShape: "cookie9"
                    symbol: "home"
                    selected: root.activePage === 0
                    onClicked: backend.loadHome()
                }

                SectionLabel {
                    width: parent.width
                    compact: root.isCompact
                    text: qsTr("Медиатека")
                }

                NavigationItem {
                    width: parent.width
                    compact: root.isCompact
                    text: qsTr("Мне нравится")
                    iconShape: "heart"
                    keepsShape: true
                    symbol: "favorite"
                    selected: root.activePage === 2
                    onClicked: backend.loadLikes()
                }

                NavigationItem {
                    width: parent.width
                    compact: root.isCompact
                    text: qsTr("Загружено")
                    iconShape: "clamShell"
                    symbol: "download_done"
                    selected: root.activePage === 7
                    onClicked: backend.loadDownloads()
                }

                SectionLabel {
                    width: parent.width
                    compact: root.isCompact
                    text: qsTr("Коллекции")
                    trailing: IconButton {
                        symbol: "add"
                        size: 30
                        iconSize: 18
                        iconColor: Appearance.colors.primary
                        tooltip: qsTr("Создать плейлист")
                        onClicked: UiState.createPlaylistRequested()
                    }
                }

                Column {
                    width: parent.width
                    spacing: 0

                    NavigationItem {
                        width: parent.width
                        compact: root.isCompact
                        text: qsTr("Плейлисты")
                        iconShape: "bun"
                        symbol: "library_music"
                        selected: root.activePage === 3
                        trailing: IconButton {
                            visible: !root.isCompact && backend.pinnedPlaylists.length > 0
                            symbol: "expand_more"
                            iconRotation: appSettings.pinnedPlaylistsExpanded ? 0 : -90
                            size: 26
                            iconSize: 18
                            tooltip: appSettings.pinnedPlaylistsExpanded ? qsTr("Свернуть закреплённые") : qsTr("Развернуть закреплённые")
                            onClicked: appSettings.pinnedPlaylistsExpanded = !appSettings.pinnedPlaylistsExpanded
                        }
                        onClicked: backend.loadPlaylists()
                    }

                    Item {
                        id: pinnedSection
                        readonly property bool expanded: appSettings.pinnedPlaylistsExpanded && backend.pinnedPlaylists.length > 0
                        width: parent.width
                        height: expanded ? pinnedColumn.implicitHeight + 3 : 0
                        visible: height > 0
                        clip: true
                        opacity: expanded ? 1 : 0
                        enabled: expanded

                        Behavior on height {
                            enabled: !Appearance.performanceMode
                            ElementMove {}
                        }
                        Behavior on opacity {
                            enabled: !Appearance.performanceMode
                            NumberAnimation { duration: Appearance.duration(180); easing.type: Easing.OutCubic }
                        }

                        Column {
                            id: pinnedColumn
                            width: parent.width
                            y: pinnedSection.expanded ? 3 : -Math.min(16, implicitHeight * 0.25)
                            spacing: 3

                            Behavior on y {
                                enabled: !Appearance.performanceMode
                                ElementMove {}
                            }

                            Repeater {
                                model: backend.pinnedPlaylists

                                NavigationItem {
                                    id: pinnedItem
                                    required property var modelData
                                    width: parent.width
                                    compact: root.isCompact
                                    indent: 10
                                    text: modelData.title ?? ""
                                    fallbackKey: modelData.key ?? text
                                    showArtwork: true
                                    artworkUrl: (modelData.has_cover ?? false) ? (modelData.cover_url ?? "") : ""
                                    symbol: "library_music"
                                    selected: root.activePage === 6 && backend.activePlaylistKey === (modelData.key ?? "")
                                    trailing: IconButton {
                                        symbol: "close"
                                        size: 24
                                        iconSize: 15
                                        opacity: pinnedItem.hovered ? 0.85 : 0
                                        visible: opacity > 0
                                        tooltip: qsTr("Открепить плейлист")
                                        onClicked: backend.feature({
                                            action: "toggle_pin_playlist",
                                            uid: pinnedItem.modelData.uid,
                                            kind: pinnedItem.modelData.kind
                                        })
                                    }
                                    onClicked: backend.feature({
                                        action: "open_playlist",
                                        uid: pinnedItem.modelData.uid,
                                        kind: pinnedItem.modelData.kind,
                                        title: pinnedItem.modelData.title ?? "Плейлист"
                                    })
                                    TapHandler {
                                        acceptedButtons: Qt.RightButton
                                        onTapped: backend.feature({
                                            action: "toggle_pin_playlist",
                                            uid: pinnedItem.modelData.uid,
                                            kind: pinnedItem.modelData.kind
                                        })
                                    }
                                }
                            }
                        }
                    }
                }

                NavigationItem {
                    width: parent.width
                    compact: root.isCompact
                    text: qsTr("Альбомы")
                    iconShape: "sunny"
                    symbol: "album"
                    selected: root.activePage === 4
                    onClicked: backend.loadAlbums()
                }

                NavigationItem {
                    width: parent.width
                    compact: root.isCompact
                    text: qsTr("Артисты")
                    iconShape: "clover4"
                    symbol: "group"
                    selected: root.activePage === 5
                    onClicked: backend.loadArtists()
                }
            }
        }

        NavigationItem {
            Layout.fillWidth: true
            compact: root.isCompact
            text: qsTr("Настройки")
            iconShape: "cookie12"
            symbol: "settings"
            onClicked: root.settingsRequested()
        }
    }
}
