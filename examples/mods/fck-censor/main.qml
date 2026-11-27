pragma ComponentBehavior: Bound
import QtQuick

QtObject {
    id: root

    property var modApi: null

    readonly property string remoteListUrl: "https://raw.githubusercontent.com/Hazzz895/FckCensorData/main/list_v2.json"

    function normalizeAudioUrl(url) {
        const s = String(url || "").trim();
        if (s.length === 0) return "";
        if (s.indexOf("://") < 0) {
            return "https://" + s.replace(/^\/+/, "");
        }
        return s;
    }

    function resolveAudioUrl(rawUrl, urlTemplate) {
        if (rawUrl === undefined || rawUrl === null) return "";
        let out = "";
        if (typeof rawUrl === "number") {
            out = urlTemplate ? String(urlTemplate).replace("%%", String(rawUrl)) : "";
        } else {
            const s = String(rawUrl).trim();
            if (s.length === 0) return "";
            out = (s.indexOf("://") < 0 && urlTemplate)
                ? String(urlTemplate).replace("%%", s)
                : s;
        }
        return normalizeAudioUrl(out);
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

    function normalizeCover(coverUri) {
        if (!coverUri) return "";
        const uri = String(coverUri).replace("%%", "400x400");
        return uri.indexOf("://") >= 0 ? uri : ("https://" + uri.replace(/^\/+/, ""));
    }

    function parseRemoteList(jsonText) {
        const result = {};
        const albums = {};
        let parsed = null;
        try {
            parsed = JSON.parse(jsonText);
        } catch (e) {
            if (modApi) modApi.warn("Ошибка парсинга list_v2.json: " + e);
            return { overrides: result, albums: albums, trackCount: 0, audioCount: 0, albumCount: 0 };
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
                        entry.coverUrl = normalizeCover(t.coverUri);
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

            // 3. Album track injections from src.albums (supports both `volumes` and `tracks`)
            if (src.albums && typeof src.albums === "object") {
                const aKeys = Object.keys(src.albums);
                for (let aIdx = 0; aIdx < aKeys.length; ++aIdx) {
                    const albumId = String(aKeys[aIdx]);
                    const albumObj = src.albums[albumId];
                    if (!albumObj || typeof albumObj !== "object") continue;

                    const tracksList = [];
                    if (Array.isArray(albumObj.volumes)) {
                        for (let vIdx = 0; vIdx < albumObj.volumes.length; ++vIdx) {
                            const vol = albumObj.volumes[vIdx];
                            if (Array.isArray(vol)) {
                                for (let ti = 0; ti < vol.length; ++ti) tracksList.push(vol[ti]);
                            }
                        }
                    } else if (Array.isArray(albumObj.tracks)) {
                        for (let ti = 0; ti < albumObj.tracks.length; ++ti) tracksList.push(albumObj.tracks[ti]);
                    }
                    if (tracksList.length === 0) continue;

                    const albumCover = albumObj.coverUri ? normalizeCover(albumObj.coverUri) : "";
                    const normalized = [];
                    for (let ti = 0; ti < tracksList.length; ++ti) {
                        const raw = tracksList[ti];
                        const tid = String(typeof raw === "object" && raw !== null ? (raw.id !== undefined ? raw.id : "") : raw);
                        if (tid.length === 0) continue;
                        const meta = result[tid] || {};
                        const item = {
                            id: tid,
                            title: (raw && raw.title) || meta.title || ("Трек " + tid),
                            artists: formatArtists(raw && raw.artists) || meta.artists || "",
                            coverUrl: (raw && raw.coverUri ? normalizeCover(raw.coverUri) : "") || meta.coverUrl || albumCover,
                            durationMs: (raw && typeof raw.durationMs === "number" ? raw.durationMs : 0) || meta.durationMs || 0,
                            available: true
                        };
                        if (meta.audioUrl) {
                            item.audioUrl = normalizeAudioUrl(meta.audioUrl);
                            item.codec = meta.codec || guessCodec(item.audioUrl);
                        }
                        if (meta.audioTrackId) item.audioTrackId = meta.audioTrackId;
                        if (meta.localFile) item.localFile = meta.localFile;
                        normalized.push(item);
                    }
                    if (normalized.length > 0) {
                        albums[albumId] = normalized;
                    }
                }
            }
        }

        return {
            overrides: result,
            albums: albums,
            trackCount: Object.keys(result).length,
            audioCount: audioCount,
            albumCount: Object.keys(albums).length
        };
    }

    function applyAllOverrides() {
        if (!modApi) return;
        const merged = {};
        const useRemote = Boolean(modApi.storageGet("useRemoteDb", true));
        const remoteOverrides = modApi.storageGet("cachedRemoteOverrides", ({})) || ({});
        if (useRemote && remoteOverrides && typeof remoteOverrides === "object") {
            const rKeys = Object.keys(remoteOverrides);
            for (let i = 0; i < rKeys.length; ++i) {
                const id = rKeys[i];
                const copy = Object.assign({}, remoteOverrides[id]);
                if (copy.audioUrl) copy.audioUrl = normalizeAudioUrl(copy.audioUrl);
                merged[id] = copy;
            }
        }

        // User custom overrides always win over remote DB
        const custom = modApi.storageGet("customOverrides", ({})) || ({});
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

        // Apply cached album injections if enabled
        const cachedAlbums = modApi.storageGet("cachedRemoteAlbums", ({})) || ({});
        if (useRemote && cachedAlbums && typeof cachedAlbums === "object") {
            const aKeys = Object.keys(cachedAlbums);
            for (let k = 0; k < aKeys.length; ++k) {
                const albumId = aKeys[k];
                const list = cachedAlbums[albumId];
                if (Array.isArray(list) && list.length > 0) {
                    modApi.setAlbumInjections(albumId, list);
                }
            }
        }

        // Publish declarative badges for track lists and player bar
        const mKeys = Object.keys(merged);
        if (Boolean(modApi.storageGet("showPlayerBadge", true))) {
            const badges = {};
            for (let m = 0; m < mKeys.length; ++m) {
                const id = mKeys[m];
                const hasAudio = Boolean(merged[id].audioUrl || merged[id].localFile || merged[id].audioTrackId);
                badges[id] = {
                    text: "FCK",
                    tone: hasAudio ? "primary" : "tertiary",
                    tooltip: hasAudio ? "Подмена аудио FckCensor" : "Подмена метаданных FckCensor"
                };
            }
            modApi.setTrackBadges(badges);
        } else {
            modApi.clearTrackBadges();
        }
        modApi.storageSet("appliedCount", mKeys.length);
    }

    function fetchRemoteDb() {
        if (!modApi) return;
        modApi.storageSet("remoteStatus", "Загрузка базы FckCensorData…");
        modApi.httpGet(remoteListUrl, "fck-censor-db");
    }

    Component.onCompleted: {
        if (!modApi) return;
        modApi.registerTrackMenuAction("spoof-track", "Подменить в FckCensor", "graphic_eq", false);
        applyAllOverrides();
        if (Boolean(modApi.storageGet("useRemoteDb", true))) {
            fetchRemoteDb();
        }
    }

    property Connections apiConn: Connections {
        target: root.modApi

        function onStorageChanged(key) {
            if (!root.modApi) return;
            if (key === "useRemoteDb" || key === "customOverrides" || key === "showPlayerBadge") {
                root.applyAllOverrides();
            } else if (key === "refreshNonce") {
                root.fetchRemoteDb();
            }
        }

        function onHttpFinished(requestId, statusCode, body, error) {
            if (requestId !== "fck-censor-db" || !root.modApi) return;
            if (statusCode !== 200 || !body || body.length === 0) {
                root.modApi.storageSet("remoteStatus", "Ошибка загрузки (HTTP " + statusCode + "): " + (error || "нет ответа"));
                root.modApi.warn("FckCensorData load failed: HTTP " + statusCode + " " + error);
                return;
            }
            const parsed = root.parseRemoteList(body);
            root.modApi.storageSet("cachedRemoteOverrides", parsed.overrides);
            root.modApi.storageSet("cachedRemoteAlbums", parsed.albums);
            root.modApi.storageSet("remoteTrackCount", parsed.trackCount);
            root.modApi.storageSet("remoteAudioCount", parsed.audioCount);
            root.modApi.storageSet("remoteAlbumCount", parsed.albumCount);
            root.modApi.storageSet(
                "remoteStatus",
                "База обновлена: " + parsed.trackCount + " треков · " + parsed.audioCount + " аудио"
                + (parsed.albumCount > 0 ? (" · " + parsed.albumCount + " альбомов") : "")
            );
            root.applyAllOverrides();
            root.modApi.log("FckCensorData loaded: " + parsed.trackCount + " tracks, " + parsed.audioCount + " audio, " + parsed.albumCount + " albums");
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
