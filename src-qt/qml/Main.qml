import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ymusic.ui

ApplicationWindow {
    id: window

    visible: true
    width: 1200
    height: 760
    minimumWidth: 860
    minimumHeight: 560
    title: "Yandex Music"
    color: Appearance.colors.surfaceContainerLowest

    property bool immersiveOpen: false
    readonly property bool isCardsPage: backend.page === 0 || backend.page === 3 || backend.page === 4 || backend.page === 5 || (!backend.isArtistView && backend.tracks.rowCount() === 0 && backend.cards.rowCount() > 0)

    // Root layout
    Item {
        anchors.fill: parent

        // Left Sidebar
        Sidebar {
            id: sidebar
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 210
        }

        // Center Elevated Sheet
        Rectangle {
            id: sheet
            anchors.left: sidebar.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 10
            radius: Appearance.rounding.large
            color: Appearance.colors.surfaceContainer
            clip: true
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.04)

            // Status message toast / banner
            Rectangle {
                id: statusBanner
                visible: backend.statusMessage.length > 0
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: 12
                height: 36
                width: statusText.implicitWidth + 32
                radius: Appearance.rounding.full
                color: Appearance.colors.primaryContainer
                border.width: 1
                border.color: Appearance.colors.primary
                z: 10

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8

                    MaterialSymbol {
                        text: "auto_awesome"
                        iconSize: 16
                        color: Appearance.colors.onPrimaryContainer
                    }

                    Text {
                        id: statusText
                        text: backend.statusMessage
                        color: Appearance.colors.onPrimaryContainer
                        font.pixelSize: Appearance.fontSize.smaller
                        font.weight: Font.Medium
                    }

                    IconButton {
                        symbol: "close"
                        size: 24
                        iconSize: 14
                        iconColor: Appearance.colors.onPrimaryContainer
                        onClicked: backend.clearStatus()
                    }
                }
            }

            // View 1: Not Logged In
            Item {
                id: loginView
                anchors.fill: parent
                visible: !backend.loggedIn

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 20
                    width: 360

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "music_note"
                        iconSize: 64
                        color: Appearance.colors.primary
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Добро пожаловать в Yandex Music"
                        color: Appearance.colors.onSurface
                        font.pixelSize: Appearance.fontSize.title
                        font.weight: Font.Bold
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Авторизуйтесь для доступа к вашим трекам и Моей волне"
                        color: Appearance.colors.onSurfaceVariant
                        font.pixelSize: Appearance.fontSize.small
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    // Device code section
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        visible: backend.loginCode.length > 0

                        Rectangle {
                            Layout.fillWidth: true
                            height: 60
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.surfaceContainerHigh
                            border.width: 1
                            border.color: Appearance.colors.primary

                            Text {
                                anchors.centerIn: parent
                                text: backend.loginCode
                                color: Appearance.colors.primary
                                font.pixelSize: 28
                                font.weight: Font.Bold
                                font.letterSpacing: 4
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Перейдите на <a href=\"" + backend.loginUrl + "\">" + backend.loginUrl + "</a> и введите код выше"
                            color: Appearance.colors.onSurfaceVariant
                            font.pixelSize: Appearance.fontSize.smaller
                            onLinkActivated: (link) => Qt.openUrlExternally(link)
                        }
                    }

                    // Login button
                    Rectangle {
                        Layout.fillWidth: true
                        height: 44
                        radius: Appearance.rounding.full
                        color: loginMouse.containsMouse ? Appearance.colors.primaryHover : Appearance.colors.primary

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 8

                            MaterialSymbol {
                                text: "auto_awesome"
                                iconSize: 18
                                color: Appearance.colors.onPrimary
                            }

                            Text {
                                text: backend.loginBusy ? "Ожидание входа..." : "Войти через код устройства"
                                color: Appearance.colors.onPrimary
                                font.pixelSize: Appearance.fontSize.small
                                font.weight: Font.DemiBold
                            }
                        }

                        MouseArea {
                            id: loginMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: !backend.loginBusy
                            onClicked: backend.loginDevice()
                        }
                    }

                    // Or enter token manually
                    Rectangle {
                        Layout.fillWidth: true
                        height: 40
                        radius: Appearance.rounding.full
                        color: Appearance.colors.surfaceContainerLow
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.08)

                        TextInput {
                            id: tokenInput
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            verticalAlignment: TextInput.AlignVCenter
                            color: Appearance.colors.onSurface
                            font.pixelSize: Appearance.fontSize.smaller
                            clip: true

                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                text: "или вставьте OAuth токен..."
                                color: Appearance.colors.onSurfaceVariant
                                font.pixelSize: Appearance.fontSize.smaller
                                visible: !tokenInput.text && !tokenInput.activeFocus
                            }

                            onAccepted: {
                                if (text.trim().length > 0) {
                                    backend.loginToken(text.trim());
                                }
                            }
                        }
                    }
                }
            }

            // View 2: Cards Grid View (Главная, Плейлисты, Альбомы, Артисты)
            Item {
                id: cardsView
                anchors.fill: parent
                visible: backend.loggedIn && window.isCardsPage

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    Text {
                        text: backend.page === 0 ? "Главная"
                            : (backend.page === 3 ? "Плейлисты"
                            : (backend.page === 4 ? "Альбомы"
                            : (backend.page === 5 ? "Любимые артисты"
                            : backend.listTitle)))
                        color: Appearance.colors.onSurface
                        font.pixelSize: 28
                        font.weight: Font.Bold
                    }

                    GridView {
                        id: cardsGrid
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        cellWidth: 194
                        cellHeight: 254
                        model: backend.cards

                        delegate: CardItem {
                            width: 178
                            height: 238
                        }

                        footer: Item {
                            width: cardsGrid.width
                            height: 110
                        }

                        ScrollBar.vertical: ScrollBar { active: true }
                    }
                }
            }

            // View 3: Logged In - Track List / Collection View (Wave, Likes, Album/Artist tracks)
            Item {
                id: trackListView
                anchors.fill: parent
                visible: backend.loggedIn && !window.isCardsPage

                ListView {
                    id: listView
                    anchors.fill: parent
                    anchors.topMargin: 8
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    clip: true
                    model: backend.tracks

                    header: CollectionHero {
                        width: listView.width
                        height: implicitHeight
                    }

                    delegate: TrackRow {
                        width: listView.width
                    }

                    footer: ColumnLayout {
                        width: listView.width
                        spacing: 16

                        // Artist releases section if on artist page
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            visible: backend.isArtistView && backend.cards.rowCount() > 0

                            Text {
                                text: "Альбомы и релизы"
                                color: Appearance.colors.onSurface
                                font.pixelSize: 22
                                font.weight: Font.Bold
                                leftPadding: 8
                                topPadding: 16
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 16

                                Repeater {
                                    model: backend.cards
                                    delegate: CardItem {
                                        width: 174
                                        height: 234
                                    }
                                }
                            }
                        }

                        Item {
                            height: 110 // Space for floating player bar
                        }
                    }

                    ScrollBar.vertical: ScrollBar { active: true }
                }

                // Wave loading indicator if page == 1 and no tracks yet
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 16
                    visible: backend.page === 1 && backend.tracks.rowCount() === 0

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "auto_awesome"
                        iconSize: 56
                        color: Appearance.colors.primary
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Настраиваем Мою волну..."
                        color: Appearance.colors.onSurface
                        font.pixelSize: Appearance.fontSize.large
                        font.weight: Font.DemiBold
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Подбираем треки под ваше настроение"
                        color: Appearance.colors.onSurfaceVariant
                        font.pixelSize: Appearance.fontSize.small
                    }
                }
            }
        }

        // Floating Player Bar
        FloatingPlayerBar {
            id: playerBar
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            width: Math.min(840, parent.width - 48)
            visible: backend.loggedIn
            onImmersiveRequested: window.immersiveOpen = true
        }

        // Fullscreen Immersive Player Overlay
        ImmersivePlayer {
            id: immersiveOverlay
            anchors.fill: parent
            z: 100
            visible: opacity > 0
            opacity: window.immersiveOpen ? 1.0 : 0.0

            Behavior on opacity {
                NumberAnimation {
                    duration: 240
                    easing.type: Easing.OutCubic
                }
            }

            onCloseRequested: window.immersiveOpen = false
        }
    }
}
