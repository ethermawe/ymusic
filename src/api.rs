use std::collections::HashSet;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, anyhow, bail};
use reqwest::{Client, RequestBuilder};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

const BASE: &str = "https://api.music.yandex.net";
const OAUTH: &str = "https://oauth.yandex.ru";
const CLIENT_HEADER: &str = "YandexMusicAndroid/24023621";
const DESKTOP_CLIENT_HEADER: &str = "YandexMusicDesktopAppWindows/5.95.0";
const DESKTOP_SIGN_KEY: &[u8] = b"kzqU4XhfCaY6B6JTHODeq5";
const SIGN_SALT: &str = "XGRlBW9FXlekgbPrRHuSiA";

// Публичные OAuth-креды Android-приложения Яндекс Музыки (как в MarshalX/yandex-music-api).
const OAUTH_CLIENT_ID: &str = "23cabbbdc6cd418abb4b39c32c41195d";
const OAUTH_CLIENT_SECRET: &str = "53bc75238f0c4d08a118e51fe9203300";

pub fn normalize_track_id(track_id: &str) -> &str {
    track_id.split(':').next().unwrap_or(track_id)
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Track {
    pub id: String,
    pub album_id: Option<String>,
    pub album_title: String,
    pub artist_id: Option<String>,
    #[serde(default)]
    pub artist_links: Vec<(String, String)>,
    pub title: String,
    pub artists: String,
    pub duration_ms: u64,
    pub cover_uri: Option<String>,
    pub available: bool,
    #[serde(default)]
    pub has_sync_lyrics: bool,
    #[serde(default)]
    pub has_text_lyrics: bool,
    #[serde(default)]
    pub r128_i: Option<f32>,
    #[serde(default)]
    pub r128_tp: Option<f32>,
    #[serde(default)]
    pub is_ai: bool,
}

impl Eq for Track {}

impl Track {
    pub fn cover_url(&self, size: u32) -> Option<String> {
        cover_url(self.cover_uri.as_deref(), size)
    }

    pub fn composite_id(&self) -> String {
        match &self.album_id {
            Some(a) => format!("{}:{a}", self.id),
            None => self.id.clone(),
        }
    }

    /// Коэффициент громкости по стандарту EBU R128 (целевой уровень -14 LUFS с защитой от клиппинга по True Peak).
    pub fn r128_gain(&self) -> f32 {
        let Some(integrated) = self.r128_i.filter(|v| v.is_finite() && *v < 0.0 && *v > -70.0) else {
            return 1.0;
        };
        let target_lufs = -14.0f32;
        let mut delta_db = (target_lufs - integrated).clamp(-12.0, 9.0);
        if let Some(tp) = self.r128_tp.filter(|v| v.is_finite()) {
            let max_gain_db = (-1.0 - tp).max(-12.0);
            delta_db = delta_db.min(max_gain_db);
        }
        10.0f32.powf(delta_db / 20.0).clamp(0.25, 2.0)
    }
}

pub fn cover_url(uri: Option<&str>, size: u32) -> Option<String> {
    uri.map(str::trim)
        .filter(|s| !s.is_empty())
        .map(|u| {
            let sized = u.replace("%%", &format!("{size}x{size}"));
            if sized.starts_with("https://") || sized.starts_with("http://") {
                sized
            } else if sized.starts_with("//") {
                format!("https:{sized}")
            } else {
                format!("https://{}", sized.trim_start_matches('/'))
            }
        })
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlaylistCard {
    pub uid: u64,
    pub kind: u64,
    pub title: String,
    pub subtitle: String,
    #[serde(default)]
    pub cover_uri: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct AlbumCard {
    pub id: String,
    pub title: String,
    pub artists: String,
    pub year: Option<u64>,
    pub track_count: u64,
    #[serde(default)]
    pub cover_uri: Option<String>,
    #[serde(default)]
    pub section: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ArtistCard {
    pub id: String,
    pub name: String,
    pub genres: String,
    #[serde(default)]
    pub cover_uri: Option<String>,
    #[serde(default)]
    pub stats: String,
}

#[derive(Clone, Debug)]
pub struct ArtistPage {
    pub artist: ArtistCard,
    pub popular_tracks: Vec<Track>,
    pub albums: Vec<AlbumCard>,
    pub similar_artists: Vec<ArtistCard>,
}

#[derive(Clone, Debug, Default)]
pub struct LandingHome {
    pub personal_playlists: Vec<PlaylistCard>,
    pub new_releases: Vec<AlbumCard>,
    pub new_playlists: Vec<PlaylistCard>,
    pub chart_tracks: Vec<Track>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CreditItem {
    pub title: String,
    pub value: String,
}

#[derive(Clone, Debug)]
pub struct StreamInfo {
    pub url: String,
    pub codec: String,
    pub quality: String,
    pub bitrate: u64,
}

#[derive(Clone, Debug)]
pub struct RotorTracksBatch {
    pub batch_id: String,
    pub tracks: Vec<Track>,
    pub unknown_session: bool,
}

#[derive(Clone, Debug)]
pub enum SearchBest {
    Track(Track),
    Album(AlbumCard),
    Artist(ArtistCard),
    Playlist(PlaylistCard),
}

#[derive(Clone, Debug, Default)]
pub struct SearchSuggestResult {
    pub suggestions: Vec<String>,
    pub best: Option<SearchBest>,
}

#[derive(Clone, Debug, Default)]
pub struct SearchResults {
    pub tracks: Vec<Track>,
    pub albums: Vec<AlbumCard>,
    pub artists: Vec<ArtistCard>,
    pub playlists: Vec<PlaylistCard>,
    pub best: Option<SearchBest>,
    pub has_more: bool,
}

#[derive(Clone, Debug)]
pub struct RotorSession {
    pub session_id: String,
    pub batch_id: String,
    pub tracks: Vec<Track>,
}

#[derive(Clone, Debug, Serialize, PartialEq)]
pub struct LyricsWord {
    pub start: f64,
    pub end: f64,
    pub text: String,
}

#[derive(Clone, Debug, Serialize)]
pub struct LyricsLine {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub time: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub end_time: Option<f64>,
    pub text: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub words: Vec<LyricsWord>,
}

#[derive(Clone, Debug, Serialize)]
pub struct TrackLyrics {
    pub synced: bool,
    #[serde(default)]
    pub word_synced: bool,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub source: String,
    pub lines: Vec<LyricsLine>,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub writers: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub major: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum LyricsSourceMode {
    #[default]
    YandexFirst,
    LrclibFirst,
    LrclibOnly,
    YandexOnly,
}

impl LyricsSourceMode {
    pub fn from_str_opt(raw: Option<&str>) -> Self {
        match raw.unwrap_or("yandex_first") {
            "lrclib_first" => Self::LrclibFirst,
            "lrclib_only" => Self::LrclibOnly,
            "yandex_only" => Self::YandexOnly,
            _ => Self::YandexFirst,
        }
    }
}

#[derive(Clone, Debug)]
pub struct LyricsFetchOptions {
    pub source_mode: LyricsSourceMode,
    pub prefer_word_sync: bool,
    pub lrclib_base_url: String,
}

impl Default for LyricsFetchOptions {
    fn default() -> Self {
        Self {
            source_mode: LyricsSourceMode::YandexFirst,
            prefer_word_sync: true,
            lrclib_base_url: "https://lrclib.net".to_string(),
        }
    }
}

#[derive(Clone, Debug, Default)]
pub struct LyricsQueryMeta {
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration_secs: f64,
    pub has_sync_lyrics: Option<bool>,
    pub has_text_lyrics: Option<bool>,
}

pub struct Account {
    pub uid: u64,
    pub name: String,
    pub avatar_url: Option<String>,
}

pub struct DeviceCode {
    pub device_code: String,
    pub user_code: String,
    pub verification_url: String,
    pub interval: u64,
    pub expires_in: u64,
}

pub fn http_client() -> Client {
    Client::builder()
        .user_agent("ymusic/0.2")
        .dns_resolver(crate::dns::Resolver)
        .http1_only()
        .pool_idle_timeout(Duration::from_secs(15))
        .tcp_keepalive(Duration::from_secs(30))
        .connect_timeout(Duration::from_secs(10))
        .read_timeout(Duration::from_secs(30))
        .build()
        .expect("failed to build HTTP client")
}

#[derive(Clone)]
pub struct Api {
    http: Client,
    token: String,
}

impl Api {
    pub fn new(http: Client, token: String) -> Self {
        Self { http, token }
    }

    pub fn http(&self) -> &Client {
        &self.http
    }

    fn auth(&self, rb: RequestBuilder) -> RequestBuilder {
        rb.header("Authorization", format!("OAuth {}", self.token))
            .header("X-Yandex-Music-Client", CLIENT_HEADER)
            .header("Accept-Language", "ru")
    }

    async fn send_with_retry(rb: RequestBuilder) -> Result<(reqwest::StatusCode, String)> {
        const MAX_ATTEMPTS: usize = 3;
        for attempt in 0..MAX_ATTEMPTS {
            let Some(req) = rb.try_clone() else {
                let resp = rb.send().await.context("нет соединения с сервером")?;
                let status = resp.status();
                let text = resp.text().await?;
                return Ok((status, text));
            };
            let is_last = attempt + 1 == MAX_ATTEMPTS;
            match req.send().await {
                Ok(resp) => {
                    let status = resp.status();
                    match resp.text().await {
                        Ok(text) => {
                            let code = status.as_u16();
                            let retryable_status = code == 429
                                || code == 502
                                || code == 503
                                || code == 504
                                || (code == 403
                                    && attempt == 0
                                    && !text.contains("invalid-token")
                                    && !text.contains("access-denied")
                                    && !text.contains("unauthorized"));
                            if !is_last && retryable_status {
                                tokio::time::sleep(Duration::from_millis(
                                    150 * (attempt as u64 + 1),
                                ))
                                .await;
                                continue;
                            }
                            return Ok((status, text));
                        }
                        Err(e) if !is_last && is_retryable_reqwest_err(&e) => {
                            tokio::time::sleep(Duration::from_millis(150 * (attempt as u64 + 1)))
                                .await;
                        }
                        Err(e) => return Err(e.into()),
                    }
                }
                Err(e) if !is_last && is_retryable_reqwest_err(&e) => {
                    tokio::time::sleep(Duration::from_millis(150 * (attempt as u64 + 1))).await;
                }
                Err(e) => return Err(e).context("нет соединения с сервером"),
            }
        }
        unreachable!()
    }

    async fn result(rb: RequestBuilder) -> Result<Value> {
        let (status, text) = Self::send_with_retry(rb).await?;
        let body: Value = match serde_json::from_str(&text) {
            Ok(v) => v,
            Err(_) if !status.is_success() => bail!("HTTP {}", status.as_u16()),
            Err(e) => return Err(e).context("некорректный ответ API"),
        };
        if !status.is_success() {
            let err = &body["error"];
            let msg = err["message"]
                .as_str()
                .or(err["name"].as_str())
                .or(err.as_str())
                .unwrap_or("неизвестная ошибка");
            bail!("HTTP {}: {msg}", status.as_u16());
        }
        Ok(body.get("result").cloned().unwrap_or(Value::Null))
    }

    async fn get(&self, path: &str, query: &[(&str, &str)]) -> Result<Value> {
        Self::result(self.auth(self.http.get(format!("{BASE}{path}")).query(query))).await
    }

    async fn post_form(&self, path: &str, form: &[(&str, &str)]) -> Result<Value> {
        Self::result(self.auth(self.http.post(format!("{BASE}{path}")).form(form))).await
    }

    async fn post_json(&self, path: &str, body: &Value) -> Result<Value> {
        Self::result(self.auth(self.http.post(format!("{BASE}{path}")).json(body))).await
    }

    pub async fn account(&self) -> Result<Account> {
        let r = self.get("/account/status", &[]).await?;
        let acc = &r["account"];
        let uid = acc["uid"]
            .as_u64()
            .ok_or_else(|| anyhow!("токен недействителен"))?;
        let name = acc["displayName"]
            .as_str()
            .or(acc["login"].as_str())
            .unwrap_or("Пользователь")
            .to_string();

        let mut avatar_url = None;
        let avatar_id = acc["defaultAvatarId"]
            .as_str()
            .or(acc["default_avatar_id"].as_str())
            .or(r["default_avatar_id"].as_str())
            .or(r["defaultAvatarId"].as_str());
        if let Some(id) = avatar_id {
            if !id.is_empty() && id != "0/0-0" {
                avatar_url = Some(format!("https://avatars.yandex.net/get-yapic/{id}/islands-200"));
            }
        }
        if avatar_url.is_none() {
            if let Some(uri) = acc["avatarUrl"]
                .as_str()
                .or(acc["avatar"].as_str())
                .or(r["avatarUrl"].as_str())
            {
                if !uri.is_empty() {
                    let full = if uri.starts_with("//") {
                        format!("https:{uri}")
                    } else if !uri.starts_with("http") {
                        format!("https://{uri}")
                    } else {
                        uri.to_string()
                    };
                    avatar_url = Some(full.replace("%%", "200x200"));
                }
            }
        }
        if avatar_url.is_none() {
            if let Ok(resp) = self
                .auth(
                    self.http
                        .get("https://login.yandex.ru/info?format=json")
                        .timeout(Duration::from_secs(2)),
                )
                .send()
                .await
            {
                if let Ok(info) = resp.json::<Value>().await {
                    let is_empty = info["is_avatar_empty"].as_bool().unwrap_or(false);
                    if !is_empty {
                        if let Some(id) = info["default_avatar_id"].as_str() {
                            if !id.is_empty() && id != "0/0-0" {
                                avatar_url = Some(format!(
                                    "https://avatars.yandex.net/get-yapic/{id}/islands-200"
                                ));
                            }
                        }
                    }
                }
            }
        }
        if avatar_url.is_none() {
            if let Ok(user_info) = self.get(&format!("/users/{uid}"), &[]).await {
                let u = &user_info["user"];
                let id = u["defaultAvatarId"]
                    .as_str()
                    .or(u["default_avatar_id"].as_str())
                    .or(user_info["defaultAvatarId"].as_str());
                if let Some(id) = id {
                    if !id.is_empty() && id != "0/0-0" {
                        avatar_url = Some(format!(
                            "https://avatars.yandex.net/get-yapic/{id}/islands-200"
                        ));
                    }
                }
            }
        }

        Ok(Account { uid, name, avatar_url })
    }

    /// Возвращает список `(track_id, composite_id)` лайкнутых треков.
    pub async fn liked_track_entries(&self, uid: u64) -> Result<Vec<(String, String)>> {
        let r = self
            .get(
                &format!("/users/{uid}/likes/tracks"),
                &[("if-modified-since-revision", "0")],
            )
            .await?;
        Ok(r["library"]["tracks"]
            .as_array()
            .map(|items| {
                items
                    .iter()
                    .filter_map(|t| {
                        let id = id_str(&t["id"])?;
                        let full = match id_str(&t["albumId"]) {
                            Some(album) => format!("{id}:{album}"),
                            None => id.clone(),
                        };
                        Some((id, full))
                    })
                    .collect()
            })
            .unwrap_or_default())
    }

    pub async fn liked_tracks(&self, uid: u64) -> Result<(HashSet<String>, Vec<Track>)> {
        let entries = self.liked_track_entries(uid).await?;
        let liked_set: HashSet<String> = entries.iter().map(|(id, _)| id.clone()).collect();
        let composite: Vec<String> = entries.into_iter().map(|(_, full)| full).collect();
        let tracks = self.tracks(&composite).await?;
        Ok((liked_set, tracks))
    }

    pub async fn like_track(&self, uid: u64, track_id: &str) -> Result<()> {
        self.post_form(
            &format!("/users/{uid}/likes/tracks/add-multiple"),
            &[("track-ids", track_id)],
        )
        .await?;
        Ok(())
    }

    pub async fn unlike_track(&self, uid: u64, track_id: &str) -> Result<()> {
        self.post_form(
            &format!("/users/{uid}/likes/tracks/remove"),
            &[("track-ids", track_id)],
        )
        .await?;
        Ok(())
    }

    pub async fn dislike_track(&self, uid: u64, track_id: &str) -> Result<()> {
        self.post_form(
            &format!("/users/{uid}/dislikes/tracks/add-multiple"),
            &[("track-ids", track_id)],
        )
        .await?;
        Ok(())
    }

    pub async fn tracks(&self, ids: &[String]) -> Result<Vec<Track>> {
        if ids.is_empty() {
            return Ok(Vec::new());
        }
        let mut out = Vec::with_capacity(ids.len());
        let chunks: Vec<&[String]> = ids.chunks(150).collect();
        for (idx, chunk) in chunks.iter().enumerate() {
            if idx > 0 {
                tokio::time::sleep(Duration::from_millis(40)).await;
            }
            let joined = chunk.join(",");
            let r = self
                .post_form("/tracks", &[("track-ids", &joined), ("with-positions", "false")])
                .await?;
            if let Some(items) = r.as_array() {
                let parsed: Vec<Track> = items.iter().filter_map(parse_track).collect();
                if parsed.len() == chunk.len() {
                    out.extend(parsed);
                } else {
                    // Восстанавливаем точный порядок запрошенных ID
                    let mut by_id = std::collections::HashMap::with_capacity(parsed.len());
                    for t in parsed {
                        by_id.entry(t.id.clone()).or_insert(t);
                    }
                    for req_id in *chunk {
                        let clean = normalize_track_id(req_id);
                        if let Some(t) = by_id.get(clean) {
                            out.push(t.clone());
                        }
                    }
                }
            }
        }
        Ok(out)
    }

    pub async fn search_suggest(&self, part: &str) -> Result<Vec<String>> {
        Ok(self.search_suggest_rich(part).await?.suggestions)
    }

    pub async fn search_suggest_rich(&self, part: &str) -> Result<SearchSuggestResult> {
        let trimmed = part.trim();
        if trimmed.is_empty() {
            return Ok(SearchSuggestResult::default());
        }
        let r = self.get("/search/suggest", &[("part", trimmed)]).await?;
        let suggestions = r["suggestions"]
            .as_array()
            .map(|arr| {
                arr.iter()
                    .filter_map(|v| v.as_str().map(str::trim).filter(|s| !s.is_empty()).map(str::to_string))
                    .take(8)
                    .collect()
            })
            .unwrap_or_default();
        let best = parse_search_best(&r["best"]);
        Ok(SearchSuggestResult { suggestions, best })
    }

    pub async fn landing_home(&self) -> Result<LandingHome> {
        let r = self
            .get(
                "/landing3",
                &[(
                    "blocks",
                    "personalplaylists,new-releases,new-playlists,chart,play_contexts",
                )],
            )
            .await?;
        let mut home = LandingHome::default();
        if let Some(blocks) = r["blocks"].as_array() {
            for block in blocks {
                let btype = block["type"].as_str().unwrap_or("");
                let Some(entities) = block["entities"].as_array() else { continue };
                match btype {
                    "personal-playlists" => {
                        for ent in entities {
                            let p_val = ent["data"].get("data").unwrap_or(&ent["data"]);
                            if let Some(mut card) = parse_playlist(p_val) {
                                if let Some(desc) = ent["data"]["description"]
                                    .as_str()
                                    .or_else(|| p_val["description"].as_str())
                                    .filter(|s| !s.is_empty())
                                {
                                    card.subtitle = desc.to_string();
                                }
                                home.personal_playlists.push(card);
                            }
                        }
                    }
                    "new-releases" => {
                        for ent in entities {
                            let a_val = ent.get("data").unwrap_or(ent);
                            if let Some(album) = parse_album(a_val) {
                                home.new_releases.push(album);
                            }
                        }
                    }
                    "new-playlists" => {
                        for ent in entities {
                            let p_val = ent.get("data").unwrap_or(ent);
                            if let Some(pl) = parse_playlist(p_val) {
                                home.new_playlists.push(pl);
                            }
                        }
                    }
                    "chart" => {
                        for ent in entities {
                            let t_val = ent["data"].get("track").unwrap_or(&ent["data"]);
                            if let Some(track) = parse_track(t_val) {
                                home.chart_tracks.push(track);
                            }
                        }
                    }
                    _ => {}
                }
            }
        }
        Ok(home)
    }

    pub async fn chart_tracks(&self) -> Result<Vec<Track>> {
        let r = self.get("/landing3/chart", &[]).await?;
        if let Some(items) = r["chart"]["tracks"].as_array() {
            let mut out = Vec::with_capacity(items.len());
            for item in items {
                let t_val = item.get("track").unwrap_or(item);
                if let Some(t) = parse_track(t_val) {
                    out.push(t);
                }
            }
            if !out.is_empty() {
                return Ok(out);
            }
        }
        Ok(Vec::new())
    }

    pub async fn search_all(&self, text: &str) -> Result<SearchResults> {
        self.search_filtered(text, "all").await
    }

    pub async fn search_filtered(&self, text: &str, filter: &str) -> Result<SearchResults> {
        self.search_filtered_page(text, filter, 0).await
    }

    pub async fn search_filtered_page(&self, text: &str, filter: &str, page: u32) -> Result<SearchResults> {
        anyhow::ensure!(["all", "track", "album", "artist", "playlist"].contains(&filter), "неизвестный фильтр поиска");
        let page_str = page.to_string();
        let r = self
            .get(
                "/search",
                &[
                    ("text", text),
                    ("type", filter),
                    ("page", page_str.as_str()),
                    ("nocorrect", "false"),
                ],
            )
            .await?;
        let mut tracks: Vec<Track> = r["tracks"]["results"]
            .as_array()
            .map(|a| a.iter().filter_map(parse_track).collect())
            .unwrap_or_default();
        let albums: Vec<AlbumCard> = r["albums"]["results"]
            .as_array()
            .map(|a| a.iter().filter_map(parse_album).collect())
            .unwrap_or_default();
        let artists: Vec<ArtistCard> = r["artists"]["results"]
            .as_array()
            .map(|a| a.iter().filter_map(parse_artist).collect())
            .unwrap_or_default();
        let playlists: Vec<PlaylistCard> = r["playlists"]["results"]
            .as_array()
            .map(|a| a.iter().filter_map(parse_playlist).collect())
            .unwrap_or_default();
        let mut best = parse_search_best(&r["best"]);

        // Догружаем полные метаданные треков без обложек, т.к. /search иногда отдаёт сокращённые объекты без coverUri.
        let mut missing_ids: Vec<String> = tracks
            .iter()
            .filter(|t| t.cover_uri.is_none())
            .map(Track::composite_id)
            .collect();
        if let Some(SearchBest::Track(ref bt)) = best
            && bt.cover_uri.is_none()
        {
            missing_ids.push(bt.composite_id());
        }
        if !missing_ids.is_empty()
            && let Ok(full_tracks) = self.tracks(&missing_ids).await
        {
            let by_id: std::collections::HashMap<String, Track> =
                full_tracks.into_iter().map(|t| (t.id.clone(), t)).collect();
            for t in &mut tracks {
                if t.cover_uri.is_none()
                    && let Some(full) = by_id.get(&t.id)
                {
                    if full.cover_uri.is_some() {
                        t.cover_uri = full.cover_uri.clone();
                    }
                    if t.album_id.is_none() {
                        t.album_id = full.album_id.clone();
                    }
                    if t.album_title.is_empty() {
                        t.album_title = full.album_title.clone();
                    }
                }
            }
            if let Some(SearchBest::Track(ref mut bt)) = best
                && bt.cover_uri.is_none()
                && let Some(full) = by_id.get(&bt.id)
                && full.cover_uri.is_some()
            {
                bt.cover_uri = full.cover_uri.clone();
            }
        }

        let section_has_more = |sec: &Value, len: usize| -> bool {
            let total = sec["total"].as_u64().unwrap_or(0);
            let per_page = sec["perPage"].as_u64().unwrap_or(len as u64).max(1);
            len > 0 && ((page as u64 + 1) * per_page < total)
        };
        let has_more = match filter {
            "track" => section_has_more(&r["tracks"], tracks.len()),
            "album" => section_has_more(&r["albums"], albums.len()),
            "artist" => section_has_more(&r["artists"], artists.len()),
            "playlist" => section_has_more(&r["playlists"], playlists.len()),
            _ => {
                section_has_more(&r["tracks"], tracks.len())
                    || section_has_more(&r["albums"], albums.len())
                    || section_has_more(&r["artists"], artists.len())
                    || section_has_more(&r["playlists"], playlists.len())
            }
        };

        Ok(SearchResults {
            tracks,
            albums,
            artists,
            playlists,
            best,
            has_more,
        })
    }

    /// Плейлисты пользователя (собственные + лайкнутые).
    pub async fn user_playlists(&self, uid: u64) -> Result<Vec<PlaylistCard>> {
        let own_res = self.get(&format!("/users/{uid}/playlists/list"), &[]).await;
        let liked_res = self.get(&format!("/users/{uid}/likes/playlists"), &[]).await;
        let mut out = Vec::new();
        if let Ok(v) = own_res
            && let Some(arr) = v.as_array()
        {
            out.extend(arr.iter().filter_map(parse_playlist));
        }
        if let Ok(v) = liked_res
            && let Some(arr) = v.as_array()
        {
            out.extend(arr.iter().filter_map(|item| {
                parse_playlist(item.get("playlist").unwrap_or(item))
            }));
        }
        Ok(out)
    }

    pub async fn playlist_tracks(&self, owner_uid: u64, kind: u64) -> Result<Vec<Track>> {
        let r = self
            .get(&format!("/users/{owner_uid}/playlists/{kind}"), &[])
            .await?;
        let Some(items) = r["tracks"].as_array() else {
            return Ok(Vec::new());
        };
        enum Slot {
            Ready(Track),
            Missing(String),
        }
        let mut slots = Vec::with_capacity(items.len());
        let mut missing_ids = Vec::new();
        for item in items {
            if let Some(t) = item.get("track").and_then(parse_track) {
                slots.push(Slot::Ready(t));
            } else if let Some(t) = parse_track(item) {
                slots.push(Slot::Ready(t));
            } else if let Some(id) = id_str(&item["id"]) {
                let full = match id_str(&item["albumId"]) {
                    Some(a) => format!("{id}:{a}"),
                    None => id.clone(),
                };
                missing_ids.push(full);
                slots.push(Slot::Missing(id));
            }
        }
        let mut fetched_map = std::collections::HashMap::new();
        if !missing_ids.is_empty() {
            for t in self.tracks(&missing_ids).await? {
                fetched_map.entry(t.id.clone()).or_insert(t);
            }
        }
        let mut parsed = Vec::with_capacity(slots.len());
        for slot in slots {
            match slot {
                Slot::Ready(t) => parsed.push(t),
                Slot::Missing(id) => {
                    if let Some(t) = fetched_map.get(&id) {
                        parsed.push(t.clone());
                    }
                }
            }
        }
        Ok(parsed)
    }

    pub async fn delete_playlist(&self, uid: u64, kind: u64) -> Result<()> {
        self.post_form(&format!("/users/{uid}/playlists/{kind}/delete"), &[])
            .await?;
        Ok(())
    }

    pub async fn rename_playlist(&self, uid: u64, kind: u64, title: &str) -> Result<PlaylistCard> {
        let title = title.trim();
        anyhow::ensure!(
            !title.is_empty() && title.chars().count() <= 100,
            "Название должно содержать от 1 до 100 символов"
        );
        let r = self
            .post_form(
                &format!("/users/{uid}/playlists/{kind}/name"),
                &[("value", title)],
            )
            .await?;
        parse_playlist(&r).ok_or_else(|| anyhow!("Сервер не вернул обновлённый плейлист"))
    }

    pub async fn delete_playlist_track(&self, uid: u64, kind: u64, track_id: &str) -> Result<()> {
        let clean_target = normalize_track_id(track_id);
        let playlist = self.get(&format!("/users/{uid}/playlists/{kind}"), &[]).await?;
        anyhow::ensure!(
            id_str(&playlist["owner"]["uid"]).as_deref() == Some(&uid.to_string()),
            "плейлист принадлежит другому пользователю"
        );
        let revision = playlist["revision"]
            .as_u64()
            .ok_or_else(|| anyhow!("сервер не вернул ревизию плейлиста"))?
            .to_string();
        let items = playlist["tracks"]
            .as_array()
            .ok_or_else(|| anyhow!("плейлист пуст"))?;
        let idx = items
            .iter()
            .position(|item| {
                id_str(&item["id"]).as_deref() == Some(clean_target)
                    || id_str(&item["track"]["id"]).as_deref() == Some(clean_target)
            })
            .ok_or_else(|| anyhow!("трек не найден в плейлисте"))?;
        let item_val = &items[idx];
        let mut track_obj = json!({ "id": clean_target });
        if let Some(aid) = id_str(&item_val["albumId"])
            .or_else(|| id_str(&item_val["track"]["albums"][0]["id"]))
        {
            track_obj["albumId"] = json!(aid);
        }
        let diff = json!([{
            "op": "delete",
            "from": idx,
            "to": idx + 1,
            "tracks": [track_obj]
        }])
        .to_string();
        self.post_form(
            &format!("/users/{uid}/playlists/{kind}/change"),
            &[
                ("kind", &kind.to_string()),
                ("revision", &revision),
                ("diff", &diff),
            ],
        )
        .await?;
        Ok(())
    }

    pub async fn playlist_recommendations(&self, uid: u64, kind: u64) -> Result<Vec<Track>> {
        let r = self
            .get(&format!("/users/{uid}/playlists/{kind}/recommendations"), &[])
            .await?;
        Ok(r["tracks"]
            .as_array()
            .map(|arr| arr.iter().filter_map(parse_track).collect())
            .unwrap_or_default())
    }

    pub async fn like_playlist(&self, uid: u64, owner_uid: u64, kind: u64) -> Result<()> {
        let pid = format!("{owner_uid}:{kind}");
        self.post_form(
            &format!("/users/{uid}/likes/playlists/add-multiple"),
            &[("playlist-ids", &pid)],
        )
        .await?;
        Ok(())
    }

    pub async fn unlike_playlist(&self, uid: u64, owner_uid: u64, kind: u64) -> Result<()> {
        let pid = format!("{owner_uid}:{kind}");
        self.post_form(
            &format!("/users/{uid}/likes/playlists/remove"),
            &[("playlist-ids", &pid)],
        )
        .await?;
        Ok(())
    }

    pub async fn like_album(&self, uid: u64, album_id: &str) -> Result<()> {
        self.post_form(
            &format!("/users/{uid}/likes/albums/add-multiple"),
            &[("album-ids", album_id)],
        )
        .await?;
        Ok(())
    }

    pub async fn unlike_album(&self, uid: u64, album_id: &str) -> Result<()> {
        self.post_form(
            &format!("/users/{uid}/likes/albums/remove"),
            &[("album-ids", album_id)],
        )
        .await?;
        Ok(())
    }

    pub async fn like_artist(&self, uid: u64, artist_id: &str) -> Result<()> {
        self.post_form(
            &format!("/users/{uid}/likes/artists/add-multiple"),
            &[("artist-ids", artist_id)],
        )
        .await?;
        Ok(())
    }

    pub async fn unlike_artist(&self, uid: u64, artist_id: &str) -> Result<()> {
        self.post_form(
            &format!("/users/{uid}/likes/artists/remove"),
            &[("artist-ids", artist_id)],
        )
        .await?;
        Ok(())
    }

    pub async fn similar_tracks(&self, track_id: &str) -> Result<Vec<Track>> {
        let clean = normalize_track_id(track_id);
        let r = self.get(&format!("/tracks/{clean}/similar"), &[]).await?;
        Ok(r["similarTracks"]
            .as_array()
            .map(|arr| arr.iter().filter_map(parse_track).collect())
            .unwrap_or_default())
    }

    pub async fn track_credits(&self, track_id: &str) -> Result<Vec<CreditItem>> {
        let clean = normalize_track_id(track_id);
        let r = self.get(&format!("/tracks/{clean}/credits"), &[]).await?;
        Ok(r["credits"]
            .as_array()
            .map(|arr| {
                arr.iter()
                    .filter_map(|item| {
                        let title = item["title"].as_str()?.trim();
                        let value = item["value"].as_str()?.trim();
                        if title.is_empty() || value.is_empty() {
                            None
                        } else {
                            Some(CreditItem {
                                title: title.to_string(),
                                value: value.to_string(),
                            })
                        }
                    })
                    .collect()
            })
            .unwrap_or_default())
    }

    pub async fn play_audio(
        &self,
        uid: u64,
        track: &Track,
        from_cache: bool,
        total_played_seconds: f64,
        end_position_seconds: f64,
    ) {
        let now_iso = format_iso8601_utc(SystemTime::now());
        let track_len_secs = (track.duration_ms / 1000).to_string();
        let played_str = format!("{:.1}", total_played_seconds.max(0.0));
        let end_str = format!("{:.1}", end_position_seconds.max(0.0));
        let uid_str = uid.to_string();
        let cache_str = if from_cache { "True" } else { "False" };
        let album_id = track.album_id.as_deref().unwrap_or("");
        let play_id = format!("ymusic-{}-{}", uid, random_device_id());
        let mut form = vec![
            ("track-id", track.id.as_str()),
            ("from-cache", cache_str),
            ("from", "ymusic-desktop"),
            ("play-id", play_id.as_str()),
            ("uid", uid_str.as_str()),
            ("timestamp", now_iso.as_str()),
            ("client-now", now_iso.as_str()),
            ("track-length-seconds", track_len_secs.as_str()),
            ("total-played-seconds", played_str.as_str()),
            ("end-position-seconds", end_str.as_str()),
        ];
        if !album_id.is_empty() {
            form.push(("album-id", album_id));
        }
        let _ = self.post_form("/play-audio", &form).await;
    }

    pub async fn own_playlists(&self, uid: u64) -> Result<Vec<PlaylistCard>> {
        let result = self.get(&format!("/users/{uid}/playlists/list"), &[]).await?;
        let items = result.as_array().ok_or_else(|| anyhow!("некорректный список плейлистов"))?;
        Ok(items.iter().filter_map(parse_playlist).filter(|p| p.uid == uid).collect())
    }

    pub async fn create_playlist(&self, uid: u64, title: &str, private: bool) -> Result<PlaylistCard> {
        let title = title.trim();
        anyhow::ensure!(!title.is_empty() && title.chars().count() <= 100, "Название должно содержать от 1 до 100 символов");
        let result = self.post_form(&format!("/users/{uid}/playlists/create"),
            &[("title", title), ("visibility", if private { "private" } else { "public" })]).await?;
        parse_playlist(&result).ok_or_else(|| anyhow!("Сервер не вернул созданный плейлист"))
    }

    pub async fn insert_playlist_track(&self, uid: u64, kind: u64, track: &Track) -> Result<()> {
        let album = track.album_id.as_ref().ok_or_else(|| anyhow!("у трека нет идентификатора альбома"))?;
        let playlist = self.get(&format!("/users/{uid}/playlists/{kind}"), &[]).await?;
        anyhow::ensure!(id_str(&playlist["owner"]["uid"]).as_deref() == Some(&uid.to_string()), "плейлист принадлежит другому пользователю");
        let revision = playlist["revision"].as_u64().ok_or_else(|| anyhow!("сервер не вернул ревизию плейлиста"))?.to_string();
        let at = playlist["trackCount"].as_u64().ok_or_else(|| anyhow!("сервер не вернул размер плейлиста"))?;
        let diff = json!([{"op": "insert", "at": at, "tracks": [{"id": track.id, "albumId": album}]}]).to_string();
        self.post_form(&format!("/users/{uid}/playlists/{kind}/change"),
            &[("kind", &kind.to_string()), ("revision", &revision), ("diff", &diff)]).await?;
        Ok(())
    }

    pub async fn liked_albums(&self, uid: u64) -> Result<Vec<AlbumCard>> {
        let r = self
            .get(
                &format!("/users/{uid}/likes/albums"),
                &[("rich", "true")],
            )
            .await?;
        Ok(r.as_array()
            .map(|arr| {
                arr.iter()
                    .filter_map(|item| parse_album(item.get("album").unwrap_or(item)))
                    .collect()
            })
            .unwrap_or_default())
    }

    pub async fn album_with_tracks(&self, album_id: &str) -> Result<(AlbumCard, Vec<Track>)> {
        let r = self
            .get(&format!("/albums/{album_id}/with-tracks"), &[])
            .await?;
        let album = parse_album(&r).ok_or_else(|| anyhow!("не удалось разобрать альбом"))?;
        let mut tracks = Vec::new();
        if let Some(volumes) = r["volumes"].as_array() {
            for vol in volumes {
                if let Some(arr) = vol.as_array() {
                    for mut t in arr.iter().filter_map(parse_track) {
                        if t.album_id.is_none() {
                            t.album_id = Some(album.id.clone());
                        }
                        if t.album_title.is_empty() {
                            t.album_title = album.title.clone();
                        }
                        if t.cover_uri.is_none() {
                            t.cover_uri = album.cover_uri.clone();
                        }
                        tracks.push(t);
                    }
                }
            }
        }
        Ok((album, tracks))
    }

    pub async fn liked_artists(&self, uid: u64) -> Result<Vec<ArtistCard>> {
        let r = self
            .get(&format!("/users/{uid}/likes/artists"), &[])
            .await?;
        Ok(r.as_array()
            .map(|arr| {
                arr.iter()
                    .filter_map(|item| parse_artist(item.get("artist").unwrap_or(item)))
                    .collect()
            })
            .unwrap_or_default())
    }

    pub async fn artist_brief(&self, artist_id: &str) -> Result<ArtistPage> {
        let r = self
            .get(&format!("/artists/{artist_id}/brief-info"), &[])
            .await?;
        let mut artist = parse_artist(&r["artist"])
            .ok_or_else(|| anyhow!("не удалось разобрать страницу артиста"))?;
        if artist.cover_uri.is_none() {
            artist.cover_uri = r["allCovers"]
                .as_array()
                .and_then(|a| a.first())
                .and_then(|c| c["uri"].as_str())
                .map(str::to_string);
        }
        let stats_src = if r["stats"].is_object() {
            &r["stats"]
        } else {
            &r["artist"]["stats"]
        };
        let page_stats = format_artist_page_stats(stats_src, r["artist"]["likesCount"].as_u64());
        if !page_stats.is_empty() {
            artist.stats = page_stats;
        }
        let popular_tracks = r["popularTracks"]
            .as_array()
            .map(|arr| arr.iter().filter_map(parse_track).collect())
            .unwrap_or_default();
        let mut albums: Vec<AlbumCard> = r["albums"]
            .as_array()
            .map(|arr| arr.iter().filter_map(parse_album).collect())
            .unwrap_or_default();
        if let Some(also) = r["alsoAlbums"].as_array() {
            let existing: HashSet<String> = albums.iter().map(|a| a.id.clone()).collect();
            albums.extend(
                also.iter()
                    .filter_map(parse_album)
                    .filter(|a| !existing.contains(&a.id)),
            );
        }
        albums.sort_by(|a, b| b.year.unwrap_or(0).cmp(&a.year.unwrap_or(0)));
        let similar_artists: Vec<ArtistCard> = r["similarArtists"]
            .as_array()
            .map(|arr| arr.iter().filter_map(parse_artist).take(12).collect())
            .unwrap_or_default();
        Ok(ArtistPage {
            artist,
            popular_tracks,
            albums,
            similar_artists,
        })
    }

    /// Создаёт новую сессию «Моей волны» или радио по сиду (например, `user:onyourwave`, `track:123`, `artist:456`).
    pub async fn rotor_session_new(&self, seeds: &[&str]) -> Result<RotorSession> {
        let body = json!({
            "seeds": seeds,
            "includeTracksInResponse": true,
        });
        let r = self.post_json("/rotor/session/new", &body).await?;
        let session_id = r["radioSessionId"]
            .as_str()
            .ok_or_else(|| anyhow!("нет radioSessionId в ответе волны"))?
            .to_string();
        let batch_id = r["batchId"].as_str().unwrap_or_default().to_string();
        let tracks = parse_rotor_sequence(&r["sequence"]);
        Ok(RotorSession {
            session_id,
            batch_id,
            tracks,
        })
    }

    pub async fn wave_settings(&self) -> Result<Value> {
        self.get("/rotor/wave/settings", &[("seeds", "user:onyourwave")]).await
    }

    /// Догружает следующую партию треков для активной сессии волны.
    pub async fn rotor_session_tracks(
        &self,
        session_id: &str,
        queue: &[String],
    ) -> Result<RotorTracksBatch> {
        let body = json!({ "queue": queue });
        let r = self
            .post_json(&format!("/rotor/session/{session_id}/tracks"), &body)
            .await?;
        let unknown_session = r["unknownSession"].as_bool().unwrap_or(false);
        let batch_id = r["batchId"].as_str().unwrap_or_default().to_string();
        let tracks = parse_rotor_sequence(&r["sequence"]);
        Ok(RotorTracksBatch {
            batch_id,
            tracks,
            unknown_session,
        })
    }

    pub async fn rotor_feedback(
        &self,
        session_id: &str,
        batch_id: &str,
        event_type: &str,
        track_id: Option<&str>,
        total_played_seconds: Option<f64>,
    ) {
        let body = build_rotor_feedback_body(
            batch_id,
            event_type,
            track_id,
            total_played_seconds,
            SystemTime::now(),
        );
        if let Err(e) = self
            .post_json(&format!("/rotor/session/{session_id}/feedback"), &body)
            .await
        {
            eprintln!("Rotor feedback ({event_type}) error: {e:#}");
        }
    }

    /// Получает прямую подписанную ссылку и метаданные потока через `/get-file-info` (с поддержкой Lossless FLAC, AAC, MP3)
    /// и автоматическим резервным переходом на `/tracks/{id}/download-info`.
    pub async fn track_stream_info(&self, track_id: &str, preferred_quality: &str) -> Result<StreamInfo> {
        let clean_id = normalize_track_id(track_id);
        let quality = match preferred_quality {
            "lossless" | "hq" | "nq" => preferred_quality,
            _ => "hq",
        };
        let codecs: &[&str] = match quality {
            "lossless" => &["flac", "flac-mp4", "aac-mp4", "mp3"],
            "nq" => &["aac-mp4", "mp3"],
            _ => &["mp3", "aac-mp4"],
        };
        let transport = "raw";
        let ts = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        let sign = build_file_info_sign(ts, clean_id, quality, codecs, transport);
        let ts_str = ts.to_string();
        let codecs_csv = codecs.join(",");

        let rb = self
            .http
            .get(format!("{BASE}/get-file-info"))
            .header("Authorization", format!("OAuth {}", self.token))
            .header("X-Yandex-Music-Client", DESKTOP_CLIENT_HEADER)
            .header("Accept-Language", "ru")
            .query(&[
                ("ts", ts_str.as_str()),
                ("trackId", clean_id),
                ("quality", quality),
                ("codecs", codecs_csv.as_str()),
                ("transports", transport),
                ("sign", sign.as_str()),
            ]);

        if let Ok(r) = Self::result(rb).await {
            let di = &r["downloadInfo"];
            let resp_transport = di["transport"].as_str().unwrap_or("raw");
            if resp_transport == "raw" {
                let url = di["url"]
                    .as_str()
                    .filter(|s| !s.is_empty())
                    .or_else(|| {
                        di["urls"]
                            .as_array()
                            .and_then(|a| a.first())
                            .and_then(|v| v.as_str())
                            .filter(|s| !s.is_empty())
                    });
                if let Some(url) = url {
                    let codec = di["codec"].as_str().unwrap_or("mp3").to_string();
                    let actual_quality = di["quality"].as_str().unwrap_or(quality).to_string();
                    let bitrate = di["bitrate"].as_u64().unwrap_or(320);
                    return Ok(StreamInfo {
                        url: url.to_string(),
                        codec,
                        quality: actual_quality,
                        bitrate,
                    });
                }
            }
        }

        let (url, bitrate) = self.track_direct_url_legacy(clean_id).await?;
        Ok(StreamInfo {
            url,
            codec: "mp3".to_string(),
            quality: "hq".to_string(),
            bitrate,
        })
    }

    /// Получает прямую подписанную ссылку на аудиопоток (по умолчанию HQ).
    pub async fn track_direct_url(&self, track_id: &str) -> Result<String> {
        Ok(self.track_stream_info(track_id, "hq").await?.url)
    }

    async fn track_direct_url_legacy(&self, clean_id: &str) -> Result<(String, u64)> {
        let r = self.get(&format!("/tracks/{clean_id}/download-info"), &[]).await?;
        let infos = r.as_array().ok_or_else(|| anyhow!("нет вариантов загрузки"))?;
        let bitrate = |i: &&Value| i["bitrateInKbps"].as_u64().unwrap_or(0);
        let mp3 = || infos.iter().filter(|i| i["codec"] == "mp3");
        let best = mp3()
            .filter(|i| !i["preview"].as_bool().unwrap_or(false))
            .max_by_key(bitrate)
            .or_else(|| mp3().max_by_key(bitrate))
            .ok_or_else(|| anyhow!("трек недоступен для прослушивания"))?;
        let info_url = best["downloadInfoUrl"]
            .as_str()
            .ok_or_else(|| anyhow!("нет downloadInfoUrl"))?;
        let br = best["bitrateInKbps"].as_u64().unwrap_or(320);

        let (status, xml) = Self::send_with_retry(self.auth(self.http.get(info_url))).await?;
        if !status.is_success() {
            bail!("HTTP {}", status.as_u16());
        }
        let host = xml_tag(&xml, "host")?;
        let path = xml_tag(&xml, "path")?;
        let ts = xml_tag(&xml, "ts")?;
        let s = xml_tag(&xml, "s")?;
        let sign = md5::compute(format!("{SIGN_SALT}{}{s}", path.get(1..).unwrap_or("")));
        Ok((format!("https://{host}/get-mp3/{sign:x}/{ts}{path}"), br))
    }

    /// Загружает синхронизированный (LRC) текст с Яндекса или LRCLIB, либо обычный текст (`format=TEXT`).
    pub async fn track_lyrics(
        &self,
        track_id: &str,
        meta: Option<&LyricsQueryMeta>,
        options: &LyricsFetchOptions,
    ) -> Result<TrackLyrics> {
        let clean_id = normalize_track_id(track_id);
        let lrclib_base = normalize_lrclib_base_url(&options.lrclib_base_url);
        let has_meta = meta.is_some_and(|m| !m.title.trim().is_empty() && !m.artist.trim().is_empty());

        match options.source_mode {
            LyricsSourceMode::LrclibOnly => {
                if has_meta {
                    if let Some(m) = meta {
                        match self.lrclib_lyrics(m, &lrclib_base).await {
                            Ok(Some(found)) => return Ok(found),
                            Ok(None) => {}
                            Err(e) => {
                                eprintln!("[lyrics] lrclib lookup failed for {} - {}: {e}", m.artist, m.title);
                            }
                        }
                    }
                }
                return Ok(TrackLyrics {
                    synced: false,
                    word_synced: false,
                    source: String::new(),
                    lines: Vec::new(),
                    writers: String::new(),
                    major: String::new(),
                });
            }
            LyricsSourceMode::YandexOnly => {
                let (sync_res, writers, major) = self.fetch_yandex_sync_lyrics(&clean_id, meta).await;
                if let Some(lyrics) = sync_res {
                    return Ok(lyrics);
                }
                return Ok(
                    self.fetch_yandex_plain_lyrics(&clean_id, meta, writers, major)
                        .await
                        .unwrap_or(TrackLyrics {
                            synced: false,
                            word_synced: false,
                            source: String::new(),
                            lines: Vec::new(),
                            writers: String::new(),
                            major: String::new(),
                        }),
                );
            }
            LyricsSourceMode::LrclibFirst => {
                if let Some(m) = meta.filter(|_| has_meta) {
                    match self.lrclib_lyrics(m, &lrclib_base).await {
                        Ok(Some(found)) => return Ok(found),
                        Ok(None) => {}
                        Err(e) => {
                            eprintln!("[lyrics] lrclib lookup failed for {} - {}: {e}", m.artist, m.title);
                        }
                    }
                }
                let (sync_res, writers, major) = self.fetch_yandex_sync_lyrics(&clean_id, meta).await;
                if let Some(lyrics) = sync_res {
                    return Ok(lyrics);
                }
                return Ok(
                    self.fetch_yandex_plain_lyrics(&clean_id, meta, writers, major)
                        .await
                        .unwrap_or(TrackLyrics {
                            synced: false,
                            word_synced: false,
                            source: String::new(),
                            lines: Vec::new(),
                            writers: String::new(),
                            major: String::new(),
                        }),
                );
            }
            LyricsSourceMode::YandexFirst => {
                let (yandex_tuple, lrclib_res) = if options.prefer_word_sync && has_meta {
                    let m = meta.unwrap();
                    let (y, l) = tokio::join!(
                        self.fetch_yandex_sync_lyrics(&clean_id, meta),
                        self.lrclib_lyrics(m, &lrclib_base)
                    );
                    (y, Some(l))
                } else {
                    (self.fetch_yandex_sync_lyrics(&clean_id, meta).await, None)
                };

                let (yandex_sync, mut writers, mut major) = yandex_tuple;
                let lrclib_queried = lrclib_res.is_some();

                let lrclib_found = match lrclib_res {
                    Some(Ok(opt)) => opt,
                    Some(Err(e)) => {
                        if let Some(m) = meta {
                            eprintln!("[lyrics] lrclib lookup failed for {} - {}: {e}", m.artist, m.title);
                        }
                        None
                    }
                    None => None,
                };

                // If LRCLIB returned true word-level timestamps and preference is enabled, use it!
                if options.prefer_word_sync {
                    if let Some(mut lrc) = lrclib_found.clone().filter(|l| l.word_synced) {
                        if lrc.writers.is_empty() {
                            lrc.writers = writers;
                        }
                        if lrc.major.is_empty() {
                            lrc.major = major;
                        }
                        return Ok(lrc);
                    }
                }

                if let Some(lyrics) = yandex_sync {
                    return Ok(lyrics);
                }

                let lrclib_checked = if lrclib_queried {
                    lrclib_found
                } else if let Some(m) = meta.filter(|_| has_meta) {
                    match self.lrclib_lyrics(m, &lrclib_base).await {
                        Ok(opt) => opt,
                        Err(e) => {
                            eprintln!("[lyrics] lrclib lookup failed for {} - {}: {e}", m.artist, m.title);
                            None
                        }
                    }
                } else {
                    None
                };

                if let Some(mut lrc) = lrclib_checked.clone().filter(|l| l.synced) {
                    if lrc.writers.is_empty() {
                        lrc.writers = writers;
                    }
                    if lrc.major.is_empty() {
                        lrc.major = major;
                    }
                    return Ok(lrc);
                }

                if let Some(plain) = self.fetch_yandex_plain_lyrics(&clean_id, meta, writers.clone(), major.clone()).await {
                    return Ok(plain);
                }

                if let Some(mut lrc_plain) = lrclib_checked {
                    lrc_plain.writers = std::mem::take(&mut writers);
                    lrc_plain.major = std::mem::take(&mut major);
                    return Ok(lrc_plain);
                }

                Ok(TrackLyrics {
                    synced: false,
                    word_synced: false,
                    source: String::new(),
                    lines: Vec::new(),
                    writers,
                    major,
                })
            }
        }
    }

    async fn fetch_yandex_sync_lyrics(
        &self,
        clean_id: &str,
        meta: Option<&LyricsQueryMeta>,
    ) -> (Option<TrackLyrics>, String, String) {
        let mut writers = String::new();
        let mut major = String::new();
        let try_sync = meta.and_then(|m| m.has_sync_lyrics).unwrap_or(true);
        if !try_sync {
            return (None, writers, major);
        }

        const LYRICS_SIGN_KEY: &[u8] = b"p93jhgh689SBReK6ghtw62";
        let ts = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs()
            .to_string();
        let msg = format!("{clean_id}{ts}");
        let sign = base64_encode(&hmac_sha256(LYRICS_SIGN_KEY, msg.as_bytes()));

        match self
            .get(
                &format!("/tracks/{clean_id}/lyrics"),
                &[("format", "LRC"), ("timeStamp", &ts), ("sign", &sign)],
            )
            .await
        {
            Ok(r) => {
                extract_lyrics_credits(&r, &mut writers, &mut major);
                if let Some(url) = r["downloadUrl"].as_str().filter(|s| !s.is_empty()) {
                    if let Ok((status, lrc_text)) = Self::send_with_retry(self.http.get(url)).await {
                        if status.is_success() {
                            let (word_synced, lines) = parse_lrc_with_words(&lrc_text);
                            if !lines.is_empty() {
                                return (
                                    Some(TrackLyrics {
                                        synced: true,
                                        word_synced,
                                        source: "yandex".to_string(),
                                        lines,
                                        writers: writers.clone(),
                                        major: major.clone(),
                                    }),
                                    writers,
                                    major,
                                );
                            }
                        }
                    }
                }
            }
            Err(e) => {
                eprintln!("[lyrics] yandex track {clean_id}: /lyrics LRC failed: {e}");
            }
        }
        (None, writers, major)
    }

    async fn fetch_yandex_plain_lyrics(
        &self,
        clean_id: &str,
        meta: Option<&LyricsQueryMeta>,
        mut writers: String,
        mut major: String,
    ) -> Option<TrackLyrics> {
        let try_text = meta.and_then(|m| m.has_text_lyrics).unwrap_or(true);
        if try_text {
            const LYRICS_SIGN_KEY: &[u8] = b"p93jhgh689SBReK6ghtw62";
            let ts = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs()
                .to_string();
            let msg = format!("{clean_id}{ts}");
            let sign = base64_encode(&hmac_sha256(LYRICS_SIGN_KEY, msg.as_bytes()));
            if let Ok(r) = self
                .get(
                    &format!("/tracks/{clean_id}/lyrics"),
                    &[("format", "TEXT"), ("timeStamp", &ts), ("sign", &sign)],
                )
                .await
            {
                extract_lyrics_credits(&r, &mut writers, &mut major);
                if let Some(url) = r["downloadUrl"].as_str().filter(|s| !s.is_empty()) {
                    if let Ok((status, plain_text)) = Self::send_with_retry(self.http.get(url)).await {
                        if status.is_success() {
                            let lines = plain_lyrics_lines(&plain_text);
                            if lines.iter().any(|l| !l.text.is_empty()) {
                                return Some(TrackLyrics {
                                    synced: false,
                                    word_synced: false,
                                    source: "yandex".to_string(),
                                    lines,
                                    writers,
                                    major,
                                });
                            }
                        }
                    }
                }
            }
        }

        if let Ok(sup) = self.get(&format!("/tracks/{clean_id}/supplement"), &[]).await {
            if let Some(full) = sup["lyrics"]["fullLyrics"].as_str() {
                let lines = plain_lyrics_lines(full);
                if lines.iter().any(|l| !l.text.is_empty()) {
                    return Some(TrackLyrics {
                        synced: false,
                        word_synced: false,
                        source: "yandex".to_string(),
                        lines,
                        writers,
                        major,
                    });
                }
            }
        }
        None
    }

    async fn lrclib_lyrics(&self, meta: &LyricsQueryMeta, base_url: &str) -> Result<Option<TrackLyrics>> {
        let mut get_params: Vec<(&str, String)> = vec![
            ("track_name", meta.title.trim().to_string()),
            ("artist_name", meta.artist.trim().to_string()),
        ];
        if !meta.album.trim().is_empty() {
            get_params.push(("album_name", meta.album.trim().to_string()));
        }
        if meta.duration_secs > 1.0 {
            get_params.push(("duration", format!("{}", meta.duration_secs.round() as u64)));
        }

        let ua = format!("ymusic/{} (https://github.com/ethermawe/ymusic)", env!("CARGO_PKG_VERSION"));
        let get_url = format!("{base_url}/api/get");
        if let Ok(resp) = self
            .http
            .get(&get_url)
            .header(reqwest::header::USER_AGENT, &ua)
            .query(&get_params)
            .timeout(Duration::from_secs(6))
            .send()
            .await
        {
            if resp.status().is_success() {
                if let Ok(val) = resp.json::<Value>().await {
                    if let Some(res) = extract_lrclib_entry(&val) {
                        if res.synced {
                            return Ok(Some(res));
                        }
                    }
                }
            }
        }

        // Fallback search (also handles Yandex titles with "(feat. ...)" / "(Remaster)" suffixes).
        let clean_title = strip_title_suffix(&meta.title);
        let search_params = [
            ("track_name", clean_title.as_str()),
            ("artist_name", meta.artist.trim()),
        ];
        let search_url = format!("{base_url}/api/search");
        let resp = self
            .http
            .get(&search_url)
            .header(reqwest::header::USER_AGENT, &ua)
            .query(&search_params)
            .timeout(Duration::from_secs(6))
            .send()
            .await?;
        if !resp.status().is_success() {
            return Ok(None);
        }
        let arr: Vec<Value> = resp.json().await.unwrap_or_default();
        let mut best_synced: Option<TrackLyrics> = None;
        let mut best_plain: Option<TrackLyrics> = None;
        for entry in &arr {
            if meta.duration_secs > 1.0 {
                if let Some(d) = entry["duration"].as_f64() {
                    if (d - meta.duration_secs).abs() > 6.0 {
                        continue;
                    }
                }
            }
            if let Some(parsed) = extract_lrclib_entry(entry) {
                if parsed.word_synced {
                    return Ok(Some(parsed));
                }
                if parsed.synced && best_synced.is_none() {
                    best_synced = Some(parsed);
                } else if best_plain.is_none() {
                    best_plain = Some(parsed);
                }
            }
        }
        Ok(best_synced.or(best_plain))
    }
}

pub async fn request_device_code(http: &Client) -> Result<DeviceCode> {
    let device_id = random_device_id();
    let v: Value = http
        .post(format!("{OAUTH}/device/code"))
        .form(&[
            ("client_id", OAUTH_CLIENT_ID),
            ("device_id", device_id.as_str()),
            ("device_name", "ymusic"),
        ])
        .send()
        .await?
        .json()
        .await?;
    let field = |k: &str| v[k].as_str().map(str::to_string);
    match (field("device_code"), field("user_code")) {
        (Some(device_code), Some(user_code)) => Ok(DeviceCode {
            device_code,
            user_code,
            verification_url: field("verification_url")
                .unwrap_or_else(|| "https://ya.ru/device".into()),
            interval: v["interval"].as_u64().unwrap_or(5),
            expires_in: v["expires_in"].as_u64().unwrap_or(300),
        }),
        _ => bail!(
            "не удалось получить код: {}",
            v["error_description"].as_str().unwrap_or("неизвестная ошибка")
        ),
    }
}

/// `Ok(None)`, пока пользователь не подтвердил вход.
pub async fn poll_device_token(http: &Client, device_code: &str) -> Result<Option<String>> {
    let v: Value = http
        .post(format!("{OAUTH}/token"))
        .form(&[
            ("grant_type", "device_code"),
            ("code", device_code),
            ("client_id", OAUTH_CLIENT_ID),
            ("client_secret", OAUTH_CLIENT_SECRET),
        ])
        .send()
        .await?
        .json()
        .await?;
    if let Some(token) = v["access_token"].as_str() {
        return Ok(Some(token.to_string()));
    }
    match v["error"].as_str() {
        Some("authorization_pending") => Ok(None),
        Some(e) => bail!("{}", v["error_description"].as_str().unwrap_or(e)),
        None => bail!("неожиданный ответ OAuth"),
    }
}

fn parse_rotor_sequence(seq: &Value) -> Vec<Track> {
    seq.as_array()
        .map(|arr| {
            arr.iter()
                .filter_map(|item| parse_track(item.get("track").unwrap_or(item)))
                .collect()
        })
        .unwrap_or_default()
}

fn non_empty_str<'a>(v: &'a Value) -> Option<&'a str> {
    v.as_str().map(str::trim).filter(|s| !s.is_empty())
}

fn parse_search_best(v: &Value) -> Option<SearchBest> {
    let kind = non_empty_str(&v["type"])?;
    let res = &v["result"];
    match kind {
        "track" => parse_track(res).map(SearchBest::Track),
        "album" => parse_album(res).map(SearchBest::Album),
        "artist" => parse_artist(res).map(SearchBest::Artist),
        "playlist" => parse_playlist(res).map(SearchBest::Playlist),
        _ => None,
    }
}

fn parse_track(v: &Value) -> Option<Track> {
    let id = id_str(&v["id"])?;
    let mut title = v["title"].as_str().unwrap_or("Без названия").to_string();
    if let Some(version) = v["version"].as_str().filter(|s| !s.is_empty()) {
        title = format!("{title} ({version})");
    }
    let artists_arr = v["artists"].as_array();
    let artist_links: Vec<(String, String)> = artists_arr
        .map(|a| {
            a.iter()
                .filter_map(|x| Some((id_str(&x["id"]).unwrap_or_default(), x["name"].as_str()?.to_string())))
                .collect()
        })
        .unwrap_or_default();
    let artist_id = artist_links.iter().find(|(id, _)| !id.is_empty()).map(|(id, _)| id.clone())
        .or_else(|| artists_arr.and_then(|a| a.first()).and_then(|x| id_str(&x["id"])));
    let artists = artists_arr
        .map(|a| {
            a.iter()
                .filter_map(|x| x["name"].as_str())
                .collect::<Vec<_>>()
                .join(", ")
        })
        .unwrap_or_default();
    let album = &v["albums"][0];
    let album_id = id_str(&album["id"]);
    let album_title = album["title"].as_str().unwrap_or_default().to_string();
    let has_sync_lyrics = v["lyricsInfo"]["hasAvailableSyncLyrics"].as_bool().unwrap_or(false);
    let has_text_lyrics = v["lyricsInfo"]["hasAvailableTextLyrics"]
        .as_bool()
        .or_else(|| v["lyricsAvailable"].as_bool())
        .unwrap_or(has_sync_lyrics);
    let r128_i = v["r128"]["i"].as_f64().map(|x| x as f32);
    let r128_tp = v["r128"]["tp"].as_f64().map(|x| x as f32);
    let is_ai = artist_id
        .as_deref()
        .is_some_and(crate::slopless::is_builtin_ai_artist_str)
        || artist_links
            .iter()
            .any(|(aid, _)| crate::slopless::is_builtin_ai_artist_str(aid));
    let cover_uri = non_empty_str(&v["coverUri"])
        .or_else(|| {
            v["albums"].as_array().and_then(|arr| {
                arr.iter().find_map(|a| {
                    non_empty_str(&a["coverUri"]).or_else(|| non_empty_str(&a["ogImage"]))
                })
            })
        })
        .or_else(|| non_empty_str(&v["ogImage"]))
        .map(str::to_string);
    Some(Track {
        id,
        album_id,
        album_title,
        artist_id,
        artist_links,
        title,
        artists,
        duration_ms: v["durationMs"].as_u64().unwrap_or(0),
        cover_uri,
        available: v["available"].as_bool().unwrap_or(true),
        has_sync_lyrics,
        has_text_lyrics,
        r128_i,
        r128_tp,
        is_ai,
    })
}

fn parse_playlist(v: &Value) -> Option<PlaylistCard> {
    let uid = v["uid"].as_u64().or_else(|| v["owner"]["uid"].as_u64())?;
    let kind = v["kind"].as_u64()?;
    let title = v["title"].as_str().unwrap_or("Плейлист").to_string();
    let count = v["trackCount"].as_u64().unwrap_or(0);
    let owner = v["owner"]["name"]
        .as_str()
        .or(v["owner"]["login"].as_str())
        .unwrap_or("");
    let subtitle = if owner.is_empty() {
        format!("{count} треков")
    } else {
        format!("{owner} • {count} тр.")
    };
    let cover_uri = non_empty_str(&v["cover"]["uri"])
        .or_else(|| non_empty_str(&v["coverUri"]))
        .or_else(|| {
            v["cover"]["itemsUri"]
                .as_array()
                .and_then(|a| a.first())
                .and_then(non_empty_str)
        })
        .or_else(|| non_empty_str(&v["ogImage"]))
        .map(str::to_string);
    Some(PlaylistCard {
        uid,
        kind,
        title,
        subtitle,
        cover_uri,
    })
}

fn parse_album(v: &Value) -> Option<AlbumCard> {
    let id = id_str(&v["id"])?;
    let mut title = v["title"].as_str().unwrap_or("Альбом").to_string();
    if let Some(version) = v["version"].as_str().filter(|s| !s.is_empty()) {
        title = format!("{title} ({version})");
    }
    let artists = v["artists"]
        .as_array()
        .map(|a| {
            a.iter()
                .filter_map(|x| x["name"].as_str())
                .collect::<Vec<_>>()
                .join(", ")
        })
        .unwrap_or_default();
    let year = v["year"].as_u64();
    let track_count = v["trackCount"].as_u64().unwrap_or(0);
    let cover_uri = non_empty_str(&v["coverUri"])
        .or_else(|| non_empty_str(&v["ogImage"]))
        .map(str::to_string);
    Some(AlbumCard {
        id,
        title,
        artists,
        year,
        track_count,
        cover_uri,
        section: String::new(),
    })
}

fn parse_artist(v: &Value) -> Option<ArtistCard> {
    let id = id_str(&v["id"])?;
    let name = v["name"].as_str()?.to_string();
    let genres = v["genres"]
        .as_array()
        .map(|a| {
            a.iter()
                .filter_map(|g| g.as_str())
                .take(3)
                .collect::<Vec<_>>()
                .join(", ")
        })
        .unwrap_or_default();
    let cover_uri = non_empty_str(&v["cover"]["uri"])
        .or_else(|| non_empty_str(&v["ogImage"]))
        .map(str::to_string);
    let stats = format_artist_stats(&v["stats"], v["likesCount"].as_u64());
    Some(ArtistCard {
        id,
        name,
        genres,
        cover_uri,
        stats,
    })
}

fn artist_stat_parts(stats: &Value, likes_count: Option<u64>) -> Vec<String> {
    let mut parts = Vec::new();
    if let Some(m) = stats["lastMonthListeners"].as_u64().filter(|&n| n > 0) {
        parts.push(format!("{} слушателей в месяц", fmt_compact_num(m)));
    }
    if let Some(l) = likes_count
        .or_else(|| stats["likesCount"].as_u64())
        .filter(|&n| n > 0)
    {
        parts.push(format!("{} лайков", fmt_compact_num(l)));
    }
    parts
}

fn format_artist_stats(stats: &Value, likes_count: Option<u64>) -> String {
    artist_stat_parts(stats, likes_count)
        .into_iter()
        .next()
        .unwrap_or_default()
}

fn format_artist_page_stats(stats: &Value, likes_count: Option<u64>) -> String {
    artist_stat_parts(stats, likes_count).join("  •  ")
}

fn fmt_compact_num(n: u64) -> String {
    if n >= 1_000_000 {
        format!("{:.1} млн", n as f64 / 1_000_000.0).replace(".0", "")
    } else if n >= 1_000 {
        format!("{} тыс.", n / 1_000)
    } else {
        n.to_string()
    }
}

fn id_str(v: &Value) -> Option<String> {
    match v {
        Value::String(s) if !s.is_empty() => Some(s.clone()),
        Value::Number(n) => Some(n.to_string()),
        _ => None,
    }
}

fn xml_tag<'a>(xml: &'a str, tag: &str) -> Result<&'a str> {
    let open = format!("<{tag}>");
    let close = format!("</{tag}>");
    let start = xml
        .find(&open)
        .map(|i| i + open.len())
        .ok_or_else(|| anyhow!("в download-info нет <{tag}>"))?;
    let end = xml[start..]
        .find(&close)
        .ok_or_else(|| anyhow!("в download-info нет </{tag}>"))?;
    Ok(&xml[start..start + end])
}

fn random_device_id() -> String {
    const ALPHABET: &[u8] = b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    let mut x = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos() as u64)
        .unwrap_or(0x9E37_79B9_7F4A_7C15)
        ^ u64::from(std::process::id());
    (0..10)
        .map(|_| {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            ALPHABET[(x % ALPHABET.len() as u64) as usize] as char
        })
        .collect()
}

fn is_retryable_reqwest_err(e: &reqwest::Error) -> bool {
    e.is_connect() || e.is_request() || e.is_body() || e.is_decode() || e.is_timeout()
}

fn format_iso8601_utc(t: SystemTime) -> String {
    let dur = t.duration_since(UNIX_EPOCH).unwrap_or_default();
    let total_secs = dur.as_secs();
    let millis = dur.subsec_millis();
    let days = (total_secs / 86_400) as i64;
    let rem_secs = total_secs % 86_400;
    let hour = rem_secs / 3_600;
    let min = (rem_secs % 3_600) / 60;
    let sec = rem_secs % 60;

    // Howard Hinnant's civil_from_days algorithm for UTC date without external crates.
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u64;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let y = (yoe as i64) + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = y + i64::from(m <= 2);

    format!("{y:04}-{m:02}-{d:02}T{hour:02}:{min:02}:{sec:02}.{millis:03}Z")
}

fn build_rotor_feedback_body(
    batch_id: &str,
    event_type: &str,
    track_id: Option<&str>,
    total_played_seconds: Option<f64>,
    timestamp: SystemTime,
) -> Value {
    let mut event = json!({
        "type": event_type,
        "timestamp": format_iso8601_utc(timestamp),
    });
    if let Some(tid) = track_id {
        event["trackId"] = Value::String(tid.to_string());
    }
    if let Some(secs) = total_played_seconds.filter(|s| s.is_finite()) {
        event["totalPlayedSeconds"] = json!(secs.max(0.0));
    }
    let mut body = json!({ "event": event });
    if !batch_id.is_empty() {
        body["batchId"] = Value::String(batch_id.to_string());
    }
    if event_type == "radioStarted" {
        body["from"] = Value::String("ymusic".to_string());
    }
    body
}

fn sha256(data: &[u8]) -> [u8; 32] {
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ];
    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ];

    let bit_len = (data.len() as u64) * 8;
    let mut padded = data.to_vec();
    padded.push(0x80);
    while (padded.len() % 64) != 56 {
        padded.push(0);
    }
    padded.extend_from_slice(&bit_len.to_be_bytes());

    for chunk in padded.chunks_exact(64) {
        let mut w = [0u32; 64];
        for i in 0..16 {
            w[i] = u32::from_be_bytes([
                chunk[i * 4],
                chunk[i * 4 + 1],
                chunk[i * 4 + 2],
                chunk[i * 4 + 3],
            ]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16].wrapping_add(s0).wrapping_add(w[i - 7]).wrapping_add(s1);
        }
        let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut hh] = h;
        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let temp1 = hh.wrapping_add(s1).wrapping_add(ch).wrapping_add(K[i]).wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let temp2 = s0.wrapping_add(maj);
            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(temp1);
            d = c;
            c = b;
            b = a;
            a = temp1.wrapping_add(temp2);
        }
        h[0] = h[0].wrapping_add(a);
        h[1] = h[1].wrapping_add(b);
        h[2] = h[2].wrapping_add(c);
        h[3] = h[3].wrapping_add(d);
        h[4] = h[4].wrapping_add(e);
        h[5] = h[5].wrapping_add(f);
        h[6] = h[6].wrapping_add(g);
        h[7] = h[7].wrapping_add(hh);
    }

    let mut out = [0u8; 32];
    for (i, word) in h.iter().enumerate() {
        out[i * 4..i * 4 + 4].copy_from_slice(&word.to_be_bytes());
    }
    out
}

fn hmac_sha256(key: &[u8], msg: &[u8]) -> [u8; 32] {
    let mut k_block = [0u8; 64];
    if key.len() > 64 {
        let hashed = sha256(key);
        k_block[..32].copy_from_slice(&hashed);
    } else {
        k_block[..key.len()].copy_from_slice(key);
    }
    let mut i_pad = Vec::with_capacity(64 + msg.len());
    let mut o_pad = Vec::with_capacity(64 + 32);
    for b in k_block {
        i_pad.push(b ^ 0x36);
        o_pad.push(b ^ 0x5c);
    }
    i_pad.extend_from_slice(msg);
    let inner = sha256(&i_pad);
    o_pad.extend_from_slice(&inner);
    sha256(&o_pad)
}

fn base64_encode(bytes: &[u8]) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let b0 = chunk[0];
        let b1 = *chunk.get(1).unwrap_or(&0);
        let b2 = *chunk.get(2).unwrap_or(&0);
        out.push(TABLE[(b0 >> 2) as usize] as char);
        out.push(TABLE[(((b0 & 0x03) << 4) | (b1 >> 4)) as usize] as char);
        out.push(if chunk.len() > 1 {
            TABLE[(((b1 & 0x0f) << 2) | (b2 >> 6)) as usize] as char
        } else {
            '='
        });
        out.push(if chunk.len() > 2 {
            TABLE[(b2 & 0x3f) as usize] as char
        } else {
            '='
        });
    }
    out
}

fn plain_lyrics_lines(raw: &str) -> Vec<LyricsLine> {
    raw.lines()
        .map(|l| LyricsLine {
            time: None,
            end_time: None,
            text: l.trim_end().to_string(),
            words: Vec::new(),
        })
        .collect()
}

fn strip_title_suffix(title: &str) -> String {
    let trimmed = title.trim();
    if let Some((head, _)) = trimmed.split_once(" (") {
        let h = head.trim();
        if !h.is_empty() {
            return h.to_string();
        }
    }
    trimmed.to_string()
}

fn build_file_info_sign(
    ts: u64,
    track_id: &str,
    quality: &str,
    codecs: &[&str],
    transport: &str,
) -> String {
    let msg = format!("{ts}{track_id}{quality}{}{transport}", codecs.join(""));
    let mac = hmac_sha256(DESKTOP_SIGN_KEY, msg.as_bytes());
    let mut b64 = base64_encode(&mac);
    if b64.ends_with('=') {
        b64.pop();
    }
    b64
}

fn extract_lyrics_credits(r: &Value, writers: &mut String, major: &mut String) {
    if writers.is_empty() {
        if let Some(arr) = r["writers"].as_array() {
            let joined: Vec<&str> = arr.iter().filter_map(|v| v.as_str()).filter(|s| !s.is_empty()).collect();
            if !joined.is_empty() {
                *writers = joined.join(", ");
            }
        }
    }
    if major.is_empty() {
        if let Some(m) = r["major"]["prettyName"]
            .as_str()
            .or_else(|| r["major"]["name"].as_str())
            .filter(|s| !s.is_empty())
        {
            *major = m.to_string();
        }
    }
}

fn normalize_lrclib_base_url(raw: &str) -> String {
    let trimmed = raw.trim().trim_end_matches('/');
    if trimmed.starts_with("https://") || trimmed.starts_with("http://") {
        trimmed.to_string()
    } else {
        "https://lrclib.net".to_string()
    }
}

fn unquote_yaml_scalar(raw: &str) -> String {
    let s = raw.trim();
    if s.len() >= 2 && s.starts_with('\'') && s.ends_with('\'') {
        return s[1..s.len() - 1].replace("''", "'");
    }
    if s.len() >= 2 && s.starts_with('"') && s.ends_with('"') {
        let inner = &s[1..s.len() - 1];
        let mut out = String::with_capacity(inner.len());
        let mut chars = inner.chars();
        while let Some(ch) = chars.next() {
            if ch == '\\' {
                match chars.next() {
                    Some('n') => out.push('\n'),
                    Some('t') => out.push('\t'),
                    Some('r') => out.push('\r'),
                    Some('"') => out.push('"'),
                    Some('\\') => out.push('\\'),
                    Some(other) => out.push(other),
                    None => {}
                }
            } else {
                out.push(ch);
            }
        }
        return out;
    }
    s.to_string()
}

fn parse_lyricsfile_yaml(raw: &str) -> Option<(bool, Vec<LyricsLine>)> {
    #[derive(Default)]
    struct DraftWord {
        text: String,
        start_ms: Option<u64>,
        end_ms: Option<u64>,
    }
    #[derive(Default)]
    struct DraftLine {
        text: Option<String>,
        start_ms: Option<u64>,
        end_ms: Option<u64>,
        words: Vec<DraftWord>,
    }

    let mut lines: Vec<DraftLine> = Vec::new();
    let mut cur_line: Option<DraftLine> = None;
    let mut cur_word: Option<DraftWord> = None;
    let mut in_lines = false;
    let mut in_words = false;
    let mut line_indent: usize = 0;

    let flush_word = |cw: &mut Option<DraftWord>, cl: &mut Option<DraftLine>| {
        if let Some(w) = cw.take() {
            if let Some(l) = cl.as_mut() {
                l.words.push(w);
            }
        }
    };
    let flush_line = |cw: &mut Option<DraftWord>, cl: &mut Option<DraftLine>, out: &mut Vec<DraftLine>| {
        flush_word(cw, cl);
        if let Some(l) = cl.take() {
            out.push(l);
        }
    };

    for raw_line in raw.lines() {
        let indent = raw_line.chars().take_while(|c| *c == ' ').count();
        let trimmed = raw_line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        if indent == 0 {
            if trimmed == "lines:" {
                in_lines = true;
                in_words = false;
                continue;
            } else if in_lines && !trimmed.starts_with('-') {
                flush_line(&mut cur_word, &mut cur_line, &mut lines);
                in_lines = false;
                in_words = false;
                continue;
            }
        }
        if !in_lines {
            continue;
        }

        if let Some(after_dash) = trimmed.strip_prefix('-') {
            let after_dash_trimmed = after_dash.trim_start();
            let is_new_line = !in_words || indent <= line_indent;
            if is_new_line {
                flush_line(&mut cur_word, &mut cur_line, &mut lines);
                in_words = false;
                line_indent = indent;
                let mut dl = DraftLine::default();
                if let Some((k, v)) = after_dash_trimmed.split_once(':') {
                    match k.trim() {
                        "text" => dl.text = Some(unquote_yaml_scalar(v)),
                        "start_ms" => dl.start_ms = v.trim().parse().ok(),
                        "end_ms" => dl.end_ms = v.trim().parse().ok(),
                        "plain" => dl.text = Some(unquote_yaml_scalar(v)),
                        _ => {}
                    }
                }
                cur_line = Some(dl);
            } else {
                flush_word(&mut cur_word, &mut cur_line);
                let mut dw = DraftWord::default();
                if let Some((k, v)) = after_dash_trimmed.split_once(':') {
                    match k.trim() {
                        "text" => dw.text = unquote_yaml_scalar(v),
                        "start_ms" => dw.start_ms = v.trim().parse().ok(),
                        "end_ms" => dw.end_ms = v.trim().parse().ok(),
                        _ => {}
                    }
                }
                cur_word = Some(dw);
            }
            continue;
        }

        if trimmed == "words:" {
            in_words = true;
            continue;
        }

        if in_words && indent <= line_indent {
            flush_word(&mut cur_word, &mut cur_line);
            in_words = false;
        }

        if let Some((k, v)) = trimmed.split_once(':') {
            let key = k.trim();
            if in_words {
                if let Some(w) = cur_word.as_mut() {
                    match key {
                        "text" => w.text = unquote_yaml_scalar(v),
                        "start_ms" => w.start_ms = v.trim().parse().ok(),
                        "end_ms" => w.end_ms = v.trim().parse().ok(),
                        _ => {}
                    }
                }
            } else if let Some(l) = cur_line.as_mut() {
                match key {
                    "text" => l.text = Some(unquote_yaml_scalar(v)),
                    "start_ms" => l.start_ms = v.trim().parse().ok(),
                    "end_ms" => l.end_ms = v.trim().parse().ok(),
                    _ => {}
                }
            }
        }
    }
    flush_line(&mut cur_word, &mut cur_line, &mut lines);

    if lines.is_empty() {
        return None;
    }

    let mut out = Vec::with_capacity(lines.len());
    let mut any_words = false;
    for dl in lines {
        let line_end = dl.end_ms.map(|ms| ms as f64 / 1000.0);
        let mut words = Vec::with_capacity(dl.words.len());
        for i in 0..dl.words.len() {
            let w = &dl.words[i];
            let Some(start_ms) = w.start_ms else { continue };
            let start = start_ms as f64 / 1000.0;
            let next_start = dl
                .words
                .get(i + 1)
                .and_then(|nw| nw.start_ms)
                .map(|ms| ms as f64 / 1000.0);
            let mut end = w
                .end_ms
                .map(|ms| ms as f64 / 1000.0)
                .or(next_start)
                .or(line_end)
                .unwrap_or(start + 0.35);
            if end <= start {
                end = next_start.filter(|&ns| ns > start).unwrap_or(start + 0.12);
            }
            if !w.text.is_empty() {
                words.push(LyricsWord {
                    start,
                    end,
                    text: w.text.clone(),
                });
            }
        }
        normalize_word_timings(&mut words);
        if !words.is_empty() {
            any_words = true;
        }
        let line_start = dl
            .start_ms
            .map(|ms| ms as f64 / 1000.0)
            .or_else(|| words.first().map(|w| w.start));
        let text = dl.text.unwrap_or_else(|| {
            words
                .iter()
                .map(|w| w.text.as_str())
                .collect::<String>()
        });
        if line_start.is_none() && text.trim().is_empty() {
            continue;
        }
        out.push(LyricsLine {
            time: line_start,
            end_time: line_end,
            text,
            words,
        });
    }

    if out.is_empty() {
        None
    } else {
        Some((any_words, out))
    }
}

fn normalize_word_timings(words: &mut [LyricsWord]) {
    if words.is_empty() {
        return;
    }
    words[0].end = words[0].end.max(words[0].start + 0.05);
    for i in 1..words.len() {
        let prev_start = words[i - 1].start;
        let prev_end = words[i - 1].end;
        if words[i].start <= prev_start {
            words[i].start = prev_end.max(prev_start + 0.04);
        } else if words[i].start < prev_end {
            words[i - 1].end = words[i].start.max(prev_start + 0.04);
            if words[i].start < words[i - 1].end {
                words[i].start = words[i - 1].end;
            }
        }
        words[i].end = words[i].end.max(words[i].start + 0.05);
    }
}

fn extract_lrclib_entry(v: &Value) -> Option<TrackLyrics> {
    if let Some(yaml) = v["lyricsfile"].as_str().filter(|s| !s.trim().is_empty()) {
        if let Some((word_synced, lines)) = parse_lyricsfile_yaml(yaml) {
            let synced = word_synced || lines.iter().any(|l| l.time.is_some());
            if word_synced {
                return Some(TrackLyrics {
                    synced,
                    word_synced: true,
                    source: "lrclib".to_string(),
                    lines,
                    writers: String::new(),
                    major: String::new(),
                });
            }
            // Fall through to syncedLyrics check if lyricsfile had no word timings
            if synced && v["syncedLyrics"].as_str().is_none_or(|s| s.trim().is_empty()) {
                return Some(TrackLyrics {
                    synced: true,
                    word_synced: false,
                    source: "lrclib".to_string(),
                    lines,
                    writers: String::new(),
                    major: String::new(),
                });
            }
        }
    }
    if let Some(synced) = v["syncedLyrics"].as_str().filter(|s| !s.trim().is_empty()) {
        let (word_synced, lines) = parse_lrc_with_words(synced);
        if !lines.is_empty() {
            return Some(TrackLyrics {
                synced: true,
                word_synced,
                source: "lrclib".to_string(),
                lines,
                writers: String::new(),
                major: String::new(),
            });
        }
    }
    if let Some(plain) = v["plainLyrics"].as_str().filter(|s| !s.trim().is_empty()) {
        let lines = plain_lyrics_lines(plain);
        if lines.iter().any(|l| !l.text.is_empty()) {
            return Some(TrackLyrics {
                synced: false,
                word_synced: false,
                source: "lrclib".to_string(),
                lines,
                writers: String::new(),
                major: String::new(),
            });
        }
    }
    None
}

fn parse_lrc_timestamp(tag: &str) -> Option<f64> {
    let normalized = tag.replace(',', ".");
    let parts: Vec<&str> = normalized.split(':').map(str::trim).collect();
    let total = match parts.as_slice() {
        [min_s, sec_s] => {
            let mins: f64 = min_s.parse().ok()?;
            let secs: f64 = sec_s.parse().ok()?;
            mins * 60.0 + secs
        }
        [a, b, c] if !c.contains('.') && c.len() <= 2 => {
            let mins: f64 = a.parse().ok()?;
            let secs: f64 = b.parse().ok()?;
            let frac: f64 = c.parse().ok()?;
            let scale = if c.len() == 1 { 10.0 } else { 100.0 };
            mins * 60.0 + secs + frac / scale
        }
        [h_s, m_s, s_s] => {
            let hours: f64 = h_s.parse().ok()?;
            let mins: f64 = m_s.parse().ok()?;
            let secs: f64 = s_s.parse().ok()?;
            hours * 3600.0 + mins * 60.0 + secs
        }
        _ => return None,
    };
    if total.is_finite() && total >= 0.0 {
        Some(total)
    } else {
        None
    }
}

fn parse_enhanced_lrc_words(raw: &str, line_start: f64) -> (String, Vec<LyricsWord>, Option<f64>) {
    if !raw.contains('<') {
        return (raw.trim().to_string(), Vec::new(), None);
    }

    let mut clean_text = String::new();
    let mut segments: Vec<(f64, String)> = Vec::new();
    let mut current_time = line_start;
    let mut cursor = raw;
    let mut saw_tag = false;
    let mut end_time: Option<f64> = None;

    while let Some(open) = cursor.find('<') {
        let before = &cursor[..open];
        if !before.is_empty() {
            clean_text.push_str(before);
            segments.push((current_time, before.to_string()));
        }
        let after_open = &cursor[open + 1..];
        let Some(close) = after_open.find('>') else {
            clean_text.push_str(&cursor[open..]);
            segments.push((current_time, cursor[open..].to_string()));
            cursor = "";
            break;
        };
        let tag = &after_open[..close];
        if let Some(t) = parse_lrc_timestamp(tag) {
            saw_tag = true;
            current_time = t;
            end_time = Some(t);
        } else {
            let literal = &cursor[open..open + 1 + close + 1];
            clean_text.push_str(literal);
            segments.push((current_time, literal.to_string()));
        }
        cursor = &after_open[close + 1..];
    }

    if !cursor.is_empty() {
        clean_text.push_str(cursor);
        segments.push((current_time, cursor.to_string()));
    }

    if !saw_tag {
        return (raw.trim().to_string(), Vec::new(), None);
    }

    let mut words = Vec::with_capacity(segments.len());
    for i in 0..segments.len() {
        let (start, ref txt) = segments[i];
        if txt.is_empty() {
            continue;
        }
        let next_start = segments
            .get(i + 1)
            .map(|(t, _)| *t)
            .or(end_time)
            .unwrap_or(start + 0.35);
        let end = if next_start > start { next_start } else { start + 0.15 };
        words.push(LyricsWord {
            start,
            end,
            text: txt.clone(),
        });
    }
    normalize_word_timings(&mut words);

    let line_end = words
        .last()
        .map(|w| w.end)
        .filter(|e| end_time.is_some() && *e >= line_start);
    (clean_text.trim().to_string(), words, line_end)
}

fn parse_lrc_with_words(raw: &str) -> (bool, Vec<LyricsLine>) {
    let mut lines = Vec::new();
    let mut any_words = false;
    for line in raw.lines() {
        let mut rest = line.trim();
        let mut times = Vec::new();
        while rest.starts_with('[') {
            let Some(end) = rest.find(']') else { break };
            let tag = &rest[1..end];
            if let Some(t) = parse_lrc_timestamp(tag) {
                times.push(t);
            }
            rest = rest[end + 1..].trim_start();
        }
        for t in times {
            let (text, words, end_time) = parse_enhanced_lrc_words(rest, t);
            if !words.is_empty() {
                any_words = true;
            }
            lines.push(LyricsLine {
                time: Some(t),
                end_time,
                text,
                words,
            });
        }
    }
    lines.sort_by(|a, b| {
        a.time
            .unwrap_or(0.0)
            .partial_cmp(&b.time.unwrap_or(0.0))
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    (any_words, lines)
}

#[cfg(test)]
fn parse_lrc(raw: &str) -> Vec<LyricsLine> {
    parse_lrc_with_words(raw).1
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[test]
    fn formats_iso8601_utc_timestamps() {
        assert_eq!(format_iso8601_utc(UNIX_EPOCH), "1970-01-01T00:00:00.000Z");
        let t = UNIX_EPOCH + Duration::from_millis(1_700_000_000_123);
        assert_eq!(format_iso8601_utc(t), "2023-11-14T22:13:20.123Z");
        // 2024-02-29T12:34:56.789Z (leap day)
        let leap = UNIX_EPOCH + Duration::from_secs(1_709_210_096) + Duration::from_millis(789);
        assert_eq!(format_iso8601_utc(leap), "2024-02-29T12:34:56.789Z");
    }

    #[test]
    fn builds_rotor_feedback_payload_with_iso_timestamp() {
        let t = UNIX_EPOCH + Duration::from_secs(1_700_000_000);
        let skip = build_rotor_feedback_body(
            "batch-42",
            "skip",
            Some("123:456"),
            Some(12.5),
            t,
        );
        assert_eq!(skip["batchId"], "batch-42");
        assert_eq!(skip["event"]["type"], "skip");
        assert_eq!(skip["event"]["trackId"], "123:456");
        assert_eq!(skip["event"]["totalPlayedSeconds"], 12.5);
        assert_eq!(skip["event"]["timestamp"], "2023-11-14T22:13:20.000Z");
        assert!(skip.get("from").is_none());

        let started = build_rotor_feedback_body("batch-42", "radioStarted", None, None, t);
        assert_eq!(started["from"], "ymusic");
        assert_eq!(started["event"]["type"], "radioStarted");
        assert_eq!(started["event"]["timestamp"], "2023-11-14T22:13:20.000Z");
    }

    #[test]
    fn hmac_sha256_and_base64_match_known_vector() {
        let mac = hmac_sha256(b"key", b"The quick brown fox jumps over the lazy dog");
        let hex: String = mac.iter().map(|b| format!("{b:02x}")).collect();
        assert_eq!(
            hex,
            "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"
        );
        assert_eq!(base64_encode(b"foobar"), "Zm9vYmFy");
    }

    #[test]
    fn parses_lrc_with_multiple_tags_and_sorts() {
        let lrc = "[ti:Test]\n[00:25.50][00:05.00]Строка 1\n[00:12.345]Строка 2\n[01:02:25]Строка 3\n";
        let parsed = parse_lrc(lrc);
        assert_eq!(parsed.len(), 4);
        assert_eq!(parsed[0].time, Some(5.0));
        assert_eq!(parsed[0].text, "Строка 1");
        assert!((parsed[1].time.unwrap() - 12.345).abs() < 1e-6);
        assert_eq!(parsed[1].text, "Строка 2");
        assert_eq!(parsed[2].time, Some(25.5));
        assert!((parsed[3].time.unwrap() - 62.25).abs() < 1e-6);
        assert_eq!(parsed[3].text, "Строка 3");
    }

    #[test]
    fn extracts_lrclib_synced_and_strips_title_suffix() {
        assert_eq!(strip_title_suffix("Song Name (feat. Someone)"), "Song Name");
        assert_eq!(strip_title_suffix("Plain Song"), "Plain Song");

        let payload = serde_json::json!({
            "syncedLyrics": "[00:10.50] Первый куплет\n[00:15.00] Второй",
            "plainLyrics": "Первый куплет\nВторой"
        });
        let extracted = extract_lrclib_entry(&payload).expect("lyrics should parse");
        assert!(extracted.synced);
        assert_eq!(extracted.lines.len(), 2);
        assert_eq!(extracted.lines[0].time, Some(10.5));

        let plain_only = serde_json::json!({
            "syncedLyrics": "",
            "plainLyrics": "Строка без времени\n"
        });
        let extracted_plain = extract_lrclib_entry(&plain_only).expect("plain should parse");
        assert!(!extracted_plain.synced);
        assert!(!extracted_plain.word_synced);
        assert_eq!(extracted_plain.lines.len(), 1);

        let yaml_word_sync = serde_json::json!({
            "hasWordSync": true,
            "lyricsfile": "version: '1.0'\nlines:\n  - text: 'One two'\n    start_ms: 1000\n    end_ms: 2500\n    words:\n      - text: 'One '\n        start_ms: 1000\n        end_ms: 1700\n      - text: 'two'\n        start_ms: 1700\n        end_ms: 2500\n",
            "syncedLyrics": "[00:01.00] One two"
        });
        let ws = extract_lrclib_entry(&yaml_word_sync).expect("word sync should parse");
        assert!(ws.synced);
        assert!(ws.word_synced);
        assert_eq!(ws.source, "lrclib");
        assert_eq!(ws.lines.len(), 1);
        assert_eq!(ws.lines[0].words.len(), 2);
        assert_eq!(ws.lines[0].words[0].text, "One ");
        assert_eq!(ws.lines[0].words[0].start, 1.0);
        assert_eq!(ws.lines[0].words[0].end, 1.7);

        let (enh_ws, enh_lines) = parse_lrc_with_words("[00:10.00] <00:10.00> Hello <00:10.50> world <00:11.20>");
        assert!(enh_ws);
        assert_eq!(enh_lines[0].text, "Hello  world");
        assert_eq!(enh_lines[0].words.len(), 2);
        assert_eq!(enh_lines[0].words[0].start, 10.0);
        assert_eq!(enh_lines[0].words[0].end, 10.5);
        assert_eq!(enh_lines[0].words[1].end, 11.2);

        // Ensure non-monotonic / overlapping word timestamps never highlight later words out of order.
        let scrambled = serde_json::json!({
            "hasWordSync": true,
            "lyricsfile": "version: '1.0'\nlines:\n- text: trying to fly\n  start_ms: 10000\n  end_ms: 13000\n  words:\n  - text: 'trying '\n    start_ms: 10000\n    end_ms: 12000\n  - text: 'to '\n    start_ms: 11500\n    end_ms: 11800\n  - text: fly\n    start_ms: 11200\n    end_ms: 12500\n"
        });
        let fixed = extract_lrclib_entry(&scrambled).expect("scrambled should normalize");
        let w = &fixed.lines[0].words;
        assert!(w[0].end <= w[1].start);
        assert!(w[1].end <= w[2].start);
        assert!(w[0].start < w[1].start && w[1].start < w[2].start);
    }

    #[test]
    fn normalizes_composite_track_id_and_builds_file_info_sign() {
        assert_eq!(normalize_track_id("123456:7890"), "123456");
        assert_eq!(normalize_track_id("123456"), "123456");

        let sign = build_file_info_sign(
            1700000000,
            "123456",
            "lossless",
            &["flac", "flac-mp4", "aac-mp4", "mp3"],
            "raw",
        );
        assert_eq!(sign.len(), 43);
        assert!(!sign.ends_with('='));
    }

    #[test]
    fn computes_r128_gain_with_true_peak_headroom() {
        let mut t = parse_track(&serde_json::json!({
            "id": "1",
            "title": "Loud Track",
            "r128": { "i": -8.0, "tp": 0.2 },
            "lyricsInfo": { "hasAvailableSyncLyrics": true, "hasAvailableTextLyrics": true }
        }))
        .unwrap();
        assert!(t.has_sync_lyrics);
        assert!(t.has_text_lyrics);
        let gain = t.r128_gain();
        // Loud track (-8 LUFS vs -14 LUFS target => -6 dB => ~0.501)
        assert!((gain - 0.501).abs() < 0.02, "gain={gain}");

        t.r128_i = Some(-20.0);
        t.r128_tp = Some(-2.0);
        // Quiet track (-20 LUFS => +6 dB desired, but capped by TP -2.0 dB to +1.0 dB => ~1.122)
        let limited = t.r128_gain();
        assert!((limited - 1.122).abs() < 0.02, "limited={limited}");
    }

    #[test]
    fn artist_page_stats_include_monthly_listeners_and_likes() {
        let stats = serde_json::json!({
            "lastMonthListeners": 1_450_000,
            "lastMonthListenersDelta": 12_000
        });
        assert_eq!(
            format_artist_page_stats(&stats, Some(340_000)),
            "1.4 млн слушателей в месяц  •  340 тыс. лайков"
        );
        assert_eq!(
            format_artist_stats(&stats, Some(340_000)),
            "1.4 млн слушателей в месяц"
        );
        assert_eq!(
            format_artist_page_stats(&Value::Null, Some(42_000)),
            "42 тыс. лайков"
        );
    }

    #[test]
    fn cover_url_normalizes_schemes_and_track_falls_back_to_album_cover() {
        assert_eq!(
            cover_url(Some("avatars.yandex.net/get-music-content/1/2/%%"), 200).as_deref(),
            Some("https://avatars.yandex.net/get-music-content/1/2/200x200")
        );
        assert_eq!(
            cover_url(Some("https://avatars.yandex.net/get-music-content/1/2/%%"), 400).as_deref(),
            Some("https://avatars.yandex.net/get-music-content/1/2/400x400")
        );
        assert_eq!(
            cover_url(Some("//avatars.yandex.net/get-music-content/1/2/%%"), 100).as_deref(),
            Some("https://avatars.yandex.net/get-music-content/1/2/100x100")
        );

        let track = parse_track(&serde_json::json!({
            "id": 99,
            "title": "Search Track",
            "coverUri": "",
            "albums": [
                { "id": 10, "title": "Single", "coverUri": "" },
                { "id": 11, "title": "Main Album", "coverUri": "avatars.yandex.net/get-music-content/a/b/%%" }
            ]
        }))
        .unwrap();
        assert_eq!(track.cover_uri.as_deref(), Some("avatars.yandex.net/get-music-content/a/b/%%"));

        let best = parse_search_best(&serde_json::json!({
            "type": "track",
            "result": {
                "id": 77,
                "title": "Best Track",
                "albums": [{ "id": 5, "title": "LP", "coverUri": "avatars.yandex.net/x/y/%%" }]
            }
        }));
        assert!(matches!(best, Some(SearchBest::Track(t)) if t.id == "77" && t.cover_uri.is_some()));
    }
}
