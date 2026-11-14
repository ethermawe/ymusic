pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ymusic.ui

Item {
    id: root

    readonly property int activePage: backend.page
    property bool compact: false
    property bool searchExpanded: false
    readonly property bool isCompact: compact && !searchExpanded
    signal settingsRequested()

    implicitWidth: isCompact ? 72 : 220

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

        // Quick Search Input Field
        Rectangle {
            id: searchBox
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            radius: Appearance.rounding.full
            color: searchInput.activeFocus ? Qt.alpha(Appearance.colors.surfaceContainerHighest, 0.5)
                                           : Appearance.colors.surfaceContainerHigh
            border.width: searchInput.activeFocus ? 2 : 0
            border.color: Appearance.colors.primary

            Behavior on color { ElementMoveFastColor {} }

            MouseArea {
                anchors.fill: parent
                enabled: root.isCompact
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.searchExpanded = true
                    searchInput.forceActiveFocus()
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: root.isCompact ? 0 : 12
                anchors.rightMargin: root.isCompact ? 0 : 12
                spacing: root.isCompact ? 0 : 8

                MaterialSymbol {
                    Layout.alignment: root.isCompact ? Qt.AlignHCenter | Qt.AlignVCenter : Qt.AlignVCenter
                    text: "search"
                    iconSize: 18
                    color: searchInput.activeFocus ? Appearance.colors.primary : Appearance.colors.onSurfaceVariant
                }

                TextInput {
                    id: searchInput
                    Layout.fillWidth: true
                    visible: !root.isCompact
                    color: Appearance.colors.onSurface
                    selectionColor: Appearance.colors.primary
                    selectedTextColor: Appearance.colors.onPrimary
                    font.family: Appearance.fontFamily
                    font.pixelSize: Appearance.fontSize.smaller
                    selectByMouse: true
                    clip: true

                    onActiveFocusChanged: {
                        if (!activeFocus) root.searchExpanded = false
                    }

                    StyledText {
                        anchors.fill: parent
                        text: qsTr("Поиск музыки…")
                        color: Appearance.colors.onSurfaceVariant
                        font.pixelSize: Appearance.fontSize.smaller
                        visible: !searchInput.text && !searchInput.activeFocus
                    }

                    onAccepted: {
                        if (text.trim().length > 0) {
                            backend.search(text.trim())
                            root.searchExpanded = false
                        }
                    }
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

            Column {
                id: navColumn
                width: parent.width
                spacing: 3

                NavigationItem {
                    width: parent.width
                    compact: root.isCompact
                    text: qsTr("Главная")
                    iconShape: "cookie9"
                    symbol: "home"
                    selected: root.activePage === 0
                    onClicked: backend.loadHome()
                }

                NavigationItem {
                    width: parent.width
                    compact: root.isCompact
                    text: qsTr("Моя волна")
                    iconShape: "softBurst"
                    symbol: "waves"
                    selected: root.activePage === 1
                    onClicked: backend.startWave()
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

                NavigationItem {
                    width: parent.width
                    compact: root.isCompact
                    text: qsTr("Плейлисты")
                    iconShape: "bun"
                    symbol: "library_music"
                    selected: root.activePage === 3
                    onClicked: backend.loadPlaylists()
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
