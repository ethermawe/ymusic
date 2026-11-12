import QtQuick
import QtQuick.Layouts
import ymusic.ui

Item {
    id: root

    property int activeIndex: backend.page // 0: Home, 1: Likes, 2: Wave, 3: Playlists, 4: Albums, 5: Artists, 6: Search

    implicitWidth: 210

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 16

        // User Profile Header
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            radius: Appearance.rounding.normal
            color: Appearance.colors.surfaceContainerLow

            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 10

                // Avatar
                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    radius: width / 2
                    color: Appearance.colors.surfaceContainerHighest
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: backend.userHasAvatar ? backend.userAvatar : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
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
                Text {
                    Layout.fillWidth: true
                    text: backend.loggedIn ? backend.userName : "Гость"
                    color: Appearance.colors.onSurface
                    font.pixelSize: Appearance.fontSize.small
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                // Logout button
                IconButton {
                    symbol: "logout"
                    size: 30
                    iconSize: 16
                    iconColor: Appearance.colors.onSurfaceVariant
                    visible: backend.loggedIn
                    onClicked: backend.logout()
                }
            }
        }

        // Search Input
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
                        text: "Поиск музыки..."
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

        // Navigation Items List
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Moving active capsule indicator
            Rectangle {
                id: pillIndicator
                width: parent.width
                height: 42
                radius: Appearance.rounding.full
                color: Qt.rgba(Appearance.colors.primary.r,
                               Appearance.colors.primary.g,
                               Appearance.colors.primary.b, 0.16)
                border.width: 1
                border.color: Qt.rgba(Appearance.colors.primary.r,
                                      Appearance.colors.primary.g,
                                      Appearance.colors.primary.b, 0.3)

                visible: root.activeIndex >= 0 && root.activeIndex < navModel.count
                y: visible ? (root.activeIndex * 48) : 0

                Behavior on y {
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.4
                    }
                }
            }

            Column {
                anchors.fill: parent
                spacing: 6

                Repeater {
                    id: navRepeater
                    model: ListModel {
                        id: navModel
                        ListElement { title: "Главная"; icon: "home"; pageIndex: 0 }
                        ListElement { title: "Моя волна"; icon: "auto_awesome"; pageIndex: 1 }
                        ListElement { title: "Любимые"; icon: "favorite"; pageIndex: 2 }
                        ListElement { title: "Плейлисты"; icon: "library_music"; pageIndex: 3 }
                        ListElement { title: "Альбомы"; icon: "album"; pageIndex: 4 }
                        ListElement { title: "Артисты"; icon: "person"; pageIndex: 5 }
                    }

                    delegate: Item {
                        width: parent.width
                        height: 42

                        readonly property bool isSelected: root.activeIndex === model.pageIndex
                        readonly property bool isHovered: itemMouse.containsMouse

                        scale: isHovered && !isSelected ? 1.02 : 1.0
                        Behavior on scale {
                            NumberAnimation { duration: 150; easing.type: Easing.OutBack }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 12

                            MaterialSymbol {
                                text: model.icon
                                iconSize: 20
                                color: isSelected ? Appearance.colors.primary : (isHovered ? Appearance.colors.onSurface : Appearance.colors.onSurfaceVariant)
                            }

                            Text {
                                text: model.title
                                color: isSelected ? Appearance.colors.primary : (isHovered ? Appearance.colors.onSurface : Appearance.colors.onSurfaceVariant)
                                font.pixelSize: Appearance.fontSize.small
                                font.weight: isSelected ? Font.DemiBold : Font.Normal
                                Layout.fillWidth: true
                            }
                        }

                        MouseArea {
                            id: itemMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                switch (model.pageIndex) {
                                case 0: backend.loadHome(); break;
                                case 1: backend.startWave(); break;
                                case 2: backend.loadLikes(); break;
                                case 3: backend.loadPlaylists(); break;
                                case 4: backend.loadAlbums(); break;
                                case 5: backend.loadArtists(); break;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
