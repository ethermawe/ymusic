export function activate(ym) {
    ym.settings.define({
        enabled: {
            type: "boolean",
            title: "Скрывать Explicit-треки",
            default: true
        }
    });

    function filterTracks(payload) {
        if (!ym.settings.get("enabled", true)) {
            return payload;
        }
        if (!payload || !Array.isArray(payload.tracks)) {
            return payload;
        }
        const filtered = payload.tracks.filter(function(t) {
            return !(t && (t.explicit === true || t.contentWarning === "explicit"));
        });
        return Object.assign({}, payload, { tracks: filtered });
    }

    ym.hooks.on("search_results", filterTracks);
    ym.hooks.on("wave_next_batch", filterTracks);
    console.log("hide-explicit activated");
}

export function deactivate() {
    console.log("hide-explicit deactivated");
}
