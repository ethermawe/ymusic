import QtQuick
import QtQuick.Layouts
import ymusic.ui

Item {
    id: root

    readonly property int activePage: backend.page

    implicitWidth: 220

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        // User Profile Header
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 50
            radius: Appearance.rounding.normal
            color: Appearance.colors.surfaceContainerLow
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.04)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 8
                spacing: 10

                // Avatar
                Rectangle {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    radius: width / 2
                    color: Appearance.colors.surfaceContainerHighest
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: backend.userHasAvatar ? backend.userAvatar : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        sourceSize.width: 68
                        sourceSize.height: 68
                        visible: backend.userHasAvatar
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "person"
                        iconSize: 20
                        color: Appearance.colors.onSurfaceVariant
                        visible: !backend.userHasAvatar
                    }
                }

                // Name
                StyledText {
                    Layout.fillWidth: true
                    text: backend.loggedIn ? backend.userName : "Гость"
                    font.pixelSize: Appearance.fontSize.small
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                // Logout button
                IconButton {
                    symbol: "logout"
                    size: 28
                    iconSize: 16
                    iconColor: Appearance.colors.onSurfaceVariant
                    visible: backend.loggedIn
                    onClicked: backend.logout()
                }
            }
        }

        // Search Input Field
        Rectangle {
            id: searchBox
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            radius: Appearance.rounding.full
            color: Appearance.colors.surfaceContainerLow
            border.width: 1
            border.color: searchInput.activeFocus ? Appearance.colors.primary : Qt.rgba(1, 1, 1, 0.08)

            Behavior on border.color { ColorAnimation { duration: 140 } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                MaterialSymbol {
                    text: "search"
                    iconSize: 18
                    color: searchInput.activeFocus ? Appearance.colors.primary : Appearance.colors.onSurfaceVariant
                }

                TextInput {
                    id: searchInput
                    Layout.fillWidth: true
                    color: Appearance.colors.onSurface
                    font.pixelSize: Appearance.fontSize.smaller
                    selectByMouse: true
                    clip: true

                    Text {
                        anchors.fill: parent
                        text: "Поиск музыки…"
                        color: Appearance.colors.onSurfaceVariant
                        font.pixelSize: Appearance.fontSize.smaller
                        visible: !searchInput.text && !searchInput.activeFocus
                    }

                    onAccepted: {
                        if (text.trim().length > 0) {
                            backend.search(text.trim());
                        }
                    }
                }
            }
        }

        // Navigation Items
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: navColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: navColumn
                width: parent.width
                spacing: 4

                NavigationItem {
                    width: parent.width
                    text: "Главная"
                    symbol: "home"
                    selected: root.activePage === 0
                    onClicked: backend.loadHome()
                }

                NavigationItem {
                    width: parent.width
                    text: "Моя волна"
                    symbol: "auto_awesome"
                    selected: root.activePage === 1
                    onClicked: backend.startWave()
                }

                SectionLabel {
                    width: parent.width
                    text: "Медиатека"
                }

                NavigationItem {
                    width: parent.width
                    text: "Мне нравится"
                    symbol: "favorite"
                    selected: root.activePage === 2
                    onClicked: backend.loadLikes()
                }

                SectionLabel {
                    width: parent.width
                    text: "Коллекции"
                }

                NavigationItem {
                    width: parent.width
                    text: "Плейлисты"
                    symbol: "library_music"
                    selected: root.activePage === 3
                    onClicked: backend.loadPlaylists()
                }

                NavigationItem {
                    width: parent.width
                    text: "Альбомы"
                    symbol: "album"
                    selected: root.activePage === 4
                    onClicked: backend.loadAlbums()
                }

                NavigationItem {
                    width: parent.width
                    text: "Артисты"
                    symbol: "person"
                    selected: root.activePage === 5
                    onClicked: backend.loadArtists()
                }
            }
        }
    }
}
