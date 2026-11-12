use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex};
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
}

pub struct YMusicCore {
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
        available: t.available,
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

impl YMusicCore {
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
        }

        core.send_event(EVENT_PLAYBACK_STATE, &PlaybackStatePayload {
            playing: false,
            buffering: false,
            volume: initial_vol,
            shuffle: settings.shuffle,
            repeat_mode: settings.repeat_mode as i32,
        });

        if let Some(token) = config::load_token() {
            core.clone().login(token);
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

            this.send_event(EVENT_LOGIN_STATUS, &LoginStatusPayload {
                logged_in: false,
                busy: false,
                user_name: String::new(),
                user_avatar: String::new(),
                user_has_avatar: false,
            });

            match result {
                Ok(token) => this.login(token),
                Err(e) => this.error(format!("Вход: {e}")),
            }
        });
    }

    pub fn login(self: Arc<Self>, token: String) {
        if token.is_empty() {
            return;
        }
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

                    this.clone().load_home();
                    this.clone().prefetch_likes();
                    this.clone().restore_session();
                }
                Err(e) => this.error(format!("Не удалось войти: {e}")),
            }
        });
    }

    pub fn logout(&self) {
        config::clear_token();
        self.clear_saved_session();
        {
            let mut st = self.state.lock().unwrap();
            *st = State {
                generation: st.generation + 1,
                view_id: st.view_id + 1,
                ..State::default()
            };
        }
        self.audio.stop();
        self.mpris.set_stopped();
        self.discord.set_stopped();

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

    pub fn begin_cached_view(&self, key: Option<&str>, page: i32, title: String, subtitle: String) -> u64 {
        let is_artist = key.is_some_and(|k| k.starts_with("artist:"));
        let (view, has_cache, eff_title, eff_subtitle, cards_payload, tracks_payload, current_idx, can_wave, artist_info) = {
            let mut st = self.state.lock().unwrap();
            st.view_id += 1;
            st.page = page;
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
        let Some(api) = self.api() else { return };
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
            self.send_event(EVENT_VIEW_HEADER, &ViewHeaderPayload {
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
        let Some(api) = self.api() else { return };
        let cache_key = format!("wave:{seed}");
        let view = self.begin_cached_view(
            Some(&cache_key),
            1,
            title.clone(),
            "Персональный поток рекомендаций".into(),
        );
        let this = self.clone();
        self.rt_handle.spawn(async move {
            let session = match api.rotor_session_new(&[seed.as_str()]).await {
                Ok(s) => s,
                Err(e) => return this.view_failed(view, "Моя волна", e),
            };
            if session.tracks.is_empty() {
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
            this.play_index(0, false);
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
        if query.is_empty() {
            return;
        }
        let Some(api) = self.api() else { return };
        let key = format!("search:{}", query.to_lowercase());
        let title = format!("Поиск: {query}");
        let view = self.begin_cached_view(
            Some(&key),
            6,
            title.clone(),
            "Артисты, альбомы, плейлисты и треки".into(),
        );
        let this = self.clone();
        self.rt_handle.spawn(async move {
            match api.search_all(&query).await {
                Ok(res) => {
                    let mut cards = Vec::new();
                    cards.extend(res.artists.into_iter().take(4).map(CardTarget::Artist));
                    cards.extend(res.albums.into_iter().take(4).map(CardTarget::Album));
                    cards.extend(res.playlists.into_iter().take(3).map(playlist_target));
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
        let key = format!("playlist:{owner_uid}:{kind}");
        let view = self.begin_cached_view(Some(&key), 6, title.clone(), "Плейлист".into());
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
            let (shuf, rep) = {
                let st = self.state.lock().unwrap();
                (st.shuffle, st.repeat_mode as i32)
            };
            self.send_event(EVENT_PLAYBACK_STATE, &PlaybackStatePayload {
                playing: false,
                buffering: true,
                volume: config::load_settings().volume,
                shuffle: shuf,
                repeat_mode: rep,
            });
            return;
        }
        self.mpris.set_status(MprisStatus::Stopped, 0.0);
        self.discord.set_stopped();

        let (vol, shuf, rep) = {
            let st = self.state.lock().unwrap();
            (config::load_settings().volume, st.shuffle, st.repeat_mode as i32)
        };
        self.send_event(EVENT_PLAYBACK_STATE, &PlaybackStatePayload {
            playing: false,
            buffering: false,
            volume: vol,
            shuffle: shuf,
            repeat_mode: rep,
        });
        self.send_event(EVENT_PLAYBACK_PROGRESS, &PlaybackProgressPayload {
            position_secs: 0.0,
            duration_secs: 0.0,
            position_text: "0:00".into(),
            duration_text: "0:00".into(),
            progress: 0.0,
        });
    }

    pub fn play_index(self: Arc<Self>, index: usize, manual_skip: bool) {
        let (prev_track, prev_played, track, next_track_id, generation, api, current_idx, liked, wave) = {
            let mut st = self.state.lock().unwrap();
            let Some(track) = st.queue.get(index).cloned() else { return };
            let Some(api) = st.api.clone() else { return };
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

        self.persist_session();

        if let Some(w) = wave {
            let api_fb = api.clone();
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

        let (shuf, rep, tracks) = {
            let st = self.state.lock().unwrap();
            let tracks = st.list.iter().map(|t| track_payload(t, &st.liked_ids)).collect();
            (st.shuffle, st.repeat_mode as i32, tracks)
        };

        self.send_event(EVENT_PLAYBACK_STATE, &PlaybackStatePayload {
            playing: false,
            buffering: true,
            volume: config::load_settings().volume,
            shuffle: shuf,
            repeat_mode: rep,
        });

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
                    let (shuf, rep) = {
                        let st = this.state.lock().unwrap();
                        (st.shuffle, st.repeat_mode as i32)
                    };
                    this.send_event(EVENT_PLAYBACK_STATE, &PlaybackStatePayload {
                        playing: false,
                        buffering: false,
                        volume: config::load_settings().volume,
                        shuffle: shuf,
                        repeat_mode: rep,
                    });
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
        let this = self.clone();
        self.rt_handle.spawn(async move {
            let Ok(url) = api.track_direct_url(&track_id).await else { return };
            let Ok(resp) = api.http().get(url).send().await else { return };
            let Ok(resp) = resp.error_for_status() else { return };
            let Ok(bytes) = resp.bytes().await else { return };
            let _ = tokio::task::spawn_blocking(move || cache::save_track(&track_id, &bytes)).await;
            this.refresh_rows();
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

                let (vol, shuf, rep) = {
                    let st = self.state.lock().unwrap();
                    (config::load_settings().volume, st.shuffle, st.repeat_mode as i32)
                };
                self.send_event(EVENT_PLAYBACK_STATE, &PlaybackStatePayload {
                    playing: true,
                    buffering: false,
                    volume: vol,
                    shuffle: shuf,
                    repeat_mode: rep,
                });
            }
            Event::Position { generation, secs, paused } if generation == current => {
                let (duration, should_save, ignore_pos) = {
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
                    (st.duration_secs, should_save && !ignore_pos, ignore_pos)
                };
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

                let (vol, shuf, rep) = {
                    let st = self.state.lock().unwrap();
                    (config::load_settings().volume, st.shuffle, st.repeat_mode as i32)
                };
                self.send_event(EVENT_PLAYBACK_STATE, &PlaybackStatePayload {
                    playing: !paused,
                    buffering: false,
                    volume: vol,
                    shuffle: shuf,
                    repeat_mode: rep,
                });

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
                let (vol, shuf, rep) = {
                    let st = self.state.lock().unwrap();
                    (config::load_settings().volume, st.shuffle, st.repeat_mode as i32)
                };
                self.send_event(EVENT_PLAYBACK_STATE, &PlaybackStatePayload {
                    playing: false,
                    buffering: false,
                    volume: vol,
                    shuffle: shuf,
                    repeat_mode: rep,
                });
                self.step(1, false);
            }
            Event::Error(g, msg) if g == current || g == 0 => {
                self.mpris.set_status(MprisStatus::Stopped, 0.0);
                self.discord.set_stopped();
                let (vol, shuf, rep) = {
                    let st = self.state.lock().unwrap();
                    (config::load_settings().volume, st.shuffle, st.repeat_mode as i32)
                };
                self.send_event(EVENT_PLAYBACK_STATE, &PlaybackStatePayload {
                    playing: false,
                    buffering: false,
                    volume: vol,
                    shuffle: shuf,
                    repeat_mode: rep,
                });
                self.error(msg);
            }
            _ => {}
        }
    }

    pub fn toggle(self: Arc<Self>) {
        let (started, current) = {
            let st = self.state.lock().unwrap();
            (st.audio_started, st.current)
        };
        if started {
            self.audio.toggle();
            self.persist_session();
        } else if let Some(idx) = current {
            self.play_index(idx, false);
        }
    }

    pub fn toggle_repeat(self: Arc<Self>) {
        let mode = {
            let mut st = self.state.lock().unwrap();
            st.repeat_mode = (st.repeat_mode + 1) % 3;
            st.repeat_mode
        };
        self.send_event(EVENT_PLAYBACK_STATE, &PlaybackStatePayload {
            playing: self.audio_is_playing(),
            buffering: false,
            volume: config::load_settings().volume,
            shuffle: self.state.lock().unwrap().shuffle,
            repeat_mode: mode as i32,
        });
        self.rt_handle.spawn_blocking(move || {
            let mut settings = config::load_settings();
            settings.repeat_mode = mode;
            let _ = config::save_settings(&settings);
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
            } else if let Some(orig) = st.unshuffled_queue.take() {
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
        self.send_event(EVENT_PLAYBACK_STATE, &PlaybackStatePayload {
            playing: self.audio_is_playing(),
            buffering: false,
            volume: config::load_settings().volume,
            shuffle: shuffle_on,
            repeat_mode: self.state.lock().unwrap().repeat_mode as i32,
        });
        self.rt_handle.spawn_blocking(move || {
            let mut settings = config::load_settings();
            settings.shuffle = shuffle_on;
            let _ = config::save_settings(&settings);
        });
    }

    pub fn audio_is_playing(&self) -> bool {
        self.state.lock().unwrap().audio_started
    }

    pub fn toggle_mute(self: Arc<Self>) {
        let (new_vol, should_save) = {
            let mut st = self.state.lock().unwrap();
            let cur = config::load_settings().volume;
            if cur > 0.001 {
                st.last_unmuted_volume = cur;
                (0.0, true)
            } else {
                let restore = if st.last_unmuted_volume > 0.05 {
                    st.last_unmuted_volume
                } else {
                    0.7
                };
                (restore, true)
            }
        };
        if should_save {
            self.audio.set_volume(perceptual(new_vol));
            self.mpris.set_volume(new_vol);
            self.save_volume(new_vol);
            self.send_event(EVENT_PLAYBACK_STATE, &PlaybackStatePayload {
                playing: self.audio_is_playing(),
                buffering: false,
                volume: new_vol,
                shuffle: self.state.lock().unwrap().shuffle,
                repeat_mode: self.state.lock().unwrap().repeat_mode as i32,
            });
        }
    }

    pub fn seek(&self, frac: f32) {
        let fraction = frac.clamp(0.0, 1.0);
        let duration = self.state.lock().unwrap().duration_secs;
        if duration > 0.0 {
            let secs = f64::from(fraction) * duration;
            self.audio.seek(secs);
            {
                let mut st = self.state.lock().unwrap();
                st.position_secs = secs;
                st.seek_target_secs = secs;
                st.last_seek_time = Some(std::time::Instant::now());
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
        self.audio.set_volume(perceptual(vol));
        self.mpris.set_volume(vol);
        self.save_volume(vol);
        self.send_event(EVENT_PLAYBACK_STATE, &PlaybackStatePayload {
            playing: self.audio_is_playing(),
            buffering: false,
            volume: vol,
            shuffle: self.state.lock().unwrap().shuffle,
            repeat_mode: self.state.lock().unwrap().repeat_mode as i32,
        });
    }

    pub fn save_volume(&self, vol: f32) {
        self.rt_handle.spawn_blocking(move || {
            let mut settings = config::load_settings();
            settings.volume = vol;
            let _ = config::save_settings(&settings);
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
            let mut settings = config::load_settings();
            settings.session = Some(session);
            let _ = config::save_settings(&settings);
        });
    }

    pub fn clear_saved_session(&self) {
        self.rt_handle.spawn_blocking(move || {
            let mut settings = config::load_settings();
            settings.session = None;
            let _ = config::save_settings(&settings);
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
    }

    pub fn on_mpris(self: Arc<Self>, action: MprisAction) {
        match action {
            MprisAction::Play => self.clone().toggle(),
            MprisAction::Pause => self.audio.pause(),
            MprisAction::Toggle => self.clone().toggle(),
            MprisAction::Stop => {
                self.audio.stop();
                let (vol, shuf, rep) = {
                    let st = self.state.lock().unwrap();
                    (config::load_settings().volume, st.shuffle, st.repeat_mode as i32)
                };
                self.send_event(EVENT_PLAYBACK_STATE, &PlaybackStatePayload {
                    playing: false,
                    buffering: false,
                    volume: vol,
                    shuffle: shuf,
                    repeat_mode: rep,
                });
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
