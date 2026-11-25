import QtQuick

QtObject {
    id: root
    property var modApi: null
    property var slotContext: ({})

    Component.onCompleted: {
        if (!modApi) return;
        modApi.registerTrackMenuAction("youtube_search", "Найти клип на YouTube", "open_in_new", false);
        modApi.log("Hello YMusic запущен");
    }

    property Connections apiConn: Connections {
        target: root.modApi
        function onTrackMenuActionTriggered(actionId, trackId, trackTitle) {
            if (actionId === "youtube_search") {
                const q = encodeURIComponent(trackTitle || modApi.trackTitle || "");
                modApi.openExternalUrl("https://www.youtube.com/results?search_query=" + q);
            }
        }
        function onTrackChanged() {
            if (!modApi || !modApi.hasTrack) return;
            const prev = Number(modApi.storageGet("playedCount", 0));
            modApi.storageSet("playedCount", prev + 1);
        }
    }
}
