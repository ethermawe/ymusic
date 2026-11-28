// Пример логического скрипта мода на QJSEngine (API v1)

function loadCount() {
  const n = Number(ym.storage.get("playedCount", 0));
  return isFinite(n) && n >= 0 ? Math.floor(n) : 0;
}

ym.hooks.on("track_after_play", function (ctx) {
  const next = loadCount() + 1;
  ym.storage.set("playedCount", next);
  if (ctx && ctx.title) {
    ym.storage.set("lastTrackTitle", String(ctx.title));
  }
  return ctx;
});

// Экспортируем функции, которые можно вызывать из QML через modApi.call("getStats")
ym.ui.expose("getStats", function () {
  return {
    playedCount: loadCount(),
    lastTrackTitle: String(ym.storage.get("lastTrackTitle", "") || "")
  };
});

ym.ui.expose("resetStats", function () {
  ym.storage.set("playedCount", 0);
  ym.storage.set("lastTrackTitle", "");
  return { ok: true, playedCount: 0 };
});

console.log("hello-ymusic main.js ready (playedCount=" + loadCount() + ")");
