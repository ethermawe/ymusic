export function activate(ym) {
    let lastId = "";

    ym.events.on("trackChanged", function(track) {
        const id = track && track.id ? String(track.id) : "";
        if (!id || id === lastId) return;
        lastId = id;
        const total = Number(ym.storage.get("totalPlays", 0)) + 1;
        ym.storage.set("totalPlays", total);
        ym.storage.set("lastTrack", (track.artists ? (track.artists + " — ") : "") + (track.title || ""));
    });

    ym.ui.expose("summary", function() {
        return {
            totalPlays: Number(ym.storage.get("totalPlays", 0)),
            lastTrack: String(ym.storage.get("lastTrack", ""))
        };
    });

    ym.pages.register("stats", {
        title: "Статистика",
        icon: "bar_chart",
        qml: "ui/StatsPage.qml"
    });
}
