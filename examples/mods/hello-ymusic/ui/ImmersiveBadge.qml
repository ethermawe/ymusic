import QtQuick
import ymusic.sdk 1.0

Item {
    id: root
    property var modApi: null
    property var slotContext: ({})

    property bool showBadge: modApi ? Boolean(modApi.storageGet("showImmersiveBadge", true)) : true
    property var energies: [0.1, 0.2, 0.3, 0.2, 0.1]

    Connections {
        target: root.modApi
        function onStorageChanged(key) {
            if (key === "showImmersiveBadge" && root.modApi) {
                root.showBadge = Boolean(root.modApi.storageGet("showImmersiveBadge", true));
            }
        }
    }

    Connections {
        target: root.modApi
        enabled: root.visible && root.showBadge && !Theme.performanceMode && root.modApi !== null
        function onSpectrumUpdated() {
            const e = root.modApi.spectrumEnergies();
            if (e && e.length >= 5) root.energies = e;
        }
    }

    Rectangle {
        visible: root.showBadge && root.modApi && root.modApi.hasTrack
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 28
        width: hudRow.implicitWidth + 24
        height: 34
        radius: 17
        color: Qt.rgba(0, 0, 0, 0.45)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.16)
        opacity: (root.slotContext && root.slotContext.controlsOpacity !== undefined)
            ? root.slotContext.controlsOpacity : 1.0

        Row {
            id: hudRow
            anchors.centerIn: parent
            spacing: 8

            SpectrumBars {
                anchors.verticalCenter: parent.verticalCenter
                energies: root.energies
                active: root.modApi ? root.modApi.playing : false
                barCount: 4
                maxHeight: 14
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: "Hello Mod"
                font.pixelSize: Theme.fontSize.smaller
                color: "white"
            }
        }
    }
}
