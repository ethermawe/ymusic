use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use serde::{Deserialize, Serialize};
use tokio::runtime::Handle;
use tokio::sync::Semaphore;

use crate::api::{self, AlbumCard, Api, ArtistCard, Track};
use crate::audio::{Audio, Event, SourceData};
use crate::cache;
use crate::config;
use crate::discord::Discord;
use crate::mpris::{Action as MprisAction, Meta as MprisMeta, Mpris, Status as MprisStatus};

pub const EVENT_LOGIN_STATUS: i32 = 1;
pub const EVENT_LOGIN_DEVICE_CODE: i32 = 2;
pub const EVENT_NOW_PLAYING: i32 = 3;
pub const EVENT_PLAYBACK_PROGRESS: i32 = 4;
pub const EVENT_PLAYBACK_STATE: i32 = 5;
pub const EVENT_TRACKS_LOADED: i32 = 6;
pub const EVENT_CARDS_LOADED: i32 = 7;
pub const EVENT_VIEW_HEADER: i32 = 8;
pub const EVENT_STATUS_MSG: i32 = 9;
pub const EVENT_QUEUE_LOADED: i32 = 10;
pub const EVENT_PLAYLIST_PICKER: i32 = 11;
pub const EVENT_FEATURE: i32 = 12;

pub trait EventSink: Send + Sync {
    fn on_event(&self, event_type: i32, json_data: &str);
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct TrackItemPayload {
    pub id: String,
    pub title: String,
    pub artists: String,
    pub album: String,
    pub duration: String,
    pub duration_ms: u64,
    pub available: bool,
    pub downloaded: bool,
    pub liked: bool,
    pub cover_url: String,
    pub has_cover: bool,
    pub has_artist: bool,
    pub has_album: bool,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct CardItemPayload {
    pub title: String,
    pub subtitle: String,
    pub kind: String,
    pub cover_url: String,
    pub has_cover: bool,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct LoginStatusPayload {
    pub logged_in: bool,
    pub busy: bool,
    pub user_name: String,
    pub user_avatar: String,
    pub user_has_avatar: bool,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct DeviceCodePayload {
    pub user_code: String,
    pub verification_url: String,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct NowPlayingPayload {
    pub has_track: bool,
    pub id: String,
    pub title: String,
    pub artists: String,
    pub album: String,
    pub cover_url: String,
    pub has_cover: bool,
    pub duration_ms: u64,
    pub duration_text: String,
    pub liked: bool,
    pub has_artist: bool,
    pub has_album: bool,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct PlaybackProgressPayload {
    pub position_secs: f64,
    pub duration_secs: f64,
    pub position_text: String,
    pub duration_text: String,
    pub progress: f32,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct PlaybackStatePayload {
    pub playing: bool,
    pub buffering: bool,
    pub volume: f32,
    pub shuffle: bool,
    pub repeat_mode: i32,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct TracksPayload {
    pub tracks: Vec<TrackItemPayload>,
    pub current_index: i32,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct CardsPayload {
    pub cards: Vec<CardItemPayload>,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct ViewHeaderPayload {
    pub cover_url: String,
    pub page: i32,
    pub title: String,
    pub subtitle: String,
    pub loading: bool,
    pub is_artist_view: bool,
    pub artist_name: String,
    pub artist_genres: String,
    pub artist_stats: String,
    pub artist_avatar: String,
    pub artist_has_avatar: bool,
    pub can_start_artist_wave: bool,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct StatusPayload {
    pub text: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum CardTarget {
    Playlist {
        uid: u64,
        kind: u64,
        title: String,
        #[serde(default)]
        cover_uri: Option<String>,
    },
    Album(AlbumCard),
    Artist(ArtistCard),
}

impl CardTarget {
    pub fn cover_uri(&self) -> Option<&str> {
        match self {
            CardTarget::Playlist { cover_uri, .. } => cover_uri.as_deref(),
            CardTarget::Album(a) => a.cover_uri.as_deref(),
            CardTarget::Artist(ar) => ar.cover_uri.as_deref(),
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ArtistViewInfo {
    pub id: String,
    pub name: String,
    pub genres: String,
    pub stats: String,
    pub cover_uri: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CachedView {
    #[serde(default)]
    pub cover_uri: Option<String>,
    pub title: String,
    pub subtitle: String,
    pub cards: Vec<CardTarget>,
    pub tracks: Vec<Track>,
    pub viewed_artist_id: Option<(String, String)>,
    #[serde(default)]
    pub artist_view: Option<ArtistViewInfo>,
}

#[derive(Clone, Debug)]
pub struct WaveState {
    pub seed: String,
    pub title: String,
    pub session_id: String,
    pub batch_id: String,
    pub tracks: Vec<Track>,
    pub fetching_more: bool,
    pub resume_on_load: bool,
}

#[derive(Default)]
pub struct State {
    pub wave_groups: Vec<crate::wave::Group>,
    pub wave_selected: HashMap<String, String>,
    pub search_query: String,
    pub search_filter: String,
    pub collection_downloadable: bool,
    pub history_generation: Option<u64>,
    pub view_cover_uri: Option<String>,
    pub api: Option<Api>,
    pub uid: u64,
    pub liked_ids: HashSet<String>,
    pub cards: Vec<CardTarget>,
    pub viewed_artist_id: Option<(String, String)>,
    pub viewed_artist: Option<ArtistViewInfo>,
    pub list: Vec<Track>,
    pub queue: Vec<Track>,
    pub current: Option<usize>,
    pub duration_secs: f64,
    pub position_secs: f64,
    pub wave: Option<WaveState>,
    pub views: HashMap<String, CachedView>,
    pub generation: u64,
    pub view_id: u64,
    pub page: i32,
    pub audio_started: bool,
    pub last_saved_sec: u64,
    pub repeat_mode: u8,
    pub shuffle: bool,
    pub unshuffled_queue: Option<Vec<Track>>,
    pub last_unmuted_volume: f32,
    pub last_seek_time: Option<std::time::Instant>,
    pub seek_target_secs: f64,
    pub playing: bool,
    pub volume: f32,
    /// Позиция, на которую надо перемотать после старта трека (восстановленная сессия).
    pub resume_at: Option<f64>,
}

pub struct YMusicCore {
    pub batch_running: AtomicBool,
    pub batch_cancel: AtomicBool,
    pub batch_cancel_tx: tokio::sync::watch::Sender<bool>,
    pub playlist_creating: AtomicBool,
    pub rt_handle: Handle,
    pub runtime: Option<tokio::runtime::Runtime>,
    pub http: reqwest::Client,
    pub state: Arc<Mutex<State>>,
    pub cover_sem: Arc<Semaphore>,
    pub audio: Audio,
    pub mpris: Mpris,
    pub discord: Discord,
    pub sink: Arc<dyn EventSink>,
}

pub fn fmt_time(secs: f64) -> String {
    let s = secs.max(0.0) as u64;
    if s >= 3600 {
        format!("{}:{:02}:{:02}", s / 3600, s / 60 % 60, s % 60)
    } else {
        format!("{}:{:02}", s / 60, s % 60)
    }
}

pub fn perceptual(v: f32) -> f32 {
    v.clamp(0.0, 1.0).powi(2)
}

pub fn shuffle_slice<T>(slice: &mut [T]) {
    use std::time::SystemTime;
    let mut rng = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .map(|d| d.as_nanos() as u64)
        .unwrap_or(123456789);
    for i in (1..slice.len()).rev() {
        rng ^= rng << 13;
        rng ^= rng >> 7;
        rng ^= rng << 17;
        let j = (rng as usize) % (i + 1);
        slice.swap(i, j);
    }
}

fn playlist_target(p: api::PlaylistCard) -> CardTarget {
    CardTarget::Playlist {
        uid: p.uid,
        kind: p.kind,
        title: format!("{} ({})", p.title, p.subtitle),
        cover_uri: p.cover_uri,
    }
}

fn card_payload(c: &CardTarget) -> CardItemPayload {
    match c {
        CardTarget::Playlist { title, cover_uri, .. } => CardItemPayload {
            title: title.clone(),
            subtitle: "Плейлист".to_string(),
            kind: "playlist".to_string(),
            cover_url: api::cover_url(cover_uri.as_deref(), 200).unwrap_or_default(),
            has_cover: cover_uri.is_some(),
        },
        CardTarget::Album(a) => {
            let mut parts = vec!["Альбом".to_string()];
            if !a.artists.is_empty() {
                parts.push(a.artists.clone());
            }
            if let Some(y) = a.year {
                parts.push(y.to_string());
            }
            if a.track_count > 0 {
                parts.push(format!("{} тр.", a.track_count));
            }
            CardItemPayload {
                title: a.title.clone(),
                subtitle: parts.join(" • "),
                kind: "album".to_string(),
                cover_url: api::cover_url(a.cover_uri.as_deref(), 200).unwrap_or_default(),
                has_cover: a.cover_uri.is_some(),
            }
        }
        CardTarget::Artist(ar) => {
            let sub = if !ar.stats.is_empty() {
                if !ar.genres.is_empty() {
                    format!("{} • {}", ar.genres, ar.stats)
                } else {
                    ar.stats.clone()
                }
            } else if ar.genres.is_empty() {
                "Исполнитель".to_string()
            } else {
                format!("Исполнитель • {}", ar.genres)
            };
            CardItemPayload {
                title: ar.name.clone(),
                subtitle: sub,
                kind: "artist".to_string(),
                cover_url: api::cover_url(ar.cover_uri.as_deref(), 200).unwrap_or_default(),
                has_cover: ar.cover_uri.is_some(),
            }
        }
    }
}

fn track_payload(t: &Track, liked_ids: &HashSet<String>) -> TrackItemPayload {
    let cover_url = t.cover_url(200).unwrap_or_default();
    TrackItemPayload {
        id: t.id.clone(),
        title: t.title.clone(),
        artists: t.artists.clone(),
        album: t.album_title.clone(),
        duration: fmt_time(t.duration_ms as f64 / 1000.0),
        duration_ms: t.duration_ms,
        available: t.available || cache::is_offline(&t.id),
        downloaded: cache::is_offline(&t.id),
        liked: liked_ids.contains(&t.id),
        has_cover: !cover_url.is_empty(),
        cover_url,
        has_artist: t.artist_id.is_some(),
        has_album: t.album_id.is_some(),
    }
}

fn current_track(st: &State) -> Option<&Track> {
    st.current.and_then(|i| st.queue.get(i))
}

fn current_list_index(st: &State) -> i32 {
    let Some(cur) = current_track(st) else { return -1 };
    st.list
        .iter()
        .position(|t| t.id == cur.id)
        .map_or(-1, |i| i as i32)
}

fn enqueue_in_state(st: &mut State, track: Track, next: bool) {
    let at = if next { st.current.map_or(0, |i| i + 1) } else { st.queue.len() };
    st.queue.insert(at, track.clone());
    if st.current.is_none() {
        st.current = Some(0);
        st.audio_started = false;
    }
    if let Some(original) = &mut st.unshuffled_queue {
        // Preserve "play next" ordering when shuffle is subsequently disabled.
        let at = if next {
            st.current.and_then(|i| st.queue.get(i))
                .and_then(|current| original.iter().position(|t| t.id == current.id))
                .map_or(original.len(), |i| i + 1)
        } else { original.len() };
        original.insert(at, track);
    }
}

fn edit_queue_state(st: &mut State, op: &str, index: usize, id: Option<&str>) -> bool {
    if op == "clear" {
        let current = current_track(st).cloned();
        st.queue = current.into_iter().collect();
        st.current = (!st.queue.is_empty()).then_some(0);
    } else if index < st.queue.len() && id == Some(st.queue[index].id.as_str()) {
        if op == "remove" {
            if st.current == Some(index) { return false; }
            st.queue.remove(index);
            if let Some(cur) = st.current { if index < cur { st.current = Some(cur - 1); } }
        } else if op == "up" || op == "down" {
            let target = if op == "up" { index.checked_sub(1) } else { index.checked_add(1).filter(|&i| i < st.queue.len()) };
            let Some(target) = target else { return false };
            st.queue.swap(index, target);
            if st.current == Some(index) { st.current = Some(target); }
            else if st.current == Some(target) { st.current = Some(index); }
        } else { return false; }
    } else { return false; }
    st.wave = None;
    st.unshuffled_queue = None;
    true
}

#[cfg(test)]
mod queue_tests {
    use super::*;

    fn track(id: &str) -> Track {
        Track {
            id: id.into(), title: id.into(), artists: String::new(),
            album_id: None, album_title: String::new(), artist_id: None,
            duration_ms: 1000, cover_uri: None, available: true,
        }
    }

    #[test]
    fn next_preserves_current_and_updates_shuffle_backup() {
        let original = vec![track("a"), track("b"), track("c")];
        let mut st = State {
            queue: original.clone(), current: Some(0),
            unshuffled_queue: Some(original), ..State::default()
        };
        enqueue_in_state(&mut st, track("next"), true);
        assert_eq!(st.current, Some(0));
        assert_eq!(st.queue[1].id, "next");
        assert_eq!(st.unshuffled_queue.as_ref().unwrap()[1].id, "next");
        enqueue_in_state(&mut st, track("last"), false);
        assert_eq!(st.queue.last().unwrap().id, "last");
    }

    #[test]
    fn empty_queue_is_ready_for_play_without_autostart() {
        let mut st = State::default();
        enqueue_in_state(&mut st, track("first"), false);
        assert_eq!(st.current, Some(0));
        assert!(!st.audio_started);
        assert_eq!(st.queue[0].id, "first");
    }

    #[test]
    fn edits_preserve_playing_track_and_reject_stale_rows() {
        let mut st = State { queue: vec![track("a"), track("b"), track("c")], current: Some(1), ..State::default() };
        assert!(!edit_queue_state(&mut st, "remove", 1, Some("b")));
        assert!(!edit_queue_state(&mut st, "remove", 0, Some("c")));
        assert!(edit_queue_state(&mut st, "up", 1, Some("b")));
        assert_eq!(current_track(&st).unwrap().id, "b");
        assert_eq!(st.current, Some(0));
        assert!(edit_queue_state(&mut st, "remove", 1, Some("a")));
        assert!(edit_queue_state(&mut st, "clear", 0, None));
        assert_eq!(st.queue.len(), 1);
        assert_eq!(current_track(&st).unwrap().id, "b");
    }
}

impl YMusicCore {
    pub fn send_feature(&self, kind: &str, mut data: serde_json::Value) {
        data["type"] = kind.into();
        self.send_event(EVENT_FEATURE, &data);
    }

    fn send_history_tracks(&self, tracks: Vec<Track>) {
        let st = self.state.lock().unwrap();
        let payload: Vec<_> = tracks.iter().map(|t| track_payload(t, &st.liked_ids)).collect();
        drop(st);
        self.send_feature("history", serde_json::json!({"tracks": payload}));
    }

    pub fn feature_command(self: Arc<Self>, cmd: serde_json::Value) {
        match cmd["action"].as_str().unwrap_or("") {
            "wave_settings" => self.load_wave_settings(),
            "wave_apply" => {
                let Ok(selections) = serde_json::from_value::<HashMap<String, String>>(cmd["selected"].clone()) else {
                    self.send_feature("wave_error", serde_json::json!({"message": "Некорректные настройки волны"}));
                    return;
                };
                let validated = {
                    let st = self.state.lock().unwrap();
                    crate::wave::validate(&st.wave_groups, &selections)
                };
                match validated {
                    Ok(seeds) => self.start_wave_filtered("user:onyourwave".into(), "Моя волна".into(), seeds, Some(selections)),
                    Err(e) => self.send_feature("wave_error", serde_json::json!({"message": e.to_string()})),
                }
            }
            "history" => self.send_history_tracks(crate::history::load()),
            "clear_history" => {
                if crate::history::clear().is_ok() { self.send_history_tracks(Vec::new()); }
                else { self.error("Не удалось очистить историю"); }
            }
            "play_history" => {
                let tracks = crate::history::load();
                let Some(id) = cmd["id"].as_str() else { return };
                let Some(index) = tracks.iter().position(|t| t.id == id) else { return };
                {
                    let mut st = self.state.lock().unwrap();
                    st.queue = tracks;
                    st.wave = None;
                    st.unshuffled_queue = None;
                }
                self.play_index(index, true);
            }
            "search" => self.search_with_filter(cmd["query"].as_str().unwrap_or("").trim().into(), cmd["filter"].as_str().unwrap_or("all").into()),
            "create_playlist" => {
                let Some(api) = self.api() else { self.error("Для создания плейлиста нужен вход"); return };
                if self.playlist_creating.swap(true, Ordering::SeqCst) { return; }
                let uid = self.state.lock().unwrap().uid;
                let title = cmd["title"].as_str().unwrap_or("").to_string();
                let private = cmd["private"].as_bool().unwrap_or(true);
                let this = self.clone();
                self.rt_handle.spawn(async move {
                    let result = api.create_playlist(uid, &title, private).await;
                    this.playlist_creating.store(false, Ordering::SeqCst);
                    if this.state.lock().unwrap().uid != uid { return; }
                    match result {
                        Ok(p) => {
                            this.send_feature("create_playlist", serde_json::json!({"ok": true, "title": p.title}));
                            let page = this.state.lock().unwrap().page;
                            if page == 3 { this.clone().load_playlists(); }
                            else if page == 0 { this.clone().load_home(); }
                        }
                        Err(e) => this.send_feature("create_playlist", serde_json::json!({"ok": false, "message": e.to_string()})),
                    }
                });
            }
            "download_collection" => self.download_collection(),
            "cancel_download" => {
                self.batch_cancel.store(true, Ordering::SeqCst);
                self.batch_cancel_tx.send_replace(true);
            }
            "queue" => self.edit_queue(&cmd),
            _ => (),
        }
    }

    fn edit_queue(&self, cmd: &serde_json::Value) {
        let op = cmd["operation"].as_str().unwrap_or("");
        let index = cmd["index"].as_u64().unwrap_or(u64::MAX) as usize;
        let mut st = self.state.lock().unwrap();
        if !edit_queue_state(&mut st, op, index, cmd["id"].as_str()) { return; }
        drop(st);
        self.send_queue();
        self.refresh_rows();
        self.persist_session();
    }

    pub fn download_collection(self: Arc<Self>) {
        let Some(api) = self.api() else { self.error("Для загрузки нужен вход"); return };
        let (tracks, title, uid) = {
            let st = self.state.lock().unwrap();
            if !st.collection_downloadable || st.list.is_empty() { return; }
            (st.list.clone(), "Загрузка коллекции".to_string(), st.uid)
        };
        if self.batch_running.swap(true, Ordering::SeqCst) { self.error("Уже идёт загрузка коллекции"); return; }
        self.batch_cancel.store(false, Ordering::SeqCst);
        self.batch_cancel_tx.send_replace(false);
        let mut cancel = self.batch_cancel_tx.subscribe();
        let this = self.clone();
        self.rt_handle.spawn(async move {
            let total = tracks.len();
            let mut done = 0;
            let mut failed = 0;
            for track in tracks {
                if this.batch_cancel.load(Ordering::SeqCst) || this.state.lock().unwrap().uid != uid { break; }
                this.send_feature("batch", serde_json::json!({"running": true, "done": done, "total": total, "failed": failed, "title": track.title}));
                let download = async {
                    if !cache::is_offline(&track.id) {
                        anyhow::ensure!(track.available, "трек недоступен");
                        let url = api.track_direct_url(&track.id).await?;
                        let path = cache::offline_track_path(&track.id).ok_or_else(|| anyhow::anyhow!("нет каталога данных"))?;
                        cache::download_to_file(api.http(), &url, &path).await?;
                    }
                    let metadata = track.clone();
                    tokio::task::spawn_blocking(move || cache::save_offline_metadata(&metadata)).await??;
                    Ok::<(), anyhow::Error>(())
                };
                let result = tokio::select! {
                    biased;
                    _ = cancel.changed() => break,
                    result = download => result,
                };
                if result.is_err() { failed += 1; }
                done += 1;
            }
            this.batch_running.store(false, Ordering::SeqCst);
            let cancelled = done < total;
            this.send_feature("batch", serde_json::json!({"running": false, "done": done, "total": total, "failed": failed, "cancelled": cancelled, "title": title}));
            this.refresh_rows();
            let showing_downloads = this.state.lock().unwrap().page == 7;
            if showing_downloads { this.clone().load_downloads(); }
            this.error(format!("{}: {done}/{total}, ошибок: {failed}", if cancelled { "Загрузка остановлена" } else { "Загрузка завершена" }));
        });
    }

    pub fn new(sink: Arc<dyn EventSink>) -> Arc<Self> {
        if std::env::var("MIMALLOC_PURGE_DELAY").is_err() {
            unsafe { std::env::set_var("MIMALLOC_PURGE_DELAY", "0"); }
        }

        let runtime = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .expect("Failed to build Tokio runtime for YMusicCore");
        let rt_handle = runtime.handle().clone();

        let core = Arc::new_cyclic(|me: &std::sync::Weak<YMusicCore>| {
            let me_audio = me.clone();
            let me_mpris = me.clone();
            YMusicCore {
                batch_running: AtomicBool::new(false),
                batch_cancel: AtomicBool::new(false),
                batch_cancel_tx: tokio::sync::watch::channel(false).0,
                playlist_creating: AtomicBool::new(false),
                rt_handle: rt_handle.clone(),
                runtime: Some(runtime),
                http: api::http_client(),
                state: Arc::new(Mutex::new(State::default())),
                cover_sem: Arc::new(Semaphore::new(8)),
                audio: Audio::spawn(move |event| {
                    if let Some(c) = me_audio.upgrade() {
                        c.on_audio(event);
                    }
                }),
                mpris: Mpris::spawn(&rt_handle, move |action| {
                    if let Some(c) = me_mpris.upgrade() {
                        c.on_mpris(action);
                    }
                }),
                discord: Discord::spawn(),
                sink,
            }
        });

        let settings = config::load_settings();
        let initial_vol = settings.volume;
        core.audio.set_volume(perceptual(initial_vol));
        core.mpris.set_volume(initial_vol);
        {
            let mut st = core.state.lock().unwrap();
            st.repeat_mode = settings.repeat_mode;
            st.shuffle = settings.shuffle;
            st.last_unmuted_volume = if initial_vol > 0.001 { initial_vol } else { 0.7 };
            st.volume = initial_vol;
        }

        core.send_playback_state(false);

        // Downloads remain usable while the network login is being checked.
        if cache::offline_tracks().is_ok_and(|(tracks, _)| !tracks.is_empty()) {
            core.clone().load_downloads();
        }

        if let Some(token) = config::load_token() {
            core.clone().login(token);
        } else {
            core.send_event(EVENT_LOGIN_STATUS, &LoginStatusPayload {
                logged_in: false,
                busy: false,
                user_name: String::new(),
                user_avatar: String::new(),
                user_has_avatar: false,
            });
        }

        core
    }

    pub fn shutdown(&self) {
        self.persist_session();
        self.audio.stop();
        self.discord.set_stopped();
    }

    pub fn send_event(&self, event_type: i32, payload: &impl Serialize) {
        if let Ok(json) = serde_json::to_string(payload) {
            self.sink.on_event(event_type, &json);
        }
    }

    pub fn send_playback_state(&self, buffering: bool) {
        let payload = {
            let st = self.state.lock().unwrap();
            PlaybackStatePayload {
                playing: st.playing,
                buffering,
                volume: st.volume,
                shuffle: st.shuffle,
                repeat_mode: st.repeat_mode as i32,
            }
        };
        self.send_event(EVENT_PLAYBACK_STATE, &payload);
    }

    pub fn set_playing(&self, playing: bool, buffering: bool) {
        self.state.lock().unwrap().playing = playing;
        self.send_playback_state(buffering);
    }

    pub fn error(&self, msg: impl Into<String>) {
        self.send_event(EVENT_STATUS_MSG, &StatusPayload {
            text: msg.into(),
        });
    }

    pub fn api(&self) -> Option<Api> {
        self.state.lock().unwrap().api.clone()
    }

    pub fn generation(&self) -> u64 {
        self.state.lock().unwrap().generation
    }

    pub fn login_device(self: Arc<Self>) {
        self.send_event(EVENT_LOGIN_STATUS, &LoginStatusPayload {
            logged_in: false,
            busy: true,
            user_name: String::new(),
            user_avatar: String::new(),
            user_has_avatar: false,
        });

        let this = self.clone();
        self.rt_handle.spawn(async move {
            let code = match api::request_device_code(&this.http).await {
                Ok(c) => c,
                Err(e) => {
                    this.error(format!("Вход: {e}"));
                    this.send_event(EVENT_LOGIN_STATUS, &LoginStatusPayload {
                        logged_in: false,
                        busy: false,
                        user_name: String::new(),
                        user_avatar: String::new(),
                        user_has_avatar: false,
                    });
                    return;
                }
            };

            this.send_event(EVENT_LOGIN_DEVICE_CODE, &DeviceCodePayload {
                user_code: code.user_code.clone(),
                verification_url: code.verification_url.clone(),
            });

            let deadline = tokio::time::Instant::now() + Duration::from_secs(code.expires_in);
            let result = loop {
                tokio::time::sleep(Duration::from_secs(code.interval.max(1))).await;
                if tokio::time::Instant::now() > deadline {
                    break Err(anyhow::anyhow!("время на подтверждение истекло"));
                }
                match api::poll_device_token(&this.http, &code.device_code).await {
                    Ok(Some(token)) => break Ok(token),
                    Ok(None) => continue,
                    Err(e) => break Err(e),
                }
            };

            match result {
                Ok(token) => this.login(token),
                Err(e) => {
                    this.send_event(EVENT_LOGIN_STATUS, &LoginStatusPayload {
                        logged_in: false,
                        busy: false,
                        user_name: String::new(),
                        user_avatar: String::new(),
                        user_has_avatar: false,
                    });
                    this.error(format!("Вход: {e}"));
                }
            }
        });
    }

    pub fn login(self: Arc<Self>, token: String) {
        if token.is_empty() {
            return;
        }
        self.send_event(EVENT_LOGIN_STATUS, &LoginStatusPayload {
            logged_in: false,
            busy: true,
            user_name: String::new(),
            user_avatar: String::new(),
            user_has_avatar: false,
        });
        let this = self.clone();
        self.rt_handle.spawn(async move {
            let api = Api::new(this.http.clone(), token.clone());
            match api.account().await {
                Ok(account) => {
                    if let Err(e) = config::save_token(&token) {
                        this.error(format!("Не удалось сохранить токен: {e}"));
                    }
                    {
                        let mut st = this.state.lock().unwrap();
                        st.api = Some(api);
                        st.uid = account.uid;
                    }
                    let avatar = account.avatar_url.clone().unwrap_or_default();
                    let has_avatar = !avatar.is_empty();
                    this.send_event(EVENT_LOGIN_STATUS, &LoginStatusPayload {
                        logged_in: true,
                        busy: false,
                        user_name: account.name,
                        user_avatar: avatar,
                        user_has_avatar: has_avatar,
                    });

                    let browsing_downloads = this.state.lock().unwrap().page == 7;
                    if !browsing_downloads { this.clone().load_home(); }
                    this.clone().prefetch_likes();
                    if !browsing_downloads { this.clone().restore_session(); }
                }
                Err(e) => {
                    this.send_event(EVENT_LOGIN_STATUS, &LoginStatusPayload {
                        logged_in: false,
                        busy: false,
                        user_name: String::new(),
                        user_avatar: String::new(),
                        user_has_avatar: false,
                    });
                    this.error(format!("Не удалось войти: {e}"));
                }
            }
        });
    }

    pub fn logout(&self) {
        self.batch_cancel.store(true, Ordering::SeqCst);
        self.batch_cancel_tx.send_replace(true);
        config::clear_token();
        self.clear_saved_session();
        {
            let mut st = self.state.lock().unwrap();
            *st = State {
                generation: st.generation + 1,
                view_id: st.view_id + 1,
                volume: st.volume,
                last_unmuted_volume: st.last_unmuted_volume,
                shuffle: st.shuffle,
                repeat_mode: st.repeat_mode,
                ..State::default()
            };
        }
        self.audio.stop();
        self.mpris.set_stopped();
        self.discord.set_stopped();
        self.send_playback_state(false);
        self.send_queue();

        self.send_event(EVENT_LOGIN_STATUS, &LoginStatusPayload {
            logged_in: false,
            busy: false,
            user_name: String::new(),
            user_avatar: String::new(),
            user_has_avatar: false,
        });
        self.send_event(EVENT_NOW_PLAYING, &NowPlayingPayload {
            has_track: false,
            id: String::new(),
            title: String::new(),
            artists: String::new(),
            album: String::new(),
            cover_url: String::new(),
            has_cover: false,
            duration_ms: 0,
            duration_text: "0:00".into(),
            liked: false,
            has_artist: false,
            has_album: false,
        });
        self.send_event(EVENT_TRACKS_LOADED, &TracksPayload {
            tracks: Vec::new(),
            current_index: -1,
        });
        self.send_event(EVENT_CARDS_LOADED, &CardsPayload {
            cards: Vec::new(),
        });
    }

    pub fn view_cover_url(&self) -> String {
        let st = self.state.lock().unwrap();
        api::cover_url(st.view_cover_uri.as_deref(), 400)
            .or_else(|| st.list.iter().find_map(|t| t.cover_url(400)))
            .unwrap_or_default()
    }

    pub fn begin_cached_view(&self, key: Option<&str>, page: i32, title: String, subtitle: String) -> u64 {
        let is_artist = key.is_some_and(|k| k.starts_with("artist:"));
        let (view, has_cache, eff_title, eff_subtitle, cards_payload, tracks_payload, current_idx, can_wave, artist_info) = {
            let mut st = self.state.lock().unwrap();
            st.view_id += 1;
            st.page = page;
            st.collection_downloadable = key.is_some_and(|k| k.starts_with("album:") || k.starts_with("playlist:"));
            let view = st.view_id;

            let cached = key.and_then(|k| {
                if let Some(c) = st.views.get(k).cloned() {
                    return Some(c);
                }
                let loaded = cache::load_view::<CachedView>(k)?;
                st.views.insert(k.to_string(), loaded.clone());
                Some(loaded)
            });

            if let Some(c) = cached {
                st.view_cover_uri = c.cover_uri.clone();
                if key == Some("likes") && st.liked_ids.is_empty() {
                    st.liked_ids = c.tracks.iter().map(|t| t.id.clone()).collect();
                }
                let tracks_p: Vec<TrackItemPayload> = c
                    .tracks
                    .iter()
                    .map(|t| track_payload(t, &st.liked_ids))
                    .collect();
                let cards_p: Vec<CardItemPayload> = c.cards.iter().map(card_payload).collect();
                let can_wave = c.viewed_artist_id.is_some();
                st.cards = c.cards;
                st.list = c.tracks;
                st.viewed_artist_id = c.viewed_artist_id;
                st.viewed_artist = c.artist_view.clone();
                let cur = current_list_index(&st);
                (view, true, c.title, c.subtitle, cards_p, tracks_p, cur, can_wave, c.artist_view)
            } else {
                st.view_cover_uri = None;
                st.cards.clear();
                st.list.clear();
                st.viewed_artist_id = None;
                st.viewed_artist = None;
                (view, false, title, subtitle, Vec::new(), Vec::new(), -1, false, None)
            }
        };

        let artist_info_val = artist_info.unwrap_or_default();
        let artist_avatar = artist_info_val.cover_uri.as_deref().and_then(|u| api::cover_url(Some(u), 300)).unwrap_or_default();
        let artist_has_avatar = !artist_avatar.is_empty();

        self.send_event(EVENT_VIEW_HEADER, &ViewHeaderPayload {
            cover_url: self.view_cover_url(),
            page,
            title: eff_title,
            subtitle: eff_subtitle,
            loading: !has_cache,
            is_artist_view: is_artist || !artist_info_val.name.is_empty(),
            artist_name: artist_info_val.name,
            artist_genres: artist_info_val.genres,
            artist_stats: artist_info_val.stats,
            artist_avatar,
            artist_has_avatar,
            can_start_artist_wave: can_wave,
        });

        self.send_event(EVENT_CARDS_LOADED, &CardsPayload { cards: cards_payload });
        self.send_event(EVENT_TRACKS_LOADED, &TracksPayload { tracks: tracks_payload, current_index: current_idx });

        self.send_feature("view", serde_json::json!({"downloadable": self.state.lock().unwrap().collection_downloadable}));
        view
    }

    pub fn apply_cached_view(
        &self,
        view: u64,
        key: Option<&str>,
        title: Option<String>,
        subtitle: Option<String>,
        cards: Vec<CardTarget>,
        tracks: Vec<Track>,
        viewed_artist_id: Option<(String, String)>,
        artist_view: Option<ArtistViewInfo>,
    ) -> bool {
        if let Some(k) = key {
            let mut st = self.state.lock().unwrap();
            let prev = st.views.get(k);
            let cached = CachedView {
                cover_uri: if st.view_id == view { st.view_cover_uri.clone() } else { prev.and_then(|p| p.cover_uri.clone()) },
                title: title.clone().or_else(|| prev.map(|p| p.title.clone())).unwrap_or_default(),
                subtitle: subtitle.clone().or_else(|| prev.map(|p| p.subtitle.clone())).unwrap_or_default(),
                cards: cards.clone(),
                tracks: tracks.clone(),
                viewed_artist_id: viewed_artist_id.clone(),
                artist_view: artist_view.clone().or_else(|| prev.and_then(|p| p.artist_view.clone())),
            };
            st.views.insert(k.to_string(), cached.clone());
            drop(st);
            cache::save_view(k, &cached);
        }

        let can_wave = viewed_artist_id.is_some();
        let (tracks_p, cards_p, current_idx, current_page) = {
            let mut st = self.state.lock().unwrap();
            if st.view_id != view {
                return false;
            }
            st.cards = cards.clone();
            st.viewed_artist_id = viewed_artist_id;
            st.viewed_artist = artist_view.clone();
            let tracks_p: Vec<TrackItemPayload> = tracks
                .iter()
                .map(|t| track_payload(t, &st.liked_ids))
                .collect();
            let cards_p: Vec<CardItemPayload> = cards.iter().map(card_payload).collect();
            st.list = tracks;
            (tracks_p, cards_p, current_list_index(&st), st.page)
        };

        let artist_info_val = artist_view.unwrap_or_default();
        let artist_avatar = artist_info_val.cover_uri.as_deref().and_then(|u| api::cover_url(Some(u), 300)).unwrap_or_default();
        let artist_has_avatar = !artist_avatar.is_empty();

        if let (Some(t), Some(s)) = (title, subtitle) {
            self.send_event(EVENT_VIEW_HEADER, &ViewHeaderPayload {
                cover_url: self.view_cover_url(),
                page: current_page,
                title: t,
                subtitle: s,
                loading: false,
                is_artist_view: !artist_info_val.name.is_empty(),
                artist_name: artist_info_val.name,
                artist_genres: artist_info_val.genres,
                artist_stats: artist_info_val.stats,
                artist_avatar,
                artist_has_avatar,
                can_start_artist_wave: can_wave,
            });
        }

        self.send_event(EVENT_CARDS_LOADED, &CardsPayload { cards: cards_p });
        self.send_event(EVENT_TRACKS_LOADED, &TracksPayload { tracks: tracks_p, current_index: current_idx });

        true
    }

    pub fn view_failed(&self, view: u64, what: &str, e: anyhow::Error) {
        let is_current = self.state.lock().unwrap().view_id == view;
        if is_current {
            self.error(format!("{what}: {e:#}"));
        }
    }

    pub fn refresh_rows(&self) {
        self.send_queue();
        let (tracks_p, now_liked, current_idx) = {
            let st = self.state.lock().unwrap();
            let tracks_p: Vec<TrackItemPayload> = st
                .list
                .iter()
                .map(|t| track_payload(t, &st.liked_ids))
                .collect();
            let now_liked = current_track(&st).is_some_and(|t| st.liked_ids.contains(&t.id));
            (tracks_p, now_liked, current_list_index(&st))
        };

        self.send_event(EVENT_TRACKS_LOADED, &TracksPayload {
            tracks: tracks_p,
            current_index: current_idx,
        });

        let st = self.state.lock().unwrap();
        if let Some(t) = current_track(&st) {
            let cover_url = t.cover_url(200).unwrap_or_default();
            self.send_event(EVENT_NOW_PLAYING, &NowPlayingPayload {
                has_track: true,
                id: t.id.clone(),
                title: t.title.clone(),
                artists: t.artists.clone(),
                album: t.album_title.clone(),
                has_cover: !cover_url.is_empty(),
                cover_url,
                duration_ms: t.duration_ms,
                duration_text: fmt_time(t.duration_ms as f64 / 1000.0),
                liked: now_liked,
                has_artist: t.artist_id.is_some(),
                has_album: t.album_id.is_some(),
            });
        }
    }

    pub fn prefetch_likes(self: Arc<Self>) {
        let Some(api) = self.api() else { return };
        let uid = self.state.lock().unwrap().uid;
        let this = self.clone();
        self.rt_handle.spawn(async move {
            if let Ok(entries) = api.liked_track_entries(uid).await {
                let set: HashSet<String> = entries.into_iter().map(|(id, _)| id).collect();
                this.state.lock().unwrap().liked_ids = set;
                this.refresh_rows();
            }
        });
    }

    pub fn load_home(self: Arc<Self>) {
        let Some(api) = self.api() else {
            let view = self.begin_cached_view(None, 0, "Главная".into(), String::new());
            self.apply_cached_view(view, None, Some("Главная".into()), Some(String::new()), Vec::new(), Vec::new(), None, None);
            return;
        };
        let uid = self.state.lock().unwrap().uid;
        let view = self.begin_cached_view(
            Some("home"),
            0,
            "Главная".into(),
            "Ваша музыка и рекомендации".into(),
        );
        let this = self.clone();
        self.rt_handle.spawn(async move {
            let playlists_res = api.user_playlists(uid).await;
            let albums_res = api.liked_albums(uid).await;

            let mut cards = Vec::new();
            if let Ok(playlists) = playlists_res {
                for p in playlists.into_iter().take(6) {
                    cards.push(playlist_target(p));
                }
            }
            if let Ok(albums) = albums_res {
                for a in albums.into_iter().take(6) {
                    cards.push(CardTarget::Album(a));
                }
            }

            this.apply_cached_view(
                view,
                Some("home"),
                Some("Главная".into()),
                Some("Ваша музыка и рекомендации".into()),
                cards,
                Vec::new(),
                None,
                None,
            );
        });
    }

    pub fn load_downloads(self: Arc<Self>) {
        let view = self.begin_cached_view(None, 7, "Загружено".into(), "Читаем загрузки…".into());
        let this = self.clone();
        self.rt_handle.spawn(async move {
            let reader = this.clone();
            match tokio::task::spawn_blocking(move || {
                let known = {
                    let st = reader.state.lock().unwrap();
                    st.list.iter().chain(st.queue.iter()).cloned().collect::<Vec<_>>()
                };
                cache::recover_offline_metadata(&known);
                cache::offline_tracks()
            }).await {
                Ok(Ok((tracks, bytes))) => {
                    let subtitle = format!("{} тр. • {:.1} МБ • На этом устройстве", tracks.len(), bytes as f64 / 1048576.0);
                    this.apply_cached_view(view, None, Some("Загружено".into()), Some(subtitle), Vec::new(), tracks, None, None);
                }
                _ => {
                    this.apply_cached_view(view, None, Some("Загружено".into()), Some("Не удалось прочитать загрузки".into()), Vec::new(), Vec::new(), None, None);
                    this.error("Не удалось прочитать папку загрузок");
                }
            }
        });
    }

    pub fn remove_download(self: Arc<Self>, id: String) {
        let this = self.clone();
        self.rt_handle.spawn(async move {
            match tokio::task::spawn_blocking(move || cache::remove_offline(&id)).await {
                Ok(Ok(())) => {
                    this.refresh_rows();
                    let showing_downloads = this.state.lock().unwrap().page == 7;
                    if showing_downloads { this.clone().load_downloads(); }
                    this.error("Загрузка удалена с устройства");
                }
                _ => this.error("Не удалось удалить загрузку"),
            }
        });
    }

    pub fn playlist_choices(self: Arc<Self>, id: String) {
        let Some(api) = self.api() else { return };
        let uid = self.state.lock().unwrap().uid;
        let this = self.clone();
        self.rt_handle.spawn(async move {
            let result = api.own_playlists(uid).await;
            if this.state.lock().unwrap().uid != uid { return; }
            match result {
                Ok(playlists) => this.send_event(EVENT_PLAYLIST_PICKER, &serde_json::json!({
                    "id": id, "stage": "loaded", "playlists": playlists.iter().map(|p|
                        serde_json::json!({"kind": p.kind.to_string(), "title": p.title,
                            "subtitle": p.subtitle,
                            "cover_url": api::cover_url(p.cover_uri.as_deref(), 100).unwrap_or_default()})).collect::<Vec<_>>()
                })),
                Err(e) => this.send_event(EVENT_PLAYLIST_PICKER, &serde_json::json!({"id": id, "stage": "error", "message": e.to_string()})),
            }
        });
    }

    pub fn add_to_playlist(self: Arc<Self>, id: String, kind: u64) {
        let Some(api) = self.api() else { return };
        let Some(track) = self.find_track(&id) else {
            self.send_event(EVENT_PLAYLIST_PICKER, &serde_json::json!({"id": id, "stage": "error", "message": "Трек больше не найден. Откройте меню заново."}));
            return;
        };
        let uid = self.state.lock().unwrap().uid;
        let this = self.clone();
        self.rt_handle.spawn(async move {
            let result = api.insert_playlist_track(uid, kind, &track).await;
            if this.state.lock().unwrap().uid != uid { return; }
            match result {
                Ok(()) => {
                    // Invalidate only this playlist; never replace the page the user navigated to.
                    let key = format!("playlist:{uid}:{kind}");
                    this.state.lock().unwrap().views.remove(&key);
                    cache::remove_view(&key);
                    this.send_event(EVENT_PLAYLIST_PICKER, &serde_json::json!({"id": id, "stage": "done"}));
                    this.error(format!("«{}» добавлен в плейлист", track.title));
                }
                Err(e) => this.send_event(EVENT_PLAYLIST_PICKER, &serde_json::json!({"id": id, "stage": "error", "message": format!("Не удалось добавить трек: {e}. Обновите список и повторите.")})),
            }
        });
    }

    pub fn load_likes(self: Arc<Self>) {
        let Some(api) = self.api() else { return };
        let uid = self.state.lock().unwrap().uid;
        let view = self.begin_cached_view(Some("likes"), 2, "Мне нравится".into(), "".into());
        let this = self.clone();
        self.rt_handle.spawn(async move {
            match api.liked_tracks(uid).await {
                Ok((liked_set, tracks)) => {
                    this.state.lock().unwrap().liked_ids = liked_set;
                    this.apply_cached_view(
                        view,
                        Some("likes"),
                        Some("Мне нравится".into()),
                        Some("".into()),
                        Vec::new(),
                        tracks,
                        None,
                        None,
                    );
                    this.refresh_rows();
                }
                Err(e) => this.view_failed(view, "Не удалось загрузить лайки", e),
            }
        });
    }

    pub fn open_or_start_wave(self: Arc<Self>, seed: String, title: String) {
        let existing = {
            let mut st = self.state.lock().unwrap();
            if let Some(w) = st.wave.as_ref().filter(|w| w.seed == seed && !w.tracks.is_empty()) {
                let tracks = w.tracks.clone();
                let w_title = w.title.clone();
                st.view_id += 1;
                st.page = 1;
                st.collection_downloadable = false;
                st.view_cover_uri = None;
                let view = st.view_id;
                st.cards.clear();
                st.viewed_artist_id = None;
                st.viewed_artist = None;
                let tracks_p: Vec<TrackItemPayload> = tracks
                    .iter()
                    .map(|t| track_payload(t, &st.liked_ids))
                    .collect();
                st.list = tracks;
                let cur = current_list_index(&st);
                Some((view, w_title, tracks_p, cur))
            } else {
                None
            }
        };

        if let Some((_view, w_title, tracks_p, cur)) = existing {
            self.send_feature("view", serde_json::json!({"downloadable": false}));
            self.send_event(EVENT_VIEW_HEADER, &ViewHeaderPayload {
                cover_url: self.view_cover_url(),
                page: 1,
                title: w_title,
                subtitle: "Персональный поток рекомендаций".into(),
                loading: false,
                is_artist_view: false,
                artist_name: String::new(),
                artist_genres: String::new(),
                artist_stats: String::new(),
                artist_avatar: String::new(),
                artist_has_avatar: false,
                can_start_artist_wave: false,
            });
            self.send_event(EVENT_CARDS_LOADED, &CardsPayload { cards: Vec::new() });
            self.send_event(EVENT_TRACKS_LOADED, &TracksPayload { tracks: tracks_p, current_index: cur });
            return;
        }

        self.start_wave(seed, title);
    }

    pub fn start_wave(self: Arc<Self>, seed: String, title: String) {
        let mut seeds: Vec<String> = if seed == "user:onyourwave" {
            self.state.lock().unwrap().wave_selected.values().cloned().collect()
        } else { Vec::new() };
        seeds.sort();
        self.start_wave_filtered(seed, title, seeds, None);
    }

    pub fn load_wave_settings(self: Arc<Self>) {
        let Some(api) = self.api() else { return };
        let uid = self.state.lock().unwrap().uid;
        let this = self.clone();
        self.rt_handle.spawn(async move {
            let result = api.wave_settings().await;
            if this.state.lock().unwrap().uid != uid { return; }
            match result {
                Ok(response) => {
                    let groups = crate::wave::groups(&response);
                    let selected = {
                        let mut st = this.state.lock().unwrap();
                        if st.uid != uid { return; }
                        st.wave_groups = groups.clone();
                        st.wave_selected.retain(|key, seed| groups.iter().any(|g|
                            &g.key == key && g.choices.iter().any(|c| &c.seed == seed)));
                        st.wave_selected.clone()
                    };
                    this.send_feature("wave_settings", serde_json::json!({"groups": groups, "selected": selected}));
                }
                Err(e) => this.send_feature("wave_error", serde_json::json!({"message": format!("Не удалось получить фильтры: {e}")})),
            }
        });
    }

    pub fn start_wave_filtered(self: Arc<Self>, seed: String, title: String, filters: Vec<String>, selected: Option<HashMap<String, String>>) {
        let Some(api) = self.api() else { return };
        let cache_key = format!("wave:{seed}:{}", filters.join(","));
        let view = self.begin_cached_view(
            Some(&cache_key),
            1,
            title.clone(),
            "Персональный поток рекомендаций".into(),
        );
        let this = self.clone();
        self.rt_handle.spawn(async move {
            let seeds: Vec<&str> = std::iter::once(seed.as_str()).chain(filters.iter().map(String::as_str)).collect();
            let session = match api.rotor_session_new(&seeds).await {
                Ok(s) => s,
                Err(e) => {
                    this.send_feature("wave_error", serde_json::json!({"message": format!("Не удалось запустить волну: {e}")}));
                    return this.view_failed(view, "Моя волна", e);
                }
            };
            if session.tracks.is_empty() {
                this.send_feature("wave_error", serde_json::json!({"message": "Волна не вернула треков. Попробуйте другие фильтры."}));
                return this.view_failed(view, "Моя волна", anyhow::anyhow!("волна не вернула треков"));
            }
            {
                let mut st = this.state.lock().unwrap();
                if st.view_id != view {
                    return;
                }
                st.wave = Some(WaveState {
                    seed: seed.clone(),
                    title: title.clone(),
                    session_id: session.session_id.clone(),
                    batch_id: session.batch_id.clone(),
                    tracks: session.tracks.clone(),
                    fetching_more: false,
                    resume_on_load: false,
                });
                if let Some(selected) = selected { st.wave_selected = selected; }
                st.unshuffled_queue = None;
                st.queue = session.tracks.clone();
                st.current = None;
            }
            let (sid, bid) = (session.session_id.clone(), session.batch_id.clone());
            let api_fb = api.clone();
            tokio::spawn(async move {
                api_fb.rotor_feedback(&sid, &bid, "radioStarted", None, None).await;
            });
            this.apply_cached_view(
                view,
                Some(&cache_key),
                Some(title),
                Some("Персональный поток рекомендаций".into()),
                Vec::new(),
                session.tracks,
                None,
                None,
            );
            this.clone().play_index(0, false);
            let selected = this.state.lock().unwrap().wave_selected.clone();
            this.send_feature("wave_applied", serde_json::json!({"selected": selected}));
        });
    }

    pub fn load_playlists(self: Arc<Self>) {
        let Some(api) = self.api() else { return };
        let uid = self.state.lock().unwrap().uid;
        let view = self.begin_cached_view(
            Some("playlists"),
            3,
            "Плейлисты".into(),
            "Ваши и понравившиеся плейлисты".into(),
        );
        let this = self.clone();
        self.rt_handle.spawn(async move {
            match api.user_playlists(uid).await {
                Ok(list) => {
                    let cards = list.into_iter().map(playlist_target).collect();
                    this.apply_cached_view(
                        view,
                        Some("playlists"),
                        Some("Плейлисты".into()),
                        Some("Ваши и понравившиеся плейлисты".into()),
                        cards,
                        Vec::new(),
                        None,
                        None,
                    );
                }
                Err(e) => this.view_failed(view, "Плейлисты", e),
            }
        });
    }

    pub fn load_albums(self: Arc<Self>) {
        let Some(api) = self.api() else { return };
        let uid = self.state.lock().unwrap().uid;
        let view = self.begin_cached_view(
            Some("albums"),
            4,
            "Альбомы".into(),
            "Понравившиеся альбомы".into(),
        );
        let this = self.clone();
        self.rt_handle.spawn(async move {
            match api.liked_albums(uid).await {
                Ok(list) => {
                    let cards = list.into_iter().map(CardTarget::Album).collect();
                    this.apply_cached_view(
                        view,
                        Some("albums"),
                        Some("Альбомы".into()),
                        Some("Понравившиеся альбомы".into()),
                        cards,
                        Vec::new(),
                        None,
                        None,
                    );
                }
                Err(e) => this.view_failed(view, "Альбомы", e),
            }
        });
    }

    pub fn load_artists(self: Arc<Self>) {
        let Some(api) = self.api() else { return };
        let uid = self.state.lock().unwrap().uid;
        let view = self.begin_cached_view(
            Some("artists"),
            5,
            "Артисты".into(),
            "Любимые исполнители".into(),
        );
        let this = self.clone();
        self.rt_handle.spawn(async move {
            match api.liked_artists(uid).await {
                Ok(list) => {
                    let cards = list.into_iter().map(CardTarget::Artist).collect();
                    this.apply_cached_view(
                        view,
                        Some("artists"),
                        Some("Артисты".into()),
                        Some("Любимые исполнители".into()),
                        cards,
                        Vec::new(),
                        None,
                        None,
                    );
                }
                Err(e) => this.view_failed(view, "Артисты", e),
            }
        });
    }

    pub fn search(self: Arc<Self>, query: String) {
        self.search_with_filter(query, "all".into());
    }

    pub fn search_with_filter(self: Arc<Self>, query: String, filter: String) {
        if query.is_empty() {
            return;
        }
        if !["all", "track", "album", "artist", "playlist"].contains(&filter.as_str()) { return; }
        let Some(api) = self.api() else { return };
        {
            let mut st = self.state.lock().unwrap();
            st.search_query = query.clone();
            st.search_filter = filter.clone();
        }
        self.send_feature("search", serde_json::json!({"query": query, "filter": filter}));
        let key = format!("search:{filter}:{}", query.to_lowercase());
        let title = format!("Поиск: {query}");
        let view = self.begin_cached_view(
            Some(&key),
            8,
            title.clone(),
            "Артисты, альбомы, плейлисты и треки".into(),
        );
        let this = self.clone();
        self.rt_handle.spawn(async move {
            match api.search_filtered(&query, &filter).await {
                Ok(res) => {
                    let mut cards = Vec::new();
                    cards.extend(res.artists.into_iter().map(CardTarget::Artist));
                    cards.extend(res.albums.into_iter().map(CardTarget::Album));
                    cards.extend(res.playlists.into_iter().map(playlist_target));
                    this.apply_cached_view(
                        view,
                        Some(&key),
                        Some(title),
                        Some("Артисты, альбомы, плейлисты и треки".into()),
                        cards,
                        res.tracks,
                        None,
                        None,
                    );
                }
                Err(e) => this.view_failed(view, "Поиск", e),
            }
        });
    }

    pub fn open_card(self: Arc<Self>, index: usize) {
        let target = self.state.lock().unwrap().cards.get(index).cloned();
        let Some(target) = target else { return };
        match target {
            CardTarget::Playlist { uid, kind, title, .. } => self.open_playlist(uid, kind, title),
            CardTarget::Album(album) => self.open_album(album.id),
            CardTarget::Artist(artist) => self.open_artist(artist.id),
        }
    }

    pub fn open_playlist(self: Arc<Self>, owner_uid: u64, kind: u64, title: String) {
        let Some(api) = self.api() else { return };
        let cover = {
            let st = self.state.lock().unwrap();
            st.cards.iter().find_map(|card| match card {
                CardTarget::Playlist { uid, kind: card_kind, cover_uri, .. } if *uid == owner_uid && *card_kind == kind => cover_uri.clone(),
                _ => None,
            })
        };
        let key = format!("playlist:{owner_uid}:{kind}");
        let view = self.begin_cached_view(Some(&key), 6, title.clone(), "Плейлист".into());
        if cover.is_some() { self.state.lock().unwrap().view_cover_uri = cover; }
        let this = self.clone();
        self.rt_handle.spawn(async move {
            match api.playlist_tracks(owner_uid, kind).await {
                Ok(tracks) => {
                    this.apply_cached_view(
                        view,
                        Some(&key),
                        Some(title),
                        Some("Плейлист".into()),
                        Vec::new(),
                        tracks,
                        None,
                        None,
                    );
                }
                Err(e) => this.view_failed(view, "Плейлист", e),
            }
        });
    }

    pub fn open_album(self: Arc<Self>, album_id: String) {
        let Some(api) = self.api() else { return };
        let key = format!("album:{album_id}");
        let view = self.begin_cached_view(Some(&key), 6, "Альбом…".into(), "".into());
        let this = self.clone();
        self.rt_handle.spawn(async move {
            match api.album_with_tracks(&album_id).await {
                Ok((album, tracks)) => {
                    let sub = match album.year {
                        Some(y) if !album.artists.is_empty() => format!("{} • {y}", album.artists),
                        Some(y) => y.to_string(),
                        None => album.artists.clone(),
                    };
                    let title = album.title.clone();
                    {
                        let mut st = this.state.lock().unwrap();
                        if st.view_id == view { st.view_cover_uri = album.cover_uri.clone(); }
                    }
                    this.apply_cached_view(
                        view,
                        Some(&key),
                        Some(title),
                        Some(sub),
                        Vec::new(),
                        tracks,
                        None,
                        None,
                    );
                }
                Err(e) => this.view_failed(view, "Альбом", e),
            }
        });
    }

    pub fn open_artist(self: Arc<Self>, artist_id: String) {
        let Some(api) = self.api() else { return };
        let key = format!("artist:{artist_id}");
        let view = self.begin_cached_view(Some(&key), 6, "Артист…".into(), "".into());
        let this = self.clone();
        self.rt_handle.spawn(async move {
            match api.artist_brief(&artist_id).await {
                Ok(page) => {
                    let name = page.artist.name.clone();
                    let genres = if page.artist.genres.is_empty() {
                        "Популярные треки и дискография".to_string()
                    } else {
                        page.artist.genres.clone()
                    };
                    let cards = page.albums.into_iter().map(CardTarget::Album).collect();
                    let artist_meta = Some((page.artist.id.clone(), name.clone()));
                    let artist_view = Some(ArtistViewInfo {
                        id: page.artist.id.clone(),
                        name: name.clone(),
                        genres: genres.clone(),
                        stats: page.artist.stats.clone(),
                        cover_uri: page.artist.cover_uri.clone(),
                    });
                    this.apply_cached_view(
                        view,
                        Some(&key),
                        Some(name),
                        Some(genres),
                        cards,
                        page.popular_tracks,
                        artist_meta,
                        artist_view,
                    );
                }
                Err(e) => this.view_failed(view, "Артист", e),
            }
        });
    }

    pub fn toggle_like_at(self: Arc<Self>, index: usize) {
        let track = self.state.lock().unwrap().list.get(index).cloned();
        if let Some(t) = track {
            self.toggle_like_track(t);
        }
    }

    /// Resolve a stable track identity, not a row number that may have changed.
    pub fn find_track(&self, id: &str) -> Option<Track> {
        let st = self.state.lock().unwrap();
        st.list.iter().chain(st.queue.iter())
            .chain(st.views.values().flat_map(|view| view.tracks.iter()))
            .find(|t| t.id == id).cloned()
    }

    pub fn enqueue_track(&self, track: Track, next: bool) {
        {
            let mut st = self.state.lock().unwrap();
            enqueue_in_state(&mut st, track, next);
        }
        self.persist_session();
        self.send_queue();
        self.error(if next { "Трек будет играть следующим" } else { "Трек добавлен в очередь" });
    }

    pub fn repeat_track(self: Arc<Self>, track: Track) {
        let index = {
            let mut st = self.state.lock().unwrap();
            st.wave = None;
            st.repeat_mode = 2;
            let at = st.current.map_or(st.queue.len(), |i| i + 1);
            st.queue.insert(at, track.clone());
            if let Some(original) = &mut st.unshuffled_queue {
                original.push(track);
            }
            at
        };
        config::update_settings(|s| s.repeat_mode = 2);
        self.play_index(index, true);
    }

    pub fn send_queue(&self) {
        let payload = {
            let st = self.state.lock().unwrap();
            TracksPayload {
                tracks: st.queue.iter().map(|t| track_payload(t, &st.liked_ids)).collect(),
                current_index: st.current.map_or(-1, |i| i as i32),
            }
        };
        self.send_event(EVENT_QUEUE_LOADED, &payload);
    }

    pub fn download_track(self: Arc<Self>, track: Track, destination: Option<std::path::PathBuf>) {
        if !track.available {
            self.error("Этот трек недоступен для скачивания");
            return;
        }
        let Some(api) = self.api() else { return };
        self.error(format!("Скачиваем «{}»…", track.title));
        let this = self.clone();
        self.rt_handle.spawn(async move {
            let offline = destination.is_none();
            let result: anyhow::Result<()> = async {
                let path = destination.or_else(|| cache::offline_track_path(&track.id))
                    .ok_or_else(|| anyhow::anyhow!("нет каталога данных"))?;
                let url = api.track_direct_url(&track.id).await?;
                cache::download_to_file(api.http(), &url, &path).await?;
                if offline {
                    let metadata = track.clone();
                    tokio::task::spawn_blocking(move || cache::save_offline_metadata(&metadata)).await??;
                }
                Ok(())
            }.await;
            match result {
                Ok(()) => {
                    this.refresh_rows();
                    let showing_downloads = this.state.lock().unwrap().page == 7;
                    if showing_downloads { this.clone().load_downloads(); }
                    this.error(format!("«{}» сохранён", track.title));
                }
                Err(e) => this.error(format!("Не удалось скачать «{}»: {e}", track.title)),
            }
        });
    }

    pub fn toggle_now_like(self: Arc<Self>) {
        let track = current_track(&self.state.lock().unwrap()).cloned();
        if let Some(t) = track {
            self.toggle_like_track(t);
        }
    }

    pub fn update_likes_cache(&self, track: &Track, add: bool) {
        let mut st = self.state.lock().unwrap();
        let Some(cached) = st.views.get_mut("likes") else { return };
        if add {
            if !cached.tracks.iter().any(|t| t.id == track.id) {
                cached.tracks.insert(0, track.clone());
            }
        } else {
            cached.tracks.retain(|t| t.id != track.id);
        }
        let snapshot = cached.clone();
        drop(st);
        cache::save_view("likes", &snapshot);
    }

    pub fn toggle_like_track(self: Arc<Self>, track: Track) {
        let (api, uid, add, wave) = {
            let mut st = self.state.lock().unwrap();
            let Some(api) = st.api.clone() else { return };
            let add = !st.liked_ids.contains(&track.id);
            if add {
                st.liked_ids.insert(track.id.clone());
            } else {
                st.liked_ids.remove(&track.id);
            }
            (api, st.uid, add, st.wave.clone())
        };
        self.update_likes_cache(&track, add);
        self.refresh_rows();
        let this = self.clone();
        self.rt_handle.spawn(async move {
            let res = if add {
                api.like_track(uid, &track.id).await
            } else {
                api.unlike_track(uid, &track.id).await
            };
            if let Err(e) = res {
                {
                    let mut st = this.state.lock().unwrap();
                    if add {
                        st.liked_ids.remove(&track.id);
                    } else {
                        st.liked_ids.insert(track.id.clone());
                    }
                }
                this.update_likes_cache(&track, !add);
                this.refresh_rows();
                this.error(format!("Лайк: {e:#}"));
                return;
            }
            if let Some(w) = wave {
                let ev = if add { "like" } else { "unlike" };
                api.rotor_feedback(&w.session_id, &w.batch_id, ev, Some(&track.composite_id()), None)
                    .await;
            }
        });
    }

    pub fn dislike_now(self: Arc<Self>) {
        let (api, uid, track, played, wave, was_liked) = {
            let mut st = self.state.lock().unwrap();
            let Some(api) = st.api.clone() else { return };
            let Some(track) = current_track(&st).cloned() else { return };
            let was_liked = st.liked_ids.remove(&track.id);
            (api, st.uid, track, st.position_secs, st.wave.clone(), was_liked)
        };
        if was_liked {
            self.update_likes_cache(&track, false);
        }
        self.refresh_rows();
        let this = self.clone();
        self.rt_handle.spawn(async move {
            if let Err(e) = api.dislike_track(uid, &track.id).await {
                if was_liked {
                    this.state.lock().unwrap().liked_ids.insert(track.id.clone());
                    this.update_likes_cache(&track, true);
                    this.refresh_rows();
                }
                this.error(format!("Дизлайк: {e:#}"));
                return;
            }
            if let Some(w) = wave {
                api.rotor_feedback(
                    &w.session_id,
                    &w.batch_id,
                    "dislike",
                    Some(&track.composite_id()),
                    Some(played),
                )
                .await;
            }
        });
        self.step(1, true);
    }

    pub fn step(self: Arc<Self>, delta: isize, manual_skip: bool) {
        let (next, repeat_mode, queue_len) = {
            let st = self.state.lock().unwrap();
            let Some(cur) = st.current else { return };
            let mut i = cur;
            let found = loop {
                match i.checked_add_signed(delta).filter(|&n| n < st.queue.len()) {
                    Some(n) if st.queue[n].available => break Some(n),
                    Some(n) => i = n,
                    None => break None,
                }
            };
            (found, st.repeat_mode, st.queue.len())
        };
        match next {
            Some(i) => self.play_index(i, manual_skip),
            None => {
                if delta > 0 && queue_len > 0 {
                    if repeat_mode == 1 {
                        self.play_index(0, manual_skip);
                    } else if !manual_skip {
                        self.finish_queue();
                    }
                }
            }
        }
    }

    pub fn finish_queue(&self) {
        let waiting_for_wave = {
            let mut st = self.state.lock().unwrap();
            let waiting = st.wave.as_ref().is_some_and(|w| w.fetching_more);
            if waiting && let Some(w) = &mut st.wave {
                w.resume_on_load = true;
            }
            waiting
        };
        if waiting_for_wave {
            self.set_playing(false, true);
            return;
        }
        self.mpris.set_status(MprisStatus::Stopped, 0.0);
        self.discord.set_stopped();

        self.set_playing(false, false);
        self.send_event(EVENT_PLAYBACK_PROGRESS, &PlaybackProgressPayload {
            position_secs: 0.0,
            duration_secs: 0.0,
            position_text: "0:00".into(),
            duration_text: "0:00".into(),
            progress: 0.0,
        });
    }

    pub fn play_index(self: Arc<Self>, index: usize, manual_skip: bool) {
        self.play_index_at(index, manual_skip, None);
    }

    pub fn play_index_at(self: Arc<Self>, index: usize, manual_skip: bool, start_at: Option<f64>) {
        let (prev_track, prev_played, track, next_track_id, generation, api, current_idx, liked, wave) = {
            let mut st = self.state.lock().unwrap();
            let Some(track) = st.queue.get(index).cloned() else { return };
            let api = st.api.clone();
            let prev_track = current_track(&st).cloned();
            let prev_played = st.position_secs;
            let next_track_id = st.queue[index + 1..]
                .iter()
                .find(|t| t.available)
                .map(|t| t.id.clone());
            st.current = Some(index);
            st.generation += 1;
            st.duration_secs = track.duration_ms as f64 / 1000.0;
            st.position_secs = 0.0;
            st.audio_started = true;
            st.history_generation = None;
            st.resume_at = start_at;
            let liked = st.liked_ids.contains(&track.id);
            (
                prev_track,
                prev_played,
                track,
                next_track_id,
                st.generation,
                api,
                current_list_index(&st),
                liked,
                st.wave.clone(),
            )
        };

        self.send_queue();
        self.persist_session();

        if let (Some(w), Some(api_fb)) = (wave, api.clone()) {
            let cur_cid = track.composite_id();
            let prev_cid = prev_track.filter(|t| t.id != track.id).map(|t| t.composite_id());
            self.rt_handle.spawn(async move {
                if let Some(prev_id) = prev_cid {
                    let ev = if manual_skip { "skip" } else { "trackFinished" };
                    api_fb
                        .rotor_feedback(&w.session_id, &w.batch_id, ev, Some(&prev_id), Some(prev_played))
                        .await;
                }
                api_fb
                    .rotor_feedback(&w.session_id, &w.batch_id, "trackStarted", Some(&cur_cid), None)
                    .await;
            });
            self.clone().maybe_extend_wave(index);
        }

        let cover_url = track.cover_url(400).unwrap_or_default();
        let has_cover = !cover_url.is_empty();

        self.send_event(EVENT_NOW_PLAYING, &NowPlayingPayload {
            has_track: true,
            id: track.id.clone(),
            title: track.title.clone(),
            artists: track.artists.clone(),
            album: track.album_title.clone(),
            cover_url: cover_url.clone(),
            has_cover,
            duration_ms: track.duration_ms,
            duration_text: fmt_time(track.duration_ms as f64 / 1000.0),
            liked,
            has_artist: track.artist_id.is_some(),
            has_album: track.album_id.is_some(),
        });

        let tracks: Vec<TrackItemPayload> = {
            let st = self.state.lock().unwrap();
            st.list.iter().map(|t| track_payload(t, &st.liked_ids)).collect()
        };

        self.set_playing(false, true);

        self.send_event(EVENT_PLAYBACK_PROGRESS, &PlaybackProgressPayload {
            position_secs: 0.0,
            duration_secs: track.duration_ms as f64 / 1000.0,
            position_text: "0:00".into(),
            duration_text: fmt_time(track.duration_ms as f64 / 1000.0),
            progress: 0.0,
        });

        self.send_event(EVENT_TRACKS_LOADED, &TracksPayload {
            tracks,
            current_index: current_idx,
        });

        self.mpris.set_track(
            MprisMeta {
                id: track.id.clone(),
                title: track.title.clone(),
                artists: track.artists.clone(),
                duration_us: (track.duration_ms as i64) * 1000,
                cover_url: Some(cover_url),
            },
            MprisStatus::Paused,
        );
        self.discord.set_track(&track, MprisStatus::Paused);

        if let Some((file, len)) = cache::open_cached_track(&track.id) {
            self.audio.load(generation, SourceData::Cached { file, len });
            if let Some(next_id) = next_track_id {
                self.prefetch(next_id);
            }
            return;
        }

        self.audio.stop();

        let Some(api) = api else {
            self.state.lock().unwrap().audio_started = false;
            self.set_playing(false, false);
            self.error("Трек не сохранён на устройстве. Для загрузки нужен вход в аккаунт.");
            return;
        };

        let this = self.clone();
        self.rt_handle.spawn(async move {
            let res = async {
                let url = api.track_direct_url(&track.id).await?;
                if this.generation() != generation {
                    anyhow::bail!("cancelled");
                }
                cache::stream_track(api.http().clone(), url, track.id.clone()).await
            }
            .await;

            if this.generation() != generation {
                return;
            }
            match res {
                Ok(reader) => {
                    this.audio.load(generation, SourceData::Stream(reader));
                    if let Some(next_id) = next_track_id {
                        this.prefetch(next_id);
                    }
                }
                Err(e) => {
                    this.set_playing(false, false);
                    this.error(format!("«{}»: {e:#}", track.title));
                }
            }
        });
    }

    pub fn prefetch(self: Arc<Self>, track_id: String) {
        if cache::is_track_cached(&track_id) {
            return;
        }
        let Some(api) = self.api() else { return };
        self.rt_handle.spawn(async move {
            let Ok(url) = api.track_direct_url(&track_id).await else { return };
            let Some(path) = cache::track_path(&track_id) else { return };
            if cache::download_to_file(api.http(), &url, &path).await.is_ok() {
                let _ = tokio::task::spawn_blocking(cache::trim_track_cache).await;
            }
        });
    }

    pub fn maybe_extend_wave(self: Arc<Self>, current_index: usize) {
        let (api, session_id, queue_ids) = {
            let mut st = self.state.lock().unwrap();
            let len = st.queue.len();
            let Some(api) = st.api.clone() else { return };
            let queue_ids: Vec<String> = st.queue.iter().map(Track::composite_id).collect();
            let Some(w) = &mut st.wave else { return };
            if w.fetching_more || current_index + 3 < len {
                return;
            }
            w.fetching_more = true;
            (api, w.session_id.clone(), queue_ids)
        };

        let this = self.clone();
        self.rt_handle.spawn(async move {
            let res = api.rotor_session_tracks(&session_id, &queue_ids).await;
            let resume;
            let mut new_for_view = false;
            let mut wave_cache_update = None;
            {
                let mut st = this.state.lock().unwrap();
                let showing_wave = st.list.len() == st.queue.len()
                    && st.list.iter().zip(&st.queue).all(|(a, b)| a.id == b.id);
                let known: HashSet<String> = st.queue.iter().map(|t| t.id.clone()).collect();
                let State { wave, queue, list, views, .. } = &mut *st;
                let Some(w) = wave.as_mut().filter(|w| w.session_id == session_id) else {
                    return;
                };
                w.fetching_more = false;
                resume = std::mem::take(&mut w.resume_on_load);
                if let Ok((batch_id, more)) = res {
                    w.batch_id = batch_id;
                    let fresh: Vec<Track> =
                        more.into_iter().filter(|t| !known.contains(&t.id)).collect();
                    if !fresh.is_empty() {
                        w.tracks.extend(fresh.iter().cloned());
                        let key = format!("wave:{}", w.seed);
                        let cached = CachedView {
                            cover_uri: None,
                            title: w.title.clone(),
                            subtitle: "Персональный поток рекомендаций".into(),
                            cards: Vec::new(),
                            tracks: w.tracks.clone(),
                            viewed_artist_id: None,
                            artist_view: None,
                        };
                        views.insert(key.clone(), cached.clone());
                        wave_cache_update = Some((key, cached));
                    }
                    if showing_wave && !fresh.is_empty() {
                        list.extend(fresh.iter().cloned());
                        new_for_view = true;
                    }
                    queue.extend(fresh);
                }
            }
            if let Some((key, cached)) = wave_cache_update {
                cache::save_view(&key, &cached);
            }
            this.send_queue();
            if new_for_view {
                this.refresh_rows();
            }
            if resume {
                this.step(1, false);
            }
        });
    }

    pub fn on_audio(self: Arc<Self>, event: Event) {
        let current = self.generation();
        match event {
            Event::Started(g) if g == current => {
                self.mpris.set_status(MprisStatus::Playing, 0.0);
                self.discord.set_status(MprisStatus::Playing, 0.0);
                let resume = self.state.lock().unwrap().resume_at.take();
                if let Some(secs) = resume {
                    self.audio.seek(secs);
                    let mut st = self.state.lock().unwrap();
                    st.position_secs = secs;
                    st.seek_target_secs = secs;
                    st.last_seek_time = Some(std::time::Instant::now());
                }
                self.set_playing(true, false);
            }
            Event::Position { generation, secs, paused } if generation == current => {
                let listened = {
                    let mut st = self.state.lock().unwrap();
                    if !paused && secs >= 5.0 && st.history_generation != Some(generation) {
                        st.history_generation = Some(generation);
                        current_track(&st).cloned()
                    } else { None }
                };
                if let Some(track) = listened {
                    let this = self.clone();
                    self.rt_handle.spawn(async move {
                        match tokio::task::spawn_blocking(move || crate::history::record(track)).await {
                            Ok(Ok(tracks)) => this.send_history_tracks(tracks),
                            _ => this.error("Не удалось сохранить историю прослушивания"),
                        }
                    });
                }
                let (duration, should_save, ignore_pos, state_changed) = {
                    let mut st = self.state.lock().unwrap();
                    let ignore_pos = if let Some(seek_time) = st.last_seek_time {
                        if seek_time.elapsed() < Duration::from_millis(350) {
                            (secs - st.seek_target_secs).abs() > 1.5
                        } else {
                            st.last_seek_time = None;
                            false
                        }
                    } else {
                        false
                    };

                    if !ignore_pos {
                        st.position_secs = secs;
                    }
                    let cur_sec = st.position_secs as u64;
                    let should_save = cur_sec > 0 && cur_sec % 5 == 0 && cur_sec != st.last_saved_sec;
                    if should_save && !ignore_pos {
                        st.last_saved_sec = cur_sec;
                    }
                    let state_changed = st.playing == paused;
                    st.playing = !paused;
                    (st.duration_secs, should_save && !ignore_pos, ignore_pos, state_changed)
                };
                if state_changed {
                    self.send_playback_state(false);
                }
                if ignore_pos {
                    return;
                }
                if should_save {
                    self.persist_session();
                }
                let status = if paused { MprisStatus::Paused } else { MprisStatus::Playing };
                self.mpris.set_status(status, secs);
                self.discord.set_status(status, secs);
                let progress = if duration > 0.0 { (secs / duration) as f32 } else { 0.0 };

                self.send_event(EVENT_PLAYBACK_PROGRESS, &PlaybackProgressPayload {
                    position_secs: secs,
                    duration_secs: duration,
                    position_text: fmt_time(secs),
                    duration_text: fmt_time(duration),
                    progress,
                });
            }
            Event::Ended(g) if g == current => {
                let (repeat_mode, cur) = {
                    let st = self.state.lock().unwrap();
                    (st.repeat_mode, st.current)
                };
                if repeat_mode == 2 {
                    if let Some(cur_idx) = cur {
                        self.play_index(cur_idx, false);
                        return;
                    }
                }
                self.set_playing(false, false);
                self.step(1, false);
            }
            Event::Error(g, msg) if g == current || g == 0 => {
                self.mpris.set_status(MprisStatus::Stopped, 0.0);
                self.discord.set_stopped();
                self.state.lock().unwrap().audio_started = false;
                self.set_playing(false, false);
                self.error(msg);
            }
            _ => {}
        }
    }

    pub fn toggle(self: Arc<Self>) {
        let (started, current, pos) = {
            let st = self.state.lock().unwrap();
            (st.audio_started, st.current, st.position_secs)
        };
        if started {
            self.audio.toggle();
            self.persist_session();
        } else if let Some(idx) = current {
            self.play_index_at(idx, false, (pos > 1.0).then_some(pos));
        }
    }

    pub fn play(self: Arc<Self>) {
        if self.state.lock().unwrap().audio_started {
            self.audio.play();
        } else {
            self.toggle();
        }
    }

    pub fn toggle_repeat(self: Arc<Self>) {
        let mode = {
            let mut st = self.state.lock().unwrap();
            st.repeat_mode = (st.repeat_mode + 1) % 3;
            st.repeat_mode
        };
        self.send_playback_state(false);
        self.rt_handle.spawn_blocking(move || {
            config::update_settings(|s| s.repeat_mode = mode);
        });
    }

    pub fn toggle_shuffle(self: Arc<Self>) {
        let shuffle_on = {
            let mut st = self.state.lock().unwrap();
            st.shuffle = !st.shuffle;
            if st.shuffle {
                if st.unshuffled_queue.is_none() {
                    st.unshuffled_queue = Some(st.queue.clone());
                }
                if let Some(cur) = st.current {
                    if cur + 1 < st.queue.len() {
                        let mut tail = st.queue.split_off(cur + 1);
                        shuffle_slice(&mut tail);
                        st.queue.extend(tail);
                    }
                } else if !st.queue.is_empty() {
                    shuffle_slice(&mut st.queue);
                }
            } else if let Some(mut orig) = st.unshuffled_queue.take() {
                // Треки, догруженные волной во время перемешивания, не должны пропасть.
                let known: HashSet<String> = orig.iter().map(|t| t.id.clone()).collect();
                let extra: Vec<Track> =
                    st.queue.iter().filter(|t| !known.contains(&t.id)).cloned().collect();
                orig.extend(extra);
                if let Some(cur) = st.current {
                    if let Some(track) = st.queue.get(cur) {
                        let id = track.id.clone();
                        if let Some(new_idx) = orig.iter().position(|t| t.id == id) {
                            st.current = Some(new_idx);
                        }
                    }
                }
                st.queue = orig;
            }
            st.shuffle
        };
        self.send_playback_state(false);
        self.send_queue();
        self.rt_handle.spawn_blocking(move || {
            config::update_settings(|s| s.shuffle = shuffle_on);
        });
    }

    pub fn toggle_mute(self: Arc<Self>) {
        let new_vol = {
            let mut st = self.state.lock().unwrap();
            if st.volume > 0.001 {
                st.last_unmuted_volume = st.volume;
                0.0
            } else if st.last_unmuted_volume > 0.05 {
                st.last_unmuted_volume
            } else {
                0.7
            }
        };
        self.set_volume(new_vol);
    }

    pub fn seek(&self, frac: f32) {
        let fraction = frac.clamp(0.0, 1.0);
        let (duration, started) = {
            let st = self.state.lock().unwrap();
            (st.duration_secs, st.audio_started)
        };
        if duration > 0.0 {
            let secs = f64::from(fraction) * duration;
            {
                let mut st = self.state.lock().unwrap();
                st.position_secs = secs;
                st.seek_target_secs = secs;
                st.last_seek_time = Some(std::time::Instant::now());
            }
            if started {
                self.audio.seek(secs);
            }
            self.send_event(EVENT_PLAYBACK_PROGRESS, &PlaybackProgressPayload {
                position_secs: secs,
                duration_secs: duration,
                position_text: fmt_time(secs),
                duration_text: fmt_time(duration),
                progress: fraction,
            });
            self.persist_session();
        }
    }

    pub fn set_volume(&self, v: f32) {
        let vol = v.clamp(0.0, 1.0);
        {
            let mut st = self.state.lock().unwrap();
            st.volume = vol;
            if vol > 0.001 {
                st.last_unmuted_volume = vol;
            }
        }
        self.audio.set_volume(perceptual(vol));
        self.mpris.set_volume(vol);
        self.save_volume(vol);
        self.send_playback_state(false);
    }

    pub fn save_volume(&self, vol: f32) {
        self.rt_handle.spawn_blocking(move || {
            config::update_settings(|s| s.volume = vol);
        });
    }

    pub fn persist_session(&self) {
        let (queue, current, pos, wave) = {
            let st = self.state.lock().unwrap();
            let Some(idx) = st.current else { return };
            if st.queue.is_empty() { return };
            let queue = st.queue.clone();
            let pos = st.position_secs;
            let wave = st.wave.as_ref().map(|w| config::SavedWaveState {
                seed: w.seed.clone(),
                title: w.title.clone(),
                session_id: w.session_id.clone(),
                batch_id: w.batch_id.clone(),
                tracks: w.tracks.clone(),
            });
            (queue, idx, pos, wave)
        };

        let session = config::SavedSession {
            queue,
            current_index: current,
            position_secs: pos,
            wave,
        };

        self.rt_handle.spawn_blocking(move || {
            config::update_settings(|s| s.session = Some(session));
        });
    }

    pub fn clear_saved_session(&self) {
        self.rt_handle.spawn_blocking(move || {
            config::update_settings(|s| s.session = None);
        });
    }

    pub fn restore_session(self: Arc<Self>) {
        let settings = config::load_settings();
        let Some(session) = settings.session else { return };
        if session.queue.is_empty() { return };
        let idx = session.current_index.min(session.queue.len() - 1);
        let track = session.queue[idx].clone();
        let pos_secs = session.position_secs;
        let duration_secs = track.duration_ms as f64 / 1000.0;
        let progress = if duration_secs > 0.0 { (pos_secs / duration_secs) as f32 } else { 0.0 };
        let pos_text = fmt_time(pos_secs);
        let dur_text = fmt_time(duration_secs);

        let liked = {
            let mut st = self.state.lock().unwrap();
            st.queue = session.queue.clone();
            st.current = Some(idx);
            st.position_secs = pos_secs;
            st.duration_secs = duration_secs;
            st.audio_started = false;
            if let Some(w) = session.wave {
                st.wave = Some(WaveState {
                    seed: w.seed,
                    title: w.title,
                    session_id: w.session_id,
                    batch_id: w.batch_id,
                    tracks: w.tracks,
                    fetching_more: false,
                    resume_on_load: false,
                });
            }
            st.liked_ids.contains(&track.id)
        };

        let cover_url = track.cover_url(400).unwrap_or_default();
        let has_cover = !cover_url.is_empty();

        self.send_event(EVENT_NOW_PLAYING, &NowPlayingPayload {
            has_track: true,
            id: track.id.clone(),
            title: track.title.clone(),
            artists: track.artists.clone(),
            album: track.album_title.clone(),
            cover_url: cover_url.clone(),
            has_cover,
            duration_ms: track.duration_ms,
            duration_text: dur_text.clone(),
            liked,
            has_artist: track.artist_id.is_some(),
            has_album: track.album_id.is_some(),
        });

        self.send_event(EVENT_PLAYBACK_PROGRESS, &PlaybackProgressPayload {
            position_secs: pos_secs,
            duration_secs,
            position_text: pos_text,
            duration_text: dur_text,
            progress,
        });

        self.mpris.set_track(
            MprisMeta {
                id: track.id.clone(),
                title: track.title.clone(),
                artists: track.artists.clone(),
                duration_us: (track.duration_ms as i64) * 1000,
                cover_url: Some(cover_url),
            },
            MprisStatus::Paused,
        );
        self.discord.set_track(&track, MprisStatus::Paused);
        self.send_queue();
    }

    pub fn on_mpris(self: Arc<Self>, action: MprisAction) {
        match action {
            MprisAction::Play => self.clone().play(),
            MprisAction::Pause => self.audio.pause(),
            MprisAction::Toggle => self.clone().toggle(),
            MprisAction::Stop => {
                self.audio.stop();
                {
                    let mut st = self.state.lock().unwrap();
                    st.audio_started = false;
                    st.generation += 1;
                }
                self.set_playing(false, false);
                self.mpris.set_status(MprisStatus::Stopped, 0.0);
                self.discord.set_stopped();
            }
            MprisAction::Next => self.step(1, true),
            MprisAction::Prev => self.step(-1, true),
            MprisAction::SeekRelative(delta) => self.audio.seek_relative(delta),
            MprisAction::SeekAbsolute(secs) => self.audio.seek(secs),
            MprisAction::SetVolume(v) => self.set_volume(v),
            MprisAction::Quit => {}
        }
    }
}
