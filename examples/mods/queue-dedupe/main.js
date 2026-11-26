export function activate(ym) {
    ym.hooks.on("queue_before_add", function(payload) {
        const trackId = payload && payload.track ? String(payload.track.id || "") : String(payload && payload.trackId || "");
        if (!trackId) return payload;
        const queue = ym.player.queue() || [];
        for (let i = 0; i < queue.length; ++i) {
            if (String(queue[i].id) === trackId) {
                ym.ui.toast("Трек уже есть в очереди");
                return ym.cancel("duplicate");
            }
        }
        return payload;
    });

    ym.commands.register("dedupe-queue", "Убрать дубли из очереди", function() {
        const queue = ym.player.queue() || [];
        const seen = Object.create(null);
        let dupes = 0;
        for (let i = 0; i < queue.length; ++i) {
            const id = String(queue[i].id || "");
            if (seen[id]) dupes++;
            else seen[id] = true;
        }
        ym.ui.toast(dupes > 0 ? ("Найдено дублей в очереди: " + dupes) : "Дублей в очереди нет");
    }, { shortcut: "Ctrl+Alt+U" });
}
