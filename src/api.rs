use std::collections::HashSet;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, anyhow, bail};
use reqwest::{Client, RequestBuilder};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

const BASE: &str = "https://api.music.yandex.net";
const OAUTH: &str = "https://oauth.yandex.ru";
const CLIENT_HEADER: &str = "YandexMusicAndroid/24023621";
const SIGN_SALT: &str = "XGRlBW9FXlekgbPrRHuSiA";

// Публичные OAuth-креды Android-приложения Яндекс Музыки (как в MarshalX/yandex-music-api).
const OAUTH_CLIENT_ID: &str = "23cabbbdc6cd418abb4b39c32c41195d";
const OAUTH_CLIENT_SECRET: &str = "53bc75238f0c4d08a118e51fe9203300";

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Track {
    pub id: String,
    pub album_id: Option<String>,
    pub album_title: String,
    pub artist_id: Option<String>,
    pub title: String,
    pub artists: String,
    pub duration_ms: u64,
    pub cover_uri: Option<String>,
    pub available: bool,
}

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
}

pub fn cover_url(uri: Option<&str>, size: u32) -> Option<String> {
    uri.filter(|s| !s.is_empty())
        .map(|u| format!("https://{}", u.replace("%%", &format!("{size}x{size}"))))
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
}

#[derive(Clone, Debug, Default)]
pub struct SearchResults {
    pub tracks: Vec<Track>,
    pub albums: Vec<AlbumCard>,
    pub artists: Vec<ArtistCard>,
    pub playlists: Vec<PlaylistCard>,
}

#[derive(Clone, Debug)]
pub struct RotorSession {
    pub session_id: String,
    pub batch_id: String,
    pub tracks: Vec<Track>,
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

    async fn result(rb: RequestBuilder) -> Result<Value> {
        let resp = rb.send().await.context("нет соединения с сервером")?;
        let status = resp.status();
        let text = resp.text().await?;
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
                .auth(self.http.get("https://login.yandex.ru/info?format=json"))
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
        let mut out = Vec::with_capacity(ids.len());
        for chunk in ids.chunks(250) {
            let joined = chunk.join(",");
            let r = self
                .post_form("/tracks", &[("track-ids", &joined), ("with-positions", "false")])
                .await?;
            if let Some(items) = r.as_array() {
                out.extend(items.iter().filter_map(parse_track));
            }
        }
        Ok(out)
    }

    pub async fn search_all(&self, text: &str) -> Result<SearchResults> {
        let r = self
            .get(
                "/search",
                &[
                    ("text", text),
                    ("type", "all"),
                    ("page", "0"),
                    ("nocorrect", "false"),
                ],
            )
            .await?;
        let tracks = r["tracks"]["results"]
            .as_array()
            .map(|a| a.iter().filter_map(parse_track).collect())
            .unwrap_or_default();
        let albums = r["albums"]["results"]
            .as_array()
            .map(|a| a.iter().filter_map(parse_album).collect())
            .unwrap_or_default();
        let artists = r["artists"]["results"]
            .as_array()
            .map(|a| a.iter().filter_map(parse_artist).collect())
            .unwrap_or_default();
        let playlists = r["playlists"]["results"]
            .as_array()
            .map(|a| a.iter().filter_map(parse_playlist).collect())
            .unwrap_or_default();
        Ok(SearchResults {
            tracks,
            albums,
            artists,
            playlists,
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
        let mut parsed = Vec::with_capacity(items.len());
        let mut missing_ids = Vec::new();
        for item in items {
            if let Some(t) = item.get("track").and_then(parse_track) {
                parsed.push(t);
            } else if let Some(t) = parse_track(item) {
                parsed.push(t);
            } else if let Some(id) = id_str(&item["id"]) {
                let full = match id_str(&item["albumId"]) {
                    Some(a) => format!("{id}:{a}"),
                    None => id,
                };
                missing_ids.push(full);
            }
        }
        if !missing_ids.is_empty() {
            parsed.extend(self.tracks(&missing_ids).await?);
        }
        Ok(parsed)
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
        if artist.stats.is_empty() {
            artist.stats = format_artist_stats(&r["stats"], r["artist"]["likesCount"].as_u64());
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
        Ok(ArtistPage {
            artist,
            popular_tracks,
            albums,
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

    /// Догружает следующую партию треков для активной сессии волны.
    pub async fn rotor_session_tracks(
        &self,
        session_id: &str,
        queue: &[String],
    ) -> Result<(String, Vec<Track>)> {
        let body = json!({ "queue": queue });
        let r = self
            .post_json(&format!("/rotor/session/{session_id}/tracks"), &body)
            .await?;
        let batch_id = r["batchId"].as_str().unwrap_or_default().to_string();
        let tracks = parse_rotor_sequence(&r["sequence"]);
        Ok((batch_id, tracks))
    }

    pub async fn rotor_feedback(
        &self,
        session_id: &str,
        batch_id: &str,
        event_type: &str,
        track_id: Option<&str>,
        total_played_seconds: Option<f64>,
    ) {
        let ts = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs_f64())
            .unwrap_or(0.0);
        let mut event = json!({
            "type": event_type,
            "timestamp": ts,
        });
        if let Some(tid) = track_id {
            event["trackId"] = Value::String(tid.to_string());
        }
        if let Some(secs) = total_played_seconds {
            event["totalPlayedSeconds"] = json!(secs);
        }
        let mut body = json!({ "event": event });
        if !batch_id.is_empty() {
            body["batchId"] = Value::String(batch_id.to_string());
        }
        if event_type == "radioStarted" {
            body["from"] = Value::String("ymusic".to_string());
        }
        let _ = self
            .post_json(&format!("/rotor/session/{session_id}/feedback"), &body)
            .await;
    }

    /// Получает прямую подписанную ссылку на MP3 (лучший битрейт, 320 kbps).
    pub async fn track_direct_url(&self, track_id: &str) -> Result<String> {
        let r = self.get(&format!("/tracks/{track_id}/download-info"), &[]).await?;
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

        let xml = self
            .auth(self.http.get(info_url))
            .send()
            .await?
            .error_for_status()?
            .text()
            .await?;
        let host = xml_tag(&xml, "host")?;
        let path = xml_tag(&xml, "path")?;
        let ts = xml_tag(&xml, "ts")?;
        let s = xml_tag(&xml, "s")?;
        let sign = md5::compute(format!("{SIGN_SALT}{}{s}", path.get(1..).unwrap_or("")));
        Ok(format!("https://{host}/get-mp3/{sign:x}/{ts}{path}"))
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

fn parse_track(v: &Value) -> Option<Track> {
    let id = id_str(&v["id"])?;
    let mut title = v["title"].as_str().unwrap_or("Без названия").to_string();
    if let Some(version) = v["version"].as_str().filter(|s| !s.is_empty()) {
        title = format!("{title} ({version})");
    }
    let artists_arr = v["artists"].as_array();
    let artist_id = artists_arr
        .and_then(|a| a.first())
        .and_then(|x| id_str(&x["id"]));
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
    Some(Track {
        id,
        album_id,
        album_title,
        artist_id,
        title,
        artists,
        duration_ms: v["durationMs"].as_u64().unwrap_or(0),
        cover_uri: v["coverUri"]
            .as_str()
            .or(album["coverUri"].as_str())
            .or(v["ogImage"].as_str())
            .map(str::to_string),
        available: v["available"].as_bool().unwrap_or(true),
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
    let cover_uri = v["cover"]["uri"]
        .as_str()
        .or_else(|| {
            v["cover"]["itemsUri"]
                .as_array()
                .and_then(|a| a.first())
                .and_then(|u| u.as_str())
        })
        .or(v["ogImage"].as_str())
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
    let cover_uri = v["coverUri"]
        .as_str()
        .or(v["ogImage"].as_str())
        .map(str::to_string);
    Some(AlbumCard {
        id,
        title,
        artists,
        year,
        track_count,
        cover_uri,
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
    let cover_uri = v["cover"]["uri"]
        .as_str()
        .or(v["ogImage"].as_str())
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

fn format_artist_stats(stats: &Value, likes_count: Option<u64>) -> String {
    if let Some(m) = stats["lastMonthListeners"].as_u64().filter(|&n| n > 0) {
        return format!("{} слушателей в месяц", fmt_compact_num(m));
    }
    if let Some(l) = likes_count.or_else(|| stats["likesCount"].as_u64()).filter(|&n| n > 0) {
        return format!("{} лайков", fmt_compact_num(l));
    }
    String::new()
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
