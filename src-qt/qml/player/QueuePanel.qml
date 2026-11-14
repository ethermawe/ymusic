pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import ymusic.ui

Item {
    id: root

    property MaterialScheme scheme: Appearance.colors

    Row {
        id: headerRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        spacing: 8

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Очередь")
            font.pixelSize: Appearance.fontSize.normal
            font.weight: Font.DemiBold
            color: root.scheme.onSurfaceVariant
        }

        Item { width: Math.max(0, parent.width - 140); height: 1 }

        IconButton {
            visible: backend.queue.count > 0
            symbol: "delete_sweep"
            size: 32
            iconSize: 18
            scheme: root.scheme
            tooltip: qsTr("Очистить очередь")
            onClicked: backend.feature({ action: "queue", operation: "clear" })
        }
    }

    ListView {
        id: list
        anchors.fill: parent
        anchors.topMargin: 56
        leftMargin: 12
        rightMargin: 12
        bottomMargin: 20
        clip: true
        model: backend.queue
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        reuseItems: true
        ScrollBar.vertical: StyledScrollBar {}
        FastWheel { target: list }

        header: Column {
            width: list.width - list.leftMargin - list.rightMargin
            spacing: 8

            StyledText {
                Reveal.shown: backend.hasTrack
                leftPadding: 6
                text: qsTr("Сейчас играет")
                font.pixelSize: Appearance.fontSize.smaller
                font.weight: Font.Bold
                color: root.scheme.onSurfaceVariant
            }
            QueueRow {
                width: parent.width
                Reveal.shown: backend.hasTrack
                trackId: backend.nowId
                titleText: backend.nowTitle
                artistsText: backend.nowArtists
                coverUrl: backend.hasCover ? backend.nowCover : ""
                current: true
                scheme: root.scheme
            }
            StyledText {
                Reveal.shown: backend.queue.count > 0
                leftPadding: 6
                topPadding: 8
                bottomPadding: 2
                text: qsTr("Далее · ") + backend.queue.count
                font.pixelSize: Appearance.fontSize.smaller
                font.weight: Font.Bold
                color: root.scheme.onSurfaceVariant
            }
        }

        delegate: QueueRow {
            required property int index
            required property var model
            width: list.width - list.leftMargin - list.rightMargin
            trackId: model.id || ""
            titleText: model.title || ""
            artistsText: model.artists || ""
            coverUrl: model.hasCover ? (model.coverUrl || "") : ""
            current: Boolean(model.isCurrent)
            available: model.available === undefined ? true : Boolean(model.available)
            scheme: root.scheme
            onClicked: backend.trackAction(trackId, 3)
        }
    }

    EmptyState {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 24
        width: parent.width - 32
        Reveal.shown: backend.queue.count === 0
        symbol: "queue_music"
        title: qsTr("Очередь пуста")
        description: qsTr("Запустите трек, альбом или Мою волну")
        scheme: root.scheme
    }
}
