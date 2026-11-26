pragma ComponentBehavior: Bound
import QtQuick

QtObject {
    id: root

    property var modApi: null

    readonly property string remoteListUrl: "https://raw.githubusercontent.com/Hazzz895/FckCensorData/main/list_v2.json"

    function resolveAudioUrl(rawUrl, urlTemplate) {
        if (rawUrl === undefined || rawUrl === null) return "";
        if (typeof rawUrl === "number") {
            return urlTemplate ? String(urlTemplate).replace("%%", String(rawUrl)) : "";
        }
        const s = String(rawUrl).trim();
        if (s.length === 0) return "";
        if (s.indexOf("://") < 0 && urlTemplate) {
            return String(urlTemplate).replace("%%", s);
        }
        return s;
    }

    function guessCodec(url) {
        const lower = String(url || "").toLowerCase();
        if (lower.indexOf(".flac") >= 0) return "flac";
        if (lower.indexOf(".m4a") >= 0 || lower.indexOf(".mp4") >= 0) return "mp4";
        if (lower.indexOf(".ogg") >= 0) return "ogg";
        return "mp3";
    }

    function formatArtists(artists) {
        if (!artists) return "";
        if (typeof artists === "string") return artists;
        if (!Array.isArray(artists)) return "";
        const names = [];
        for (let i = 0; i < artists.length; ++i) {
            const a = artists[i];
            if (typeof a === "string" && a.trim().length > 0) {
                names.push(a.trim());
            } else if (a && typeof a === "object" && a.name) {
                names.push(String(a.name).trim());
            }
        }
        return names.join(", ");
    }

    function parseRemoteList(jsonText) {
        const result = {};
        let parsed = null;
        try {
            parsed = JSON.parse(jsonText);
        } catch (e) {
            if (modApi) modApi.warn("Ошибка парсинга list_v2.json: " + e);
            return { overrides: result, trackCount: 0, audioCount: 0 };
        }

        const sources = parsed && Array.isArray(parsed.sources) ? parsed.sources : [];
        let audioCount = 0;

        for (let sIdx = 0; sIdx < sources.length; ++sIdx) {
            const src = sources[sIdx];
            if (!src || typeof src !== "object") continue;

            // 1. Metadata overrides from src.tracks
            if (src.tracks && typeof src.tracks === "object") {
                const keys = Object.keys(src.tracks);
                for (let i = 0; i < keys.length; ++i) {
                    const id = String(keys[i]);
                    const t = src.tracks[id];
                    if (!t || typeof t !== "object") continue;
                    const entry = result[id] || {};
                    if (t.title && !entry.title) entry.title = String(t.title);
                    const art = formatArtists(t.artists);
                    if (art.length > 0 && !entry.artists) entry.artists = art;
                    if (t.coverUri && !entry.coverUrl) {
                        const uri = String(t.coverUri).replace("%%", "400x400");
                        entry.coverUrl = uri.indexOf("://") >= 0 ? uri : ("https://" + uri.replace(/^\/+/, ""));
                    }
                    if (typeof t.durationMs === "number" && t.durationMs > 0 && !entry.durationMs) {
                        entry.durationMs = t.durationMs;
                    }
                    if (t.available === true || t.isAvailable === true) {
                        entry.available = true;
                    }
                    result[id] = entry;
                }
            }

            // 2. Audio replacements from src.tracksStorages
            if (Array.isArray(src.tracksStorages)) {
                for (let stIdx = 0; stIdx < src.tracksStorages.length; ++stIdx) {
                    const st = src.tracksStorages[stIdx];
                    if (!st || typeof st !== "object") continue;
                    const tpl = st.urlTemplate || "";

                    if (Array.isArray(st.trackIds)) {
                        for (let j = 0; j < st.trackIds.length; ++j) {
                            const item = st.trackIds[j];
                            const id = String(typeof item === "number" ? item : (item && item.id !== undefined ? item.id : ""));
                            if (id.length === 0) continue;
                            const url = resolveAudioUrl(id, tpl);
                            if (url.length === 0) continue;
                            const entry = result[id] || {};
                            if (!entry.audioUrl) {
                                entry.audioUrl = url;
                                entry.codec = guessCodec(url);
                                entry.available = true;
                                audioCount++;
                            }
                            if (typeof item === "object" && item && typeof item.durationMs === "number" && item.durationMs > 0) {
                                entry.durationMs = item.durationMs;
                            }
                            result[id] = entry;
                        }
                    }

                    if (st.tracks && typeof st.tracks === "object") {
                        const tKeys = Object.keys(st.tracks);
                        for (let k = 0; k < tKeys.length; ++k) {
                            const id = String(tKeys[k]);
                            const repl = st.tracks[id];
                            let rawUrl = repl;
                            let dur = 0;
                            if (typeof repl === "object" && repl !== null) {
                                rawUrl = repl.url;
                                if (typeof repl.durationMs === "number") dur = repl.durationMs;
                            }
                            const url = resolveAudioUrl(rawUrl, tpl);
                            if (url.length === 0) continue;
                            const entry = result[id] || {};
                            if (!entry.audioUrl) {
                                entry.audioUrl = url;
                                entry.codec = guessCodec(url);
                                entry.available = true;
                                audioCount++;
                            }
                            if (dur > 0) entry.durationMs = dur;
                            result[id] = entry;
                        }
                    }
                }
            }
        }

        return {
            overrides: result,
            trackCount: Object.keys(result).length,
            audioCount: audioCount
        };
    }

    function applyAllOverrides(remoteOverrides) {
        if (!modApi) return;
        const merged = {};
        const useRemote = Boolean(modApi.storageGet("useRemoteDb", true));
        if (useRemote && remoteOverrides && typeof remoteOverrides === "object") {
            const rKeys = Object.keys(remoteOverrides);
            for (let i = 0; i < rKeys.length; ++i) {
                const id = rKeys[i];
                merged[id] = Object.assign({}, remoteOverrides[id]);
            }
        }

        // User custom overrides always win over remote DB
        const custom = modApi.storageGet("customOverrides", ({}));
        if (custom && typeof custom === "object") {
            const cKeys = Object.keys(custom);
            for (let j = 0; j < cKeys.length; ++j) {
                const id = cKeys[j];
                const ov = custom[id];
                if (!ov || typeof ov !== "object") continue;
                if (ov.disabled) {
                    delete merged[id];
                } else {
                    merged[id] = Object.assign({}, merged[id] || {}, ov);
                }
            }
        }

        modApi.setTrackOverrides(merged);
        modApi.storageSet("appliedCount", Object.keys(merged).length);
    }

    function fetchRemoteDb() {
        if (!modApi) return;
        modApi.storageSet("remoteStatus", "Загрузка базы FckCensorData...");
        modApi.httpGet(remoteListUrl, "fck-censor-db");
    }

    Component.onCompleted: {
        if (!modApi) return;
        modApi.registerTrackMenuAction("spoof-track", "Подменить в FckCensor", "graphic_eq", false);

        // Apply cached remote + custom overrides immediately on startup
        const cached = modApi.storageGet("cachedRemoteOverrides", ({}));
        applyAllOverrides(cached);

        if (Boolean(modApi.storageGet("useRemoteDb", true))) {
            fetchRemoteDb();
        }
    }

    property Connections apiConn: Connections {
        target: root.modApi

        function onHttpFinished(requestId, statusCode, body, error) {
            if (requestId !== "fck-censor-db" || !root.modApi) return;
            if (statusCode !== 200 || !body || body.length === 0) {
                root.modApi.storageSet("remoteStatus", "Ошибка загрузки (HTTP " + statusCode + "): " + (error || "нет ответа"));
                root.modApi.warn("FckCensorData load failed: HTTP " + statusCode + " " + error);
                return;
            }
            const parsed = root.parseRemoteList(body);
            root.modApi.storageSet("cachedRemoteOverrides", parsed.overrides);
            root.modApi.storageSet("remoteTrackCount", parsed.trackCount);
            root.modApi.storageSet("remoteAudioCount", parsed.audioCount);
            root.modApi.storageSet("remoteStatus", "База загружена: " + parsed.trackCount + " треков (" + parsed.audioCount + " аудио)");
            root.applyAllOverrides(parsed.overrides);
            root.modApi.log("FckCensorData loaded: " + parsed.trackCount + " tracks, " + parsed.audioCount + " audio");
        }

        function onTrackMenuActionTriggered(actionId, trackId, trackTitle) {
            if (actionId !== "spoof-track" || !root.modApi) return;
            root.modApi.storageSet("draftTrackId", trackId);
            root.modApi.storageSet("draftTrackTitle", trackTitle);
            root.modApi.showToast("Трек «" + trackTitle + "» (" + trackId + ") выбран — откройте Настройки → FckCensor");
            root.modApi.openSettings();
        }
    }
}
