use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use parking_lot::{Mutex, RwLock};
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
use crate::lastfm::{Lastfm, LastfmConfig};
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
    pub artist_links: Vec<ArtistLinkPayload>,
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
    #[serde(default)]
    pub is_ai: bool,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct CardItemPayload {
    pub key: String,
    pub title: String,
    pub subtitle: String,
    pub kind: String,
    #[serde(default)]
    pub section: String,
    pub cover_url: String,
    pub has_cover: bool,
    pub pinned: bool,
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
pub struct ArtistLinkPayload {
    pub id: String,
    pub name: String,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct NowPlayingPayload {
    pub has_track: bool,
    pub id: String,
    pub title: String,
    pub artists: String,
    pub artist_links: Vec<ArtistLinkPayload>,
    pub album: String,
    pub cover_url: String,
    pub has_cover: bool,
    pub duration_ms: u64,
    pub duration_text: String,
    pub liked: bool,
    pub has_artist: bool,
    pub has_album: bool,
    #[serde(default)]
    pub is_ai: bool,
}

fn artist_links_for(t: &Track) -> Vec<ArtistLinkPayload> {
    if !t.artist_links.is_empty() {
        return t.artist_links.iter().map(|(id, name)| ArtistLinkPayload { id: id.clone(), name: name.clone() }).collect();
    }
    let parts: Vec<&str> = t.artists.split(", ").map(str::trim).filter(|s| !s.is_empty()).collect();
    if parts.len() > 1 {
        return parts
            .into_iter()
            .enumerate()
            .map(|(i, name)| ArtistLinkPayload {
                id: if i == 0 { t.artist_id.clone().unwrap_or_default() } else { String::new() },
                name: name.to_string(),
            })
            .collect();
    }
    match &t.artist_id {
        Some(id) if !t.artists.is_empty() => vec![ArtistLinkPayload { id: id.clone(), name: t.artists.clone() }],
        _ => Vec::new(),
    }
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
        subtitle: String,
        #[serde(default)]
        cover_uri: Option<String>,
        #[serde(default)]
        section: String,
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
    pub filters: Vec<String>,
    pub fetching_more: bool,
    pub resume_on_load: bool,
}

impl WaveState {
    pub fn cache_key(&self) -> String {
        format!("wave:{}:{}", self.seed, self.filters.join(","))
    }
}

#[derive(Default)]
pub struct State {
    pub wave_groups: Vec<crate::wave::Group>,
    pub wave_selected: HashMap<String, String>,
    pub search_query: String,
    pub search_filter: String,
    pub search_suggest_seq: u64,
    pub quick_search_tracks: Vec<Track>,
    pub quick_search_best: Option<api::SearchBest>,
    pub search_best: Option<api::SearchBest>,
    pub search_page: u32,
    pub search_has_more: bool,
    pub search_loading_more: bool,
    pub search_history: Vec<String>,
    pub collection_downloadable: bool,
    pub active_playlist: Option<config::PinnedPlaylist>,
    pub active_album_id: Option<String>,
    pub pinned_playlists: Vec<config::PinnedPlaylist>,
    pub liked_album_ids: HashSet<String>,
    pub liked_artist_ids: HashSet<String>,
    pub liked_playlist_keys: HashSet<String>,
    pub audio_quality: String,
    pub download_quality: String,
    pub normalize_volume: bool,
    pub ai_music_behavior: String,
    pub ai_strict_tracks: bool,
    pub show_ai_labels: bool,
    pub history_generation: Option<u64>,
    pub current_play_id: String,
    pub play_scrobbled: bool,
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
    pub active_view_key: Option<String>,
    pub fetching_views: HashSet<String>,
    pub view_fetched_at: HashMap<String, std::time::Instant>,
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
    pub login_gen: std::sync::atomic::AtomicU64,
    pub rt_handle: Handle,
    pub runtime: Option<tokio::runtime::Runtime>,
    pub http: reqwest::Client,
    pub state: Arc<Mutex<State>>,
    pub cover_sem: Arc<Semaphore>,
    pub audio: Audio,
    pub mpris: Mpris,
    pub discord: Discord,
    pub lastfm: Lastfm,
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
    if slice.len() < 2 {
        return;
    }
    use std::time::SystemTime;
    let mut rng = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .map(|d| d.as_nanos() as u64)
        .unwrap_or(123456789);
    // Используем алгоритм Саттоло (`j = rng % i`), который гарантирует derangement
    // (ни один элемент не остаётся на своём исходном месте, порядок всегда меняется).
    for i in (1..slice.len()).rev() {
        rng ^= rng << 13;
        rng ^= rng >> 7;
        rng ^= rng << 17;
        let j = (rng as usize) % i;
        slice.swap(i, j);
    }
}

fn playlist_target(p: api::PlaylistCard) -> CardTarget {
    playlist_target_in(p, "")
}

fn playlist_target_in(p: api::PlaylistCard, section: &str) -> CardTarget {
    CardTarget::Playlist {
        uid: p.uid,
        kind: p.kind,
        title: p.title,
        subtitle: p.subtitle,
        cover_uri: p.cover_uri,
        section: section.to_string(),
    }
}

fn strip_legacy_playlist_title(title: &str) -> &str {
    if let Some((clean, _)) = title.rsplit_once(" (")
        && title.ends_with(')')
        && !clean.trim().is_empty()
    {
        clean.trim()
    } else {
        title
    }
}

fn is_playlist_pinned(pinned: &[config::PinnedPlaylist], uid: u64, kind: u64) -> bool {
    pinned.iter().any(|p| p.uid == uid && p.kind == kind)
}

fn quick_tracks_payload(tracks: &[Track], liked_ids: &HashSet<String>) -> Vec<serde_json::Value> {
    tracks
        .iter()
        .map(|t| {
            let cover_url = cache::resolve_track_cover_url(t, 200);
            serde_json::json!({
                "id": t.id,
                "title": t.title,
                "artists": t.artists,
                "duration": fmt_time(t.duration_ms as f64 / 1000.0),
                "cover_url": cover_url,
                "has_cover": !cover_url.is_empty(),
                "available": t.available,
                "liked": liked_ids.contains(&t.id),
                "is_ai": t.is_ai,
            })
        })
        .collect()
}

fn search_best_payload(best: &api::SearchBest, liked_ids: &HashSet<String>) -> serde_json::Value {
    match best {
        api::SearchBest::Track(t) => {
            let cover_url = cache::resolve_track_cover_url(t, 200);
            serde_json::json!({
                "kind": "track",
                "id": t.id,
                "title": t.title,
                "subtitle": t.artists,
                "duration": fmt_time(t.duration_ms as f64 / 1000.0),
                "cover_url": cover_url,
                "has_cover": !cover_url.is_empty(),
                "circular": false,
                "available": t.available,
                "liked": liked_ids.contains(&t.id),
                "is_ai": t.is_ai,
            })
        }
        api::SearchBest::Artist(a) => {
            let cover_url = api::cover_url(a.cover_uri.as_deref(), 200).unwrap_or_default();
            let subtitle = if !a.stats.is_empty() {
                a.stats.clone()
            } else if !a.genres.is_empty() {
                a.genres.clone()
            } else {
                "Исполнитель".to_string()
            };
            serde_json::json!({
                "kind": "artist",
                "id": a.id,
                "title": a.name,
                "subtitle": subtitle,
                "cover_url": cover_url,
                "has_cover": !cover_url.is_empty(),
                "circular": true,
            })
        }
        api::SearchBest::Album(a) => {
            let cover_url = api::cover_url(a.cover_uri.as_deref(), 200).unwrap_or_default();
            let subtitle = match a.year {
                Some(y) if !a.artists.is_empty() => format!("{} • {y}", a.artists),
                _ if !a.artists.is_empty() => a.artists.clone(),
                _ => "Альбом".to_string(),
            };
            serde_json::json!({
                "kind": "album",
                "id": a.id,
                "title": a.title,
                "subtitle": subtitle,
                "cover_url": cover_url,
                "has_cover": !cover_url.is_empty(),
                "circular": false,
            })
        }
        api::SearchBest::Playlist(p) => {
            let cover_url = api::cover_url(p.cover_uri.as_deref(), 200).unwrap_or_default();
            serde_json::json!({
                "kind": "playlist",
                "uid": p.uid,
                "playlist_kind": p.kind,
                "title": p.title,
                "subtitle": p.subtitle,
                "cover_url": cover_url,
                "has_cover": !cover_url.is_empty(),
                "circular": false,
            })
        }
    }
}

fn card_dedup_key(c: &CardTarget) -> String {
    match c {
        CardTarget::Playlist { uid, kind, .. } => format!("playlist:{uid}:{kind}"),
        CardTarget::Album(a) => format!("album:{}", a.id),
        CardTarget::Artist(ar) => format!("artist:{}", ar.id),
    }
}

fn card_payload(c: &CardTarget, pinned: &[config::PinnedPlaylist]) -> CardItemPayload {
    match c {
        CardTarget::Playlist { uid, kind, title, subtitle: _, cover_uri, section } => CardItemPayload {
            key: format!("playlist:{uid}:{kind}"),
            title: strip_legacy_playlist_title(title).to_string(),
            subtitle: String::new(),
            kind: "playlist".to_string(),
            section: section.clone(),
            cover_url: api::cover_url(cover_uri.as_deref(), 200).unwrap_or_default(),
            has_cover: cover_uri.is_some(),
            pinned: is_playlist_pinned(pinned, *uid, *kind),
        },
        CardTarget::Album(a) => {
            let mut parts = Vec::new();
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
                key: String::new(),
                title: a.title.clone(),
                subtitle: parts.join(" • "),
                kind: "album".to_string(),
                section: a.section.clone(),
                cover_url: api::cover_url(a.cover_uri.as_deref(), 200).unwrap_or_default(),
                has_cover: a.cover_uri.is_some(),
                pinned: false,
            }
        }
        CardTarget::Artist(ar) => {
            let sub = if !ar.stats.is_empty() {
                if !ar.genres.is_empty() {
                    format!("{} • {}", ar.genres, ar.stats)
                } else {
                    ar.stats.clone()
                }
            } else {
                ar.genres.clone()
            };
            CardItemPayload {
                key: String::new(),
                title: ar.name.clone(),
                subtitle: sub,
                kind: "artist".to_string(),
                section: String::new(),
                cover_url: api::cover_url(ar.cover_uri.as_deref(), 200).unwrap_or_default(),
                has_cover: ar.cover_uri.is_some(),
                pinned: false,
            }
        }
    }
}

#[derive(Clone, Debug, Default, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModTrackOverride {
    #[serde(default)]
    pub title: Option<String>,
    #[serde(default)]
    pub artists: Option<String>,
    #[serde(default)]
    pub album: Option<String>,
    #[serde(default)]
    pub cover_url: Option<String>,
    #[serde(default)]
    pub available: Option<bool>,
    #[serde(default)]
    pub duration_ms: Option<u64>,
    #[serde(default)]
    pub audio_url: Option<String>,
    #[serde(default)]
    pub audio_track_id: Option<String>,
    #[serde(default)]
    pub local_file: Option<String>,
    #[serde(default)]
    pub codec: Option<String>,
}

#[derive(Clone, Debug, Default)]
struct ModOverrideRegistry {
    /// mod_id -> (track_id -> override)
    tracks: HashMap<String, HashMap<String, ModTrackOverride>>,
    /// mod_id -> (album_id -> injected tracks)
    album_injections: HashMap<String, HashMap<String, Vec<Track>>>,
}

fn mod_overrides() -> &'static RwLock<ModOverrideRegistry> {
    static REG: std::sync::OnceLock<RwLock<ModOverrideRegistry>> = std::sync::OnceLock::new();
    REG.get_or_init(|| RwLock::new(ModOverrideRegistry::default()))
}

fn lookup_mod_track_override(track_id: &str) -> Option<ModTrackOverride> {
    let guard = mod_overrides().read();
    let mut merged: Option<ModTrackOverride> = None;
    for map in guard.tracks.values() {
        if let Some(ov) = map.get(track_id) {
            let dst = merged.get_or_insert_with(ModTrackOverride::default);
            if ov.title.is_some() { dst.title = ov.title.clone(); }
            if ov.artists.is_some() { dst.artists = ov.artists.clone(); }
            if ov.album.is_some() { dst.album = ov.album.clone(); }
            if ov.cover_url.is_some() { dst.cover_url = ov.cover_url.clone(); }
            if ov.available.is_some() { dst.available = ov.available; }
            if ov.duration_ms.is_some() { dst.duration_ms = ov.duration_ms; }
            if ov.audio_url.is_some() { dst.audio_url = ov.audio_url.clone(); }
            if ov.audio_track_id.is_some() { dst.audio_track_id = ov.audio_track_id.clone(); }
            if ov.local_file.is_some() { dst.local_file = ov.local_file.clone(); }
            if ov.codec.is_some() { dst.codec = ov.codec.clone(); }
        }
    }
    merged
}

fn apply_mod_track_override(track: &Track) -> Track {
    let Some(ov) = lookup_mod_track_override(&track.id) else {
        return track.clone();
    };
    let mut out = track.clone();
    if let Some(title) = ov.title.filter(|s| !s.trim().is_empty()) {
        out.title = title;
    }
    if let Some(artists) = ov.artists.filter(|s| !s.trim().is_empty()) {
        out.artists = artists;
    }
    if let Some(album) = ov.album.filter(|s| !s.trim().is_empty()) {
        out.album_title = album;
    }
    if let Some(cover) = ov.cover_url.filter(|s| !s.trim().is_empty()) {
        out.cover_uri = Some(cover);
    }
    if let Some(avail) = ov.available {
        out.available = avail;
    } else if ov.audio_url.is_some() || ov.audio_track_id.is_some() || ov.local_file.is_some() {
        out.available = true;
    }
    if let Some(dur) = ov.duration_ms.filter(|&d| d > 0) {
        out.duration_ms = dur;
    }
    out
}

fn collect_mod_album_injections(album_id: &str) -> Vec<Track> {
    let guard = mod_overrides().read();
    let mut out = Vec::new();
    for map in guard.album_injections.values() {
        if let Some(tracks) = map.get(album_id) {
            out.extend(tracks.iter().cloned());
        }
    }
    out
}

fn track_payload(t: &Track, liked_ids: &HashSet<String>) -> TrackItemPayload {
    let eff = apply_mod_track_override(t);
    let cover_url = cache::resolve_track_cover_url(&eff, 200);
    TrackItemPayload {
        id: eff.id.clone(),
        title: eff.title.clone(),
        artists: eff.artists.clone(),
        artist_links: artist_links_for(&eff),
        album: eff.album_title.clone(),
        duration: fmt_time(eff.duration_ms as f64 / 1000.0),
        duration_ms: eff.duration_ms,
        available: eff.available || cache::is_offline(&eff.id),
        downloaded: cache::is_offline(&eff.id),
        liked: liked_ids.contains(&eff.id),
        has_cover: !cover_url.is_empty(),
        cover_url,
        has_artist: eff.artist_id.is_some(),
        has_album: eff.album_id.is_some(),
        is_ai: eff.is_ai || crate::slopless::is_track_ai_fast(&eff),
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
            album_id: None, album_title: String::new(), artist_id: None, artist_links: Vec::new(),
            duration_ms: 1000, cover_uri: None, available: true,
            has_sync_lyrics: false, has_text_lyrics: false, r128_i: None, r128_tp: None, is_ai: false,
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

    struct CaptureSink(Arc<Mutex<Vec<(i32, String)>>>);
    impl EventSink for CaptureSink {
        fn on_event(&self, event_type: i32, json_data: &str) {
            self.0.lock().push((event_type, json_data.to_string()));
        }
    }

    #[test]
    fn session_save_and_restore_preserves_track_queue_and_position() {

        let mut t2 = track("t2");
        t2.duration_ms = 180_000;
        let events = Arc::new(Mutex::new(Vec::new()));
        let rt = tokio::runtime::Runtime::new().unwrap();
        let rt_handle = rt.handle().clone();
        let mpris = Mpris::spawn(&rt_handle, |_| {});
        let core = Arc::new(YMusicCore {
            batch_running: AtomicBool::new(false),
            batch_cancel: AtomicBool::new(false),
            batch_cancel_tx: tokio::sync::watch::channel(false).0,
            playlist_creating: AtomicBool::new(false),
            login_gen: std::sync::atomic::AtomicU64::new(0),
            rt_handle,
            runtime: Some(rt),
            http: api::http_client(),
            state: Arc::new(Mutex::new(State {
                queue: vec![track("t1"), t2.clone()],
                unshuffled_queue: Some(vec![t2, track("t1")]),
                current: Some(1),
                position_secs: 42.5,
                duration_secs: 180.0,
                wave: Some(WaveState {
                    seed: "user:onyourwave".into(),
                    title: "Моя волна".into(),
                    session_id: "sid-1".into(),
                    batch_id: "bid-1".into(),
                    tracks: vec![track("t1")],
                    filters: vec!["settingMood:energetic".into()],
                    fetching_more: false,
                    resume_on_load: false,
                }),
                wave_selected: HashMap::from([("mood".into(), "settingMood:energetic".into())]),
                ..State::default()
            })),
            cover_sem: Arc::new(Semaphore::new(4)),
            audio: Audio::spawn(|_| {}),
            mpris,
            discord: Discord::spawn(),
            lastfm: Lastfm::disabled(),
            sink: Arc::new(CaptureSink(events.clone())),
        });

        let saved = core.snapshot_session().expect("session snapshot present");
        let dir = std::env::temp_dir().join(format!("ymusic-session-test-{}", std::process::id()));
        let settings_file = dir.join("settings.json");
        let mut settings = config::UserSettings::default();
        settings.session = Some(saved);
        config::save_settings_to(&settings_file, &settings).unwrap();

        let reloaded = config::load_settings_from(&settings_file);
        let restored_session = reloaded.session.expect("reloaded session present");
        assert_eq!(restored_session.current_index, 1);
        assert!((restored_session.position_secs - 42.5).abs() < 1e-6);

        let rt2 = tokio::runtime::Runtime::new().unwrap();
        let rt2_handle = rt2.handle().clone();
        let mpris2 = Mpris::spawn(&rt2_handle, |_| {});
        let events2 = Arc::new(Mutex::new(Vec::new()));
        let core2 = Arc::new(YMusicCore {
            batch_running: AtomicBool::new(false),
            batch_cancel: AtomicBool::new(false),
            batch_cancel_tx: tokio::sync::watch::channel(false).0,
            playlist_creating: AtomicBool::new(false),
            login_gen: std::sync::atomic::AtomicU64::new(0),
            rt_handle: rt2_handle,
            runtime: Some(rt2),
            http: api::http_client(),
            state: Arc::new(Mutex::new(State::default())),
            cover_sem: Arc::new(Semaphore::new(4)),
            audio: Audio::spawn(|_| {}),
            mpris: mpris2,
            discord: Discord::spawn(),
            lastfm: Lastfm::disabled(),
            sink: Arc::new(CaptureSink(events2.clone())),
        });
        // Wrap in async-safe drop wait via rt2 already entered above — drop handles cleanly outside block_on
        core2.apply_saved_session(restored_session);
        {
            let st2 = core2.state.lock();
            assert_eq!(st2.current, Some(1));
            assert_eq!(st2.queue.len(), 2);
            assert_eq!(st2.queue[1].id, "t2");
            assert_eq!(st2.unshuffled_queue.as_ref().unwrap()[0].id, "t2");
            assert!(!st2.audio_started);
            assert_eq!(st2.wave_selected.get("mood").map(String::as_str), Some("settingMood:energetic"));
        }
        let captured = events2.lock();
        assert!(captured.iter().any(|(t, json)| *t == EVENT_NOW_PLAYING && json.contains("\"t2\"")));
        assert!(captured.iter().any(|(t, json)| *t == EVENT_PLAYBACK_PROGRESS && json.contains("0:42") || json.contains("42")));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn artist_links_for_splits_legacy_multi_artist_string() {
        let mut legacy = track("t1");
        legacy.artist_id = Some("10".into());
        legacy.artists = "Whybaby_ff, NEEDY GIRL OVERDOSE, KOTOKO".into();
        let links = artist_links_for(&legacy);
        assert_eq!(links.len(), 3);
        assert_eq!(links[0].name, "Whybaby_ff");
        assert_eq!(links[0].id, "10");
        assert_eq!(links[1].name, "NEEDY GIRL OVERDOSE");
        assert_eq!(links[1].id, "");
        assert_eq!(links[2].name, "KOTOKO");
        assert_eq!(links[2].id, "");
    }

    #[test]
    fn track_payload_serializes_individual_artist_links() {
        let mut t = track("t1");
        t.artists = "Petite Meller, Marlon Hoffstadt".into();
        t.artist_id = Some("10".into());
        t.artist_links = vec![
            ("10".into(), "Petite Meller".into()),
            ("20".into(), "Marlon Hoffstadt".into()),
        ];
        let payload = serde_json::to_value(track_payload(&t, &HashSet::new())).unwrap();
        assert_eq!(payload["artist_links"], serde_json::json!([
            {"id": "10", "name": "Petite Meller"},
            {"id": "20", "name": "Marlon Hoffstadt"},
        ]));
    }

    #[test]
    fn toggle_pin_playlist_updates_state_and_emits_events() {
        let rt = tokio::runtime::Runtime::new().unwrap();
        let rt_handle = rt.handle().clone();
        let mpris = Mpris::spawn(&rt_handle, |_| {});
        let events = Arc::new(Mutex::new(Vec::new()));
        let core = Arc::new(YMusicCore {
            batch_running: AtomicBool::new(false),
            batch_cancel: AtomicBool::new(false),
            batch_cancel_tx: tokio::sync::watch::channel(false).0,
            playlist_creating: AtomicBool::new(false),
            login_gen: std::sync::atomic::AtomicU64::new(0),
            rt_handle,
            runtime: Some(rt),
            http: api::http_client(),
            state: Arc::new(Mutex::new(State {
                cards: vec![CardTarget::Playlist {
                    uid: 42,
                    kind: 7,
                    title: "Мой плейлист".into(),
                    subtitle: String::new(),
                    cover_uri: None,
                    section: String::new(),
                }],
                ..State::default()
            })),
            cover_sem: Arc::new(Semaphore::new(2)),
            audio: Audio::spawn(|_| {}),
            mpris,
            discord: Discord::spawn(),
            lastfm: Lastfm::disabled(),
            sink: Arc::new(CaptureSink(events.clone())),
        });

        core.toggle_pin_playlist(&serde_json::json!({"card_index": 0}));
        assert_eq!(core.state.lock().pinned_playlists.len(), 1);
        assert!(events.lock().iter().any(|(t, j)| *t == EVENT_FEATURE && j.contains("\"pinned_playlists\"") && j.contains("\"playlist:42:7\"")));
        assert!(events.lock().iter().any(|(t, j)| *t == EVENT_CARDS_LOADED && j.contains("\"pinned\":true")));

        events.lock().clear();
        core.toggle_pin_playlist(&serde_json::json!({"uid": 42, "kind": 7}));
        assert!(core.state.lock().pinned_playlists.is_empty());
        assert!(events.lock().iter().any(|(t, j)| *t == EVENT_CARDS_LOADED && j.contains("\"pinned\":false")));
    }

    #[test]
    fn toggle_shuffle_moves_current_to_front_and_reorders_queue() {
        let rt = tokio::runtime::Runtime::new().unwrap();
        let rt_handle = rt.handle().clone();
        let mpris = Mpris::spawn(&rt_handle, |_| {});
        let events = Arc::new(Mutex::new(Vec::new()));
        let core = Arc::new(YMusicCore {
            batch_running: AtomicBool::new(false),
            batch_cancel: AtomicBool::new(false),
            batch_cancel_tx: tokio::sync::watch::channel(false).0,
            playlist_creating: AtomicBool::new(false),
            login_gen: std::sync::atomic::AtomicU64::new(0),
            rt_handle,
            runtime: Some(rt),
            http: api::http_client(),
            state: Arc::new(Mutex::new(State {
                queue: vec![track("a"), track("b"), track("c"), track("d")],
                current: Some(2),
                ..State::default()
            })),
            cover_sem: Arc::new(Semaphore::new(2)),
            audio: Audio::spawn(|_| {}),
            mpris,
            discord: Discord::spawn(),
            lastfm: Lastfm::disabled(),
            sink: Arc::new(CaptureSink(events.clone())),
        });

        core.clone().toggle_shuffle();
        {
            let st = core.state.lock();
            assert!(st.shuffle);
            assert_eq!(st.current, Some(0));
            assert_eq!(st.queue[0].id, "c");
            assert_ne!(
                st.queue[1..].iter().map(|t| t.id.as_str()).collect::<Vec<_>>(),
                vec!["a", "b", "d"]
            );
        }

        core.clone().toggle_shuffle();
        {
            let st = core.state.lock();
            assert!(!st.shuffle);
            assert_eq!(st.current, Some(2));
            assert_eq!(
                st.queue.iter().map(|t| t.id.as_str()).collect::<Vec<_>>(),
                vec!["a", "b", "c", "d"]
            );
        }
    }

    #[test]
    fn should_fetch_view_deduplicates_and_respects_cooldown() {
        let rt = tokio::runtime::Runtime::new().unwrap();
        let rt_handle = rt.handle().clone();
        let mpris = Mpris::spawn(&rt_handle, |_| {});
        let events = Arc::new(Mutex::new(Vec::new()));
        let core = Arc::new(YMusicCore {
            batch_running: AtomicBool::new(false),
            batch_cancel: AtomicBool::new(false),
            batch_cancel_tx: tokio::sync::watch::channel(false).0,
            playlist_creating: AtomicBool::new(false),
            login_gen: std::sync::atomic::AtomicU64::new(0),
            rt_handle,
            runtime: Some(rt),
            http: api::http_client(),
            state: Arc::new(Mutex::new(State::default())),
            cover_sem: Arc::new(Semaphore::new(2)),
            audio: Audio::spawn(|_| {}),
            mpris,
            discord: Discord::spawn(),
            lastfm: Lastfm::disabled(),
            sink: Arc::new(CaptureSink(events)),
        });

        assert!(core.should_fetch_view("likes", Duration::from_secs(25)));
        assert!(!core.should_fetch_view("likes", Duration::from_secs(25)));

        core.finish_fetching_view("likes", false);
        assert!(core.should_fetch_view("likes", Duration::from_secs(25)));

        core.state.lock().views.insert(
            "likes".into(),
            CachedView {
                cover_uri: None,
                title: "Мне нравится".into(),
                subtitle: String::new(),
                cards: Vec::new(),
                tracks: vec![track("1")],
                viewed_artist_id: None,
                artist_view: None,
            },
        );
        core.finish_fetching_view("likes", true);
        assert!(!core.should_fetch_view("likes", Duration::from_secs(25)));
    }

    #[test]
    fn apply_cached_view_updates_when_returned_to_same_active_key() {
        let rt = tokio::runtime::Runtime::new().unwrap();
        let rt_handle = rt.handle().clone();
        let mpris = Mpris::spawn(&rt_handle, |_| {});
        let events = Arc::new(Mutex::new(Vec::new()));
        let core = Arc::new(YMusicCore {
            batch_running: AtomicBool::new(false),
            batch_cancel: AtomicBool::new(false),
            batch_cancel_tx: tokio::sync::watch::channel(false).0,
            playlist_creating: AtomicBool::new(false),
            login_gen: std::sync::atomic::AtomicU64::new(0),
            rt_handle,
            runtime: Some(rt),
            http: api::http_client(),
            state: Arc::new(Mutex::new(State::default())),
            cover_sem: Arc::new(Semaphore::new(2)),
            audio: Audio::spawn(|_| {}),
            mpris,
            discord: Discord::spawn(),
            lastfm: Lastfm::disabled(),
            sink: Arc::new(CaptureSink(events.clone())),
        });

        let v1 = core.begin_cached_view(Some("likes"), 2, "Мне нравится".into(), String::new());
        let _v2 = core.begin_cached_view(None, 7, "Загружено".into(), String::new());
        let _v3 = core.begin_cached_view(Some("likes"), 2, "Мне нравится".into(), String::new());
        events.lock().clear();

        let applied = core.apply_cached_view(
            v1,
            Some("likes"),
            Some("Мне нравится".into()),
            Some(String::new()),
            Vec::new(),
            vec![track("42")],
            None,
            None,
        );
        assert!(applied);
        assert_eq!(core.state.lock().list.len(), 1);
        assert!(events.lock().iter().any(|(t, j)| *t == EVENT_TRACKS_LOADED && j.contains("\"42\"")));
    }

    #[test]
    fn extract_oauth_token_handles_raw_prefix_and_redirect_urls() {
        assert_eq!(extract_oauth_token("  y0_abc123  "), "y0_abc123");
        assert_eq!(extract_oauth_token("OAuth y0_abc123"), "y0_abc123");
        assert_eq!(extract_oauth_token("Bearer \"y0_abc123\""), "y0_abc123");
        assert_eq!(
            extract_oauth_token("https://music.yandex.ru/#access_token=y0_url999&token_type=bearer&expires_in=31536000"),
            "y0_url999"
        );
        assert_eq!(
            extract_oauth_token("https://oauth.yandex.ru/verification_code?access_token=y0_q777#state=1"),
            "y0_q777"
        );
    }

    #[test]
    fn is_auth_rejected_error_ignores_network_and_generic_errors() {
        assert!(!is_auth_rejected_error(&anyhow::anyhow!("нет соединения с сервером: dns 127.0.0.1:4030")));
        assert!(!is_auth_rejected_error(&anyhow::anyhow!("HTTP 403: rate limit")));
        assert!(!is_auth_rejected_error(&anyhow::anyhow!("HTTP 502: bad gateway")));
        assert!(is_auth_rejected_error(&anyhow::anyhow!("HTTP 401: unauthorized")));
        assert!(is_auth_rejected_error(&anyhow::anyhow!("HTTP 401")));
        assert!(is_auth_rejected_error(&anyhow::anyhow!("токен недействителен")));
        assert!(is_auth_rejected_error(&anyhow::anyhow!("HTTP 403: invalid-token")));
    }
}

fn strip_wrapping(v: &str) -> &str {
    v.trim().trim_matches(|c| c == '"' || c == '\'').trim()
}

pub fn extract_oauth_token(raw: &str) -> String {
    let mut s = strip_wrapping(raw);
    if let Some((_, rest)) = s.split_once("access_token=") {
        let token = rest
            .split(['&', '#', ' ', '\t', '\r', '\n'])
            .next()
            .unwrap_or("");
        let cleaned = strip_wrapping(token);
        if !cleaned.is_empty() {
            return cleaned.to_string();
        }
    }
    let lower = s.to_ascii_lowercase();
    if lower.starts_with("oauth ") {
        s = strip_wrapping(&s[6..]);
    } else if lower.starts_with("bearer ") {
        s = strip_wrapping(&s[7..]);
    }
    s.to_string()
}

fn has_http_status(msg: &str, code: u16) -> bool {
    let needle = format!("HTTP {code}");
    msg.match_indices(&needle).any(|(idx, _)| {
        let after = &msg[idx + needle.len()..];
        after.is_empty() || after.starts_with(':') || after.starts_with(char::is_whitespace)
    })
}

pub fn is_auth_rejected_error(e: &anyhow::Error) -> bool {
    let msg = format!("{e:#}");
    has_http_status(&msg, 401)
        || msg.contains("токен недействителен")
        || (has_http_status(&msg, 403)
            && (msg.contains("invalid-token")
                || msg.contains("unauthorized")
                || msg.contains("expired")))
}

impl YMusicCore {
    pub fn send_feature(&self, kind: &str, mut data: serde_json::Value) {
        data["type"] = kind.into();
        self.send_event(EVENT_FEATURE, &data);
    }

    fn send_history_tracks(&self, tracks: Vec<Track>) {
        let st = self.state.lock();
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
                    let st = self.state.lock();
                    crate::wave::validate(&st.wave_groups, &selections)
                };
                match validated {
                    Ok(seeds) => self.start_wave_filtered("user:onyourwave".into(), "Моя волна".into(), seeds, Some(selections)),
                    Err(e) => self.send_feature("wave_error", serde_json::json!({"message": e.to_string()})),
                }
            }
            "history" => {
                self.send_history_tracks(crate::history::load());
                if let Some(api) = self.api() {
                    let this = self.clone();
                    self.rt_handle.spawn(async move {
                        if let Ok(remote) = api.music_history().await {
                            if let Ok(merged) = tokio::task::spawn_blocking(move || crate::history::merge_remote(remote)).await.unwrap_or(Err(std::io::Error::other("join"))) {
                                this.send_history_tracks(merged);
                            }
                        }
                    });
                }
            }
            "clear_history" => {
                if crate::history::clear().is_ok() { self.send_history_tracks(Vec::new()); }
                else { self.error("Не удалось очистить историю"); }
            }
            "play_history" => {
                let tracks = crate::history::load();
                let Some(id) = cmd["id"].as_str() else { return };
                let Some(index) = tracks.iter().position(|t| t.id == id) else { return };
                {
                    let mut st = self.state.lock();
                    st.queue = tracks;
                    st.wave = None;
                    st.unshuffled_queue = None;
                }
                self.play_index(index, true);
            }
            "search" => self.search_with_filter(cmd["query"].as_str().unwrap_or("").trim().into(), cmd["filter"].as_str().unwrap_or("all").into()),
            "open_playlist" => {
                let Some(uid) = cmd["uid"].as_u64() else { return };
                let Some(kind) = cmd["kind"].as_u64() else { return };
                let title = cmd["title"].as_str().unwrap_or("Плейлист").to_string();
                self.clone().open_playlist(uid, kind, title);
            }
            "toggle_pin_playlist" => self.toggle_pin_playlist(&cmd),
            "create_playlist" => {
                let Some(api) = self.api() else { self.error("Для создания плейлиста нужен вход"); return };
                if self.playlist_creating.swap(true, Ordering::SeqCst) { return; }
                let uid = self.state.lock().uid;
                let title = cmd["title"].as_str().unwrap_or("").to_string();
                let private = cmd["private"].as_bool().unwrap_or(true);
                let this = self.clone();
                self.rt_handle.spawn(async move {
                    let result = api.create_playlist(uid, &title, private).await;
                    this.playlist_creating.store(false, Ordering::SeqCst);
                    if this.state.lock().uid != uid { return; }
                    match result {
                        Ok(p) => {
                            {
                                let mut st = this.state.lock();
                                st.views.remove("playlists");
                                st.view_fetched_at.remove("playlists");
                                st.view_fetched_at.remove("home");
                            }
                            this.send_feature("create_playlist", serde_json::json!({"ok": true, "title": p.title}));
                            let page = this.state.lock().page;
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
            "track_wave" => {
                let Some(id) = cmd["id"].as_str().filter(|s| !s.is_empty()) else { return };
                let title = cmd["title"].as_str().filter(|s| !s.is_empty()).unwrap_or("трек");
                self.start_wave(format!("track:{id}"), format!("Волна: {title}"));
            }
            "set_speed" => {
                let speed = cmd["speed"].as_f64().unwrap_or(1.0) as f32;
                self.audio.set_speed(speed);
            }
            "set_sleep_fade" => {
                let factor = cmd["gain"]
                    .as_f64()
                    .or_else(|| cmd["factor"].as_f64())
                    .unwrap_or(1.0) as f32;
                self.audio.set_sleep_fade(factor);
            }
            "set_audio_quality" => {
                let q = match cmd["quality"].as_str().unwrap_or("hq") {
                    "lossless" => "lossless",
                    "nq" => "nq",
                    _ => "hq",
                };
                let (changed, reload_target) = {
                    let mut st = self.state.lock();
                    let changed = st.audio_quality != q;
                    st.audio_quality = q.to_string();
                    let target = if changed && st.playing {
                        st.current.map(|idx| (idx, st.position_secs))
                    } else {
                        None
                    };
                    (changed, target)
                };
                let q_owned = q.to_string();
                config::update_settings(|s| s.audio_quality = q_owned);
                self.send_view_feature();
                if changed {
                    let this = self.clone();
                    self.rt_handle.spawn(async move {
                        let _ = tokio::task::spawn_blocking(cache::clear_track_cache).await;
                        if let Some((idx, pos)) = reload_target {
                            this.play_index_at(idx, false, Some(pos));
                        }
                    });
                }
            }
            "set_download_quality" => {
                let q = match cmd["quality"].as_str().unwrap_or("mp3") {
                    "flac" => "flac",
                    "match" => "match",
                    _ => "mp3",
                };
                self.state.lock().download_quality = q.to_string();
                let q_owned = q.to_string();
                config::update_settings(|s| s.download_quality = q_owned);
                self.send_view_feature();
            }
            "set_mod_track_overrides" => {
                let mod_id = cmd["modId"].as_str().unwrap_or("").trim().to_string();
                if mod_id.is_empty() {
                    return;
                }
                let mut parsed: HashMap<String, ModTrackOverride> = HashMap::new();
                if let Some(obj) = cmd["overrides"].as_object() {
                    for (track_id, val) in obj {
                        if let Ok(ov) = serde_json::from_value::<ModTrackOverride>(val.clone()) {
                            parsed.insert(track_id.clone(), ov);
                        }
                    }
                }
                {
                    let mut guard = mod_overrides().write();
                    if parsed.is_empty() {
                        guard.tracks.remove(&mod_id);
                    } else {
                        guard.tracks.insert(mod_id, parsed);
                    }
                }
                self.refresh_rows();
            }
            "set_mod_album_injections" => {
                let mod_id = cmd["modId"].as_str().unwrap_or("").trim().to_string();
                let album_id = cmd["albumId"].as_str().unwrap_or("").trim().to_string();
                if mod_id.is_empty() || album_id.is_empty() {
                    return;
                }
                let mut injected = Vec::new();
                if let Some(arr) = cmd["tracks"].as_array() {
                    for item in arr {
                        let id = item["id"].as_str().unwrap_or("").trim().to_string();
                        let title = item["title"].as_str().unwrap_or("").trim().to_string();
                        if id.is_empty() || title.is_empty() {
                            continue;
                        }
                        let artists = item["artists"].as_str().unwrap_or("").trim().to_string();
                        let album_title = item["album"].as_str().unwrap_or("").trim().to_string();
                        let cover_uri = item["coverUrl"]
                            .as_str()
                            .map(str::trim)
                            .filter(|s| !s.is_empty())
                            .map(String::from);
                        let duration_ms = item["durationMs"].as_u64().unwrap_or(0);
                        let audio_url = item["audioUrl"].as_str().map(str::trim).filter(|s| !s.is_empty()).map(String::from);
                        let audio_track_id = item["audioTrackId"].as_str().map(str::trim).filter(|s| !s.is_empty()).map(String::from);
                        let local_file = item["localFile"].as_str().map(str::trim).filter(|s| !s.is_empty()).map(String::from);
                        let codec = item["codec"].as_str().map(str::trim).filter(|s| !s.is_empty()).map(String::from);

                        if audio_url.is_some() || audio_track_id.is_some() || local_file.is_some() {
                            let mut guard = mod_overrides().write();
                            guard
                                .tracks
                                .entry(mod_id.clone())
                                .or_default()
                                .entry(id.clone())
                                .or_default()
                                .clone_from(&ModTrackOverride {
                                    title: Some(title.clone()),
                                    artists: (!artists.is_empty()).then_some(artists.clone()),
                                    album: (!album_title.is_empty()).then_some(album_title.clone()),
                                    cover_url: cover_uri.clone(),
                                    available: Some(true),
                                    duration_ms: (duration_ms > 0).then_some(duration_ms),
                                    audio_url,
                                    audio_track_id,
                                    local_file,
                                    codec,
                                });
                        }

                        injected.push(Track {
                            id,
                            title,
                            artists,
                            artist_id: None,
                            artist_links: Vec::new(),
                            album_id: Some(album_id.clone()),
                            album_title,
                            duration_ms,
                            cover_uri,
                            available: true,
                            r128_i: None,
                            r128_tp: None,
                            is_ai: false,
                            has_sync_lyrics: false,
                            has_text_lyrics: false,
                        });
                    }
                }
                {
                    let mut guard = mod_overrides().write();
                    let mod_map = guard.album_injections.entry(mod_id).or_default();
                    if injected.is_empty() {
                        mod_map.remove(&album_id);
                    } else {
                        mod_map.insert(album_id, injected);
                    }
                }
            }
            "clear_mod_overrides" => {
                let mod_id = cmd["modId"].as_str().unwrap_or("").trim().to_string();
                if mod_id.is_empty() {
                    return;
                }
                {
                    let mut guard = mod_overrides().write();
                    guard.tracks.remove(&mod_id);
                    guard.album_injections.remove(&mod_id);
                }
                self.refresh_rows();
            }
            "set_normalize_volume" => {
                let enabled = cmd["enabled"].as_bool().unwrap_or(true);
                let gain = {
                    let mut st = self.state.lock();
                    st.normalize_volume = enabled;
                    if enabled {
                        current_track(&st).map(Track::r128_gain).unwrap_or(1.0)
                    } else {
                        1.0
                    }
                };
                self.audio.set_track_gain(gain);
                config::update_settings(|s| s.normalize_volume = enabled);
                self.send_view_feature();
            }
            "set_ai_music_behavior" => {
                let behavior = match cmd["behavior"].as_str().unwrap_or("skip_if_not_liked") {
                    "dislike" => "dislike",
                    "dislike_if_not_liked" => "dislike_if_not_liked",
                    "skip" => "skip",
                    "skip_if_not_liked" => "skip_if_not_liked",
                    "nothing" => "nothing",
                    _ => "skip_if_not_liked",
                };
                self.state.lock().ai_music_behavior = behavior.to_string();
                let owned = behavior.to_string();
                config::update_settings(|s| s.ai_music_behavior = owned);
                self.send_view_feature();
            }
            "set_ai_strict_tracks" => {
                let strict = cmd["enabled"].as_bool().unwrap_or(false);
                self.state.lock().ai_strict_tracks = strict;
                config::update_settings(|s| s.ai_strict_tracks = strict);
                self.send_view_feature();
            }
            "set_show_ai_labels" => {
                let show = cmd["enabled"].as_bool().unwrap_or(true);
                self.state.lock().show_ai_labels = show;
                config::update_settings(|s| s.show_ai_labels = show);
                self.send_view_feature();
                self.refresh_rows();
            }
            "lastfm_auth_start" => {
                self.lastfm.start_auth();
            }
            "lastfm_auth_cancel" => {
                self.lastfm.cancel_auth();
            }
            "lastfm_disconnect" => {
                self.lastfm.disconnect();
            }
            "lastfm_clear_custom_keys" => {
                self.lastfm.clear_custom_keys();
            }
            "set_lastfm_config" => {
                let cur = config::load_settings();
                let next = LastfmConfig {
                    enabled: cmd["enabled"].as_bool().unwrap_or(cur.lastfm_enabled),
                    now_playing: cmd["nowPlaying"].as_bool().unwrap_or(cur.lastfm_now_playing),
                    love_on_like: cmd["loveOnLike"].as_bool().unwrap_or(cur.lastfm_love_on_like),
                    skip_ai: cmd["skipAi"].as_bool().unwrap_or(cur.lastfm_skip_ai),
                    custom_api_key: cmd["customApiKey"]
                        .as_str()
                        .map(str::to_string)
                        .unwrap_or_else(|| cur.lastfm_custom_api_key.unwrap_or_default()),
                    custom_api_secret: cmd["customApiSecret"]
                        .as_str()
                        .map(str::to_string)
                        .unwrap_or_else(|| cur.lastfm_custom_api_secret.unwrap_or_default()),
                };
                self.lastfm.set_config(next);
            }
            "search_suggest" => {
                let part = cmd["part"].as_str().unwrap_or("").trim().to_string();
                let (seq, history) = {
                    let mut st = self.state.lock();
                    st.search_suggest_seq = st.search_suggest_seq.wrapping_add(1);
                    if part.is_empty() {
                        st.quick_search_tracks.clear();
                        st.quick_search_best = None;
                    }
                    (st.search_suggest_seq, st.search_history.clone())
                };
                if part.is_empty() {
                    self.send_feature("search_suggest", serde_json::json!({
                        "part": "",
                        "suggestions": [],
                        "tracks": [],
                        "best": serde_json::Value::Null,
                        "history": history,
                    }));
                    return;
                }
                let Some(api) = self.api() else { return };
                let this = self.clone();
                self.rt_handle.spawn(async move {
                    let (suggest_res, tracks_res) = tokio::join!(
                        api.search_suggest_rich(&part),
                        api.search_filtered_page(&part, "track", 0)
                    );
                    let suggestions = suggest_res.as_ref().map(|r| r.suggestions.clone()).unwrap_or_default();
                    let best_raw = suggest_res
                        .as_ref()
                        .ok()
                        .and_then(|r| r.best.clone())
                        .or_else(|| tracks_res.as_ref().ok().and_then(|r| r.best.clone()));

                    let mut quick_tracks: Vec<Track> = Vec::new();
                    let mut seen_ids = HashSet::new();
                    if let Some(api::SearchBest::Track(ref bt)) = best_raw {
                        seen_ids.insert(bt.id.clone());
                        quick_tracks.push(bt.clone());
                    }
                    if let Ok(ref tr) = tracks_res {
                        for t in &tr.tracks {
                            if quick_tracks.len() >= 5 {
                                break;
                            }
                            if seen_ids.insert(t.id.clone()) {
                                quick_tracks.push(t.clone());
                            }
                        }
                    }

                    let quick_best = best_raw.filter(|b| !matches!(b, api::SearchBest::Track(_)));
                    let (payload_tracks, payload_best, history) = {
                        let mut st = this.state.lock();
                        if st.search_suggest_seq != seq {
                            return;
                        }
                        st.quick_search_tracks = quick_tracks.clone();
                        st.quick_search_best = quick_best.clone();
                        let pt = quick_tracks_payload(&quick_tracks, &st.liked_ids);
                        let pb = quick_best
                            .as_ref()
                            .map(|b| search_best_payload(b, &st.liked_ids))
                            .unwrap_or(serde_json::Value::Null);
                        (pt, pb, st.search_history.clone())
                    };
                    this.send_feature("search_suggest", serde_json::json!({
                        "part": part,
                        "suggestions": suggestions,
                        "tracks": payload_tracks,
                        "best": payload_best,
                        "history": history,
                    }));
                });
            }
            "play_quick_track" => {
                let Some(id) = cmd["id"].as_str().filter(|s| !s.is_empty()) else { return };
                let idx_found = {
                    let mut st = self.state.lock();
                    if let Some(pos) = st.quick_search_tracks.iter().position(|t| t.id == id) {
                        st.queue = st.quick_search_tracks.clone();
                        st.wave = None;
                        st.unshuffled_queue = None;
                        Some(pos)
                    } else if let Some(api::SearchBest::Track(ref bt)) = st.search_best
                        && bt.id == id
                    {
                        st.queue = vec![bt.clone()];
                        st.wave = None;
                        st.unshuffled_queue = None;
                        Some(0)
                    } else if let Some(pos) = st.list.iter().position(|t| t.id == id) {
                        st.queue = st.list.clone();
                        st.wave = None;
                        st.unshuffled_queue = None;
                        Some(pos)
                    } else {
                        None
                    }
                };
                if let Some(index) = idx_found {
                    self.play_index(index, true);
                }
            }
            "open_search_best" => {
                let source = cmd["source"].as_str().unwrap_or("search");
                let best = {
                    let st = self.state.lock();
                    if source == "suggest" {
                        st.quick_search_best.clone()
                    } else {
                        st.search_best.clone()
                    }
                };
                let Some(best) = best else { return };
                match best {
                    api::SearchBest::Track(t) => {
                        {
                            let mut st = self.state.lock();
                            st.queue = vec![t];
                            st.wave = None;
                            st.unshuffled_queue = None;
                        }
                        self.play_index(0, true);
                    }
                    api::SearchBest::Artist(a) => self.clone().open_artist(a.id),
                    api::SearchBest::Album(a) => self.clone().open_album(a.id),
                    api::SearchBest::Playlist(p) => self.clone().open_playlist(p.uid, p.kind, p.title),
                }
            }
            "clear_search_history" => {
                self.state.lock().search_history.clear();
                self.send_feature("search_history", serde_json::json!({ "history": [] }));
            }
            "search_more" => {
                self.search_more();
            }
            "open_chart" => {
                self.open_chart();
            }
            "similar_tracks" => {
                let Some(id) = cmd["id"].as_str().filter(|s| !s.is_empty()).map(str::to_string) else { return };
                let title = cmd["title"].as_str().filter(|s| !s.is_empty()).unwrap_or("Трек").to_string();
                self.open_similar_tracks(id, title);
            }
            "start_collection_wave" => {
                let target = {
                    let st = self.state.lock();
                    if st.page == 2 && st.uid > 0 {
                        Some((format!("playlist:{}_3", st.uid), "Волна: Мне нравится".to_string()))
                    } else if let Some(album_id) = st.active_album_id.clone() {
                        Some((format!("album:{album_id}"), "Волна по альбому".to_string()))
                    } else if let Some(p) = st.active_playlist.clone() {
                        Some((format!("playlist:{}_{}", p.uid, p.kind), format!("Волна: {}", p.title)))
                    } else if let Some((artist_id, name)) = st.viewed_artist_id.clone() {
                        Some((format!("artist:{artist_id}"), format!("Волна: {name}")))
                    } else {
                        None
                    }
                };
                if let Some((seed, title)) = target {
                    self.start_wave(seed, title);
                }
            }
            "open_dislikes" => {
                self.open_disliked_tracks();
            }
            "dislike_track" => {
                let Some(id) = cmd["id"].as_str().filter(|s| !s.is_empty()).map(str::to_string) else { return };
                let Some(api) = self.api() else { self.error("Нужен вход в аккаунт"); return };
                let uid = {
                    let mut st = self.state.lock();
                    st.liked_ids.remove(&id);
                    st.uid
                };
                let this = self.clone();
                self.rt_handle.spawn(async move {
                    match api.dislike_track(uid, &id).await {
                        Ok(()) => this.notify("Трек добавлен в «Не нравится»"),
                        Err(e) => this.error(format!("Дизлайк трека: {e}")),
                    }
                });
            }
            "undislike_track" => {
                let Some(id) = cmd["id"].as_str().filter(|s| !s.is_empty()).map(str::to_string) else { return };
                let Some(api) = self.api() else { self.error("Нужен вход в аккаунт"); return };
                let uid = self.state.lock().uid;
                let this = self.clone();
                self.rt_handle.spawn(async move {
                    match api.undislike_track(uid, &id).await {
                        Ok(()) => {
                            this.notify("Трек убран из «Не нравится»");
                            let is_dislikes = this.state.lock().active_view_key.as_deref() == Some("dislikes");
                            if is_dislikes {
                                this.state.lock().views.remove("dislikes");
                                this.open_disliked_tracks();
                            }
                        }
                        Err(e) => this.error(format!("Снятие дизлайка: {e}")),
                    }
                });
            }
            "dislike_artist" => {
                let Some(api) = self.api() else { self.error("Нужен вход в аккаунт"); return };
                let (uid, artist) = {
                    let st = self.state.lock();
                    (st.uid, st.viewed_artist_id.clone())
                };
                let Some((artist_id, artist_name)) = artist else { return };
                let this = self.clone();
                self.rt_handle.spawn(async move {
                    match api.dislike_artist(uid, &artist_id).await {
                        Ok(()) => this.notify(format!("Артист «{artist_name}» скрыт из рекомендаций")),
                        Err(e) => this.error(format!("Дизлайк артиста: {e}")),
                    }
                });
            }
            "track_credits" => {
                let Some(id) = cmd["id"].as_str().filter(|s| !s.is_empty()).map(str::to_string) else { return };
                let title = cmd["title"].as_str().unwrap_or("").to_string();
                let Some(api) = self.api() else {
                    self.error("Для просмотра авторов нужен вход");
                    return;
                };
                let this = self.clone();
                self.rt_handle.spawn(async move {
                    match api.track_credits(&id).await {
                        Ok(credits) => {
                            this.send_feature("track_credits", serde_json::json!({
                                "id": id,
                                "title": title,
                                "credits": credits,
                            }));
                        }
                        Err(e) => this.error(format!("Авторы трека: {e}")),
                    }
                });
            }
            "copy_track_link" => {
                let Some(id) = cmd["id"].as_str().filter(|s| !s.is_empty()) else { return };
                let album_id = self.find_track(id).and_then(|t| t.album_id).filter(|a| !a.is_empty());
                let url = match album_id {
                    Some(album_id) => format!("https://music.yandex.ru/album/{album_id}/track/{id}"),
                    None => format!("https://music.yandex.ru/track/{id}"),
                };
                self.send_feature("copy_track_link", serde_json::json!({
                    "id": id,
                    "url": url,
                }));
                self.notify("Ссылка на трек скопирована");
            }
            "toggle_like_collection" => {
                self.toggle_like_collection();
            }
            "delete_playlist" => {
                self.delete_active_playlist();
            }
            "rename_playlist" => {
                let title = cmd["title"].as_str().unwrap_or("").trim().to_string();
                if !title.is_empty() {
                    self.rename_active_playlist(title);
                }
            }
            "remove_from_playlist" => {
                let Some(track_id) = cmd["id"].as_str().filter(|s| !s.is_empty()).map(str::to_string) else { return };
                self.remove_track_from_active_playlist(track_id);
            }
            "pause_playback" => {
                self.pause_if_playing();
            }
            "lyrics" => {
                let (track_id, meta, options) = {
                    let st = self.state.lock();
                    let cur = current_track(&st);
                    let id = cmd["id"]
                        .as_str()
                        .filter(|s| !s.is_empty())
                        .map(str::to_string)
                        .or_else(|| cur.map(|t| t.id.clone()));
                    let found = id.as_deref().and_then(|target| {
                        cur.filter(|t| t.id == target)
                            .or_else(|| st.queue.iter().find(|t| t.id == target))
                            .or_else(|| st.list.iter().find(|t| t.id == target))
                    });
                    let meta = found.map(|t| crate::api::LyricsQueryMeta {
                        title: t.title.clone(),
                        artist: t
                            .artist_links
                            .first()
                            .map(|(_, name)| name.clone())
                            .filter(|s| !s.is_empty())
                            .unwrap_or_else(|| t.artists.clone()),
                        album: t.album_title.clone(),
                        duration_secs: if t.duration_ms > 0 {
                            t.duration_ms as f64 / 1000.0
                        } else {
                            st.duration_secs
                        },
                        has_sync_lyrics: if t.has_sync_lyrics || t.has_text_lyrics {
                            Some(t.has_sync_lyrics)
                        } else {
                            None
                        },
                        has_text_lyrics: if t.has_sync_lyrics || t.has_text_lyrics {
                            Some(t.has_text_lyrics)
                        } else {
                            None
                        },
                    });
                    let options = crate::api::LyricsFetchOptions {
                        source_mode: crate::api::LyricsSourceMode::from_str_opt(cmd["sourceMode"].as_str()),
                        prefer_word_sync: cmd["preferWordSync"].as_bool().unwrap_or(true),
                        lrclib_base_url: cmd["lrclibUrl"]
                            .as_str()
                            .unwrap_or("https://lrclib.net")
                            .to_string(),
                    };
                    (id, meta, options)
                };
                let Some(track_id) = track_id else { return };
                let Some(api) = self.api() else {
                    self.send_feature("lyrics", serde_json::json!({
                        "trackId": track_id,
                        "synced": false,
                        "wordSynced": false,
                        "source": "",
                        "lines": [],
                        "writers": "",
                        "major": "",
                        "message": "Для загрузки текста нужен вход в аккаунт"
                    }));
                    return;
                };
                let this = self.clone();
                self.rt_handle.spawn(async move {
                    match api.track_lyrics(&track_id, meta.as_ref(), &options).await {
                        Ok(lyrics) => {
                            let message = if lyrics.lines.is_empty() {
                                "Текст для этого трека не найден"
                            } else {
                                ""
                            };
                            this.send_feature("lyrics", serde_json::json!({
                                "trackId": track_id,
                                "synced": lyrics.synced,
                                "wordSynced": lyrics.word_synced,
                                "source": lyrics.source,
                                "lines": lyrics.lines,
                                "writers": lyrics.writers,
                                "major": lyrics.major,
                                "message": message
                            }));
                        }
                        Err(e) => {
                            this.send_feature("lyrics", serde_json::json!({
                                "trackId": track_id,
                                "synced": false,
                                "wordSynced": false,
                                "source": "",
                                "lines": [],
                                "writers": "",
                                "major": "",
                                "message": format!("Не удалось загрузить текст: {e}")
                            }));
                        }
                    }
                });
            }
            _ => (),
        }
    }

    fn edit_queue(&self, cmd: &serde_json::Value) {
        let op = cmd["operation"].as_str().unwrap_or("");
        let index = cmd["index"].as_u64().unwrap_or(u64::MAX) as usize;
        let mut st = self.state.lock();
        if !edit_queue_state(&mut st, op, index, cmd["id"].as_str()) { return; }
        drop(st);
        self.send_queue();
        self.refresh_rows();
        self.persist_session();
    }

    pub fn download_collection(self: Arc<Self>) {
        let Some(api) = self.api() else { self.error("Для загрузки нужен вход"); return };
        let (tracks, title, uid) = {
            let st = self.state.lock();
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
                if this.batch_cancel.load(Ordering::SeqCst) || this.state.lock().uid != uid { break; }
                this.send_feature("batch", serde_json::json!({"running": true, "done": done, "total": total, "failed": failed, "title": track.title}));
                let download = async {
                    if !cache::is_offline(&track.id) {
                        anyhow::ensure!(track.available, "трек недоступен");
                        let url = api.track_direct_url(&track.id).await?;
                        let path = cache::offline_track_path(&track.id).ok_or_else(|| anyhow::anyhow!("нет каталога данных"))?;
                        cache::download_to_file(api.http(), &url, &path).await?;
                    }
                    cache::download_offline_cover(api.http(), &track).await;
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
            let showing_downloads = this.state.lock().page == 7;
            if showing_downloads { this.clone().load_downloads(); }
            if !cancelled && failed == 0 {
                this.notify(format!("Загрузка завершена: {done}/{total}"));
            } else {
                this.error(format!("{}: {done}/{total}, ошибок: {failed}", if cancelled { "Загрузка остановлена" } else { "Загрузка завершена" }));
            }
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
                login_gen: std::sync::atomic::AtomicU64::new(0),
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
                discord: Discord::spawn_with_sink(sink.clone()),
                lastfm: Lastfm::spawn_with_sink(rt_handle.clone(), api::http_client(), sink.clone()),
                sink,
            }
        });

        let settings = config::load_settings();
        core.lastfm.load_initial(&settings);
        let initial_vol = settings.volume;
        core.audio.set_volume(perceptual(initial_vol));
        core.mpris.set_volume(initial_vol);
        {
            let mut st = core.state.lock();
            st.repeat_mode = settings.repeat_mode;
            st.shuffle = settings.shuffle;
            st.last_unmuted_volume = if initial_vol > 0.001 { initial_vol } else { 0.7 };
            st.volume = initial_vol;
            st.pinned_playlists = settings.pinned_playlists;
            st.audio_quality = if ["lossless", "hq", "nq"].contains(&settings.audio_quality.as_str()) {
                settings.audio_quality
            } else {
                "hq".to_string()
            };
            st.download_quality = if ["mp3", "flac", "match"].contains(&settings.download_quality.as_str()) {
                settings.download_quality
            } else {
                "mp3".to_string()
            };
            st.normalize_volume = settings.normalize_volume;
            st.ai_music_behavior = if [
                "dislike",
                "dislike_if_not_liked",
                "skip",
                "skip_if_not_liked",
                "nothing",
            ]
            .contains(&settings.ai_music_behavior.as_str())
            {
                settings.ai_music_behavior
            } else {
                "skip_if_not_liked".to_string()
            };
            st.ai_strict_tracks = settings.ai_strict_tracks;
            st.show_ai_labels = settings.show_ai_labels;
            st.wave_selected = settings.wave_selected.clone();
        }

        core.send_playback_state(false);
        core.send_pinned_playlists();
        core.send_view_feature();
        core.send_feature("wave_applied", serde_json::json!({"selected": settings.wave_selected}));
        if let Some(session) = settings.session {
            core.apply_saved_session(session);
        }

        if let Some(token) = config::load_token() {
            let api = Api::new(core.http.clone(), token.clone());
            let cached_name = settings
                .user_name
                .filter(|s| !s.trim().is_empty())
                .unwrap_or_else(|| "Пользователь".to_string());
            let cached_avatar = settings.user_avatar_url.unwrap_or_default();
            let has_avatar = !cached_avatar.is_empty();
            {
                let mut st = core.state.lock();
                st.api = Some(api);
                st.uid = settings.user_uid;
                if st.liked_ids.is_empty()
                    && let Some(likes_view) = cache::load_view::<CachedView>("likes")
                {
                    st.liked_ids = likes_view.tracks.into_iter().map(|t| t.id).collect();
                }
            }
            core.send_event(EVENT_LOGIN_STATUS, &LoginStatusPayload {
                logged_in: true,
                busy: false,
                user_name: cached_name,
                user_avatar: cached_avatar,
                user_has_avatar: has_avatar,
            });
            if core.state.lock().page != 7 {
                core.clone().load_home();
            }
            core.clone().verify_startup_account(token);
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
        self.persist_session_sync();
        self.audio.stop();
        self.discord.set_stopped();
        self.lastfm.set_stopped();
    }

    pub fn set_discord_enabled(&self, enabled: bool) {
        self.discord.set_enabled(enabled);
    }

    pub fn set_discord_config(&self, config: crate::discord::DiscordConfig) {
        self.discord.set_config(config);
    }

    pub fn send_event(&self, event_type: i32, payload: &impl Serialize) {
        if let Ok(json) = serde_json::to_string(payload) {
            self.sink.on_event(event_type, &json);
        }
    }

    pub fn send_playback_state(&self, buffering: bool) {
        let payload = {
            let st = self.state.lock();
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
        self.state.lock().playing = playing;
        self.send_playback_state(buffering);
    }

    pub fn error(&self, msg: impl Into<String>) {
        self.send_event(EVENT_STATUS_MSG, &StatusPayload {
            text: msg.into(),
        });
    }

    pub fn notify(&self, msg: impl Into<String>) {
        self.send_feature("toast", serde_json::json!({"message": msg.into()}));
    }

    pub fn api(&self) -> Option<Api> {
        self.state.lock().api.clone()
    }

    pub fn generation(&self) -> u64 {
        self.state.lock().generation
    }

    pub fn cancel_login(&self) {
        self.login_gen.fetch_add(1, Ordering::SeqCst);
        if self.state.lock().api.is_none() {
            self.send_event(EVENT_LOGIN_STATUS, &LoginStatusPayload {
                logged_in: false,
                busy: false,
                user_name: String::new(),
                user_avatar: String::new(),
                user_has_avatar: false,
            });
        }
    }

    pub fn login_device(self: Arc<Self>) {
        let my_gen = self.login_gen.fetch_add(1, Ordering::SeqCst) + 1;
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
                    if this.login_gen.load(Ordering::SeqCst) != my_gen {
                        return;
                    }
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

            if this.login_gen.load(Ordering::SeqCst) != my_gen {
                return;
            }

            this.send_event(EVENT_LOGIN_DEVICE_CODE, &DeviceCodePayload {
                user_code: code.user_code.clone(),
                verification_url: code.verification_url.clone(),
            });

            let deadline = tokio::time::Instant::now() + Duration::from_secs(code.expires_in);
            let result = loop {
                tokio::time::sleep(Duration::from_secs(code.interval.max(1))).await;
                if this.login_gen.load(Ordering::SeqCst) != my_gen {
                    return;
                }
                if tokio::time::Instant::now() > deadline {
                    break Err(anyhow::anyhow!("время на подтверждение истекло"));
                }
                match api::poll_device_token(&this.http, &code.device_code).await {
                    Ok(Some(token)) => break Ok(token),
                    Ok(None) => continue,
                    Err(e) => break Err(e),
                }
            };

            if this.login_gen.load(Ordering::SeqCst) != my_gen {
                return;
            }

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

    pub fn verify_startup_account(self: Arc<Self>, token: String) {
        let this = self.clone();
        self.rt_handle.spawn(async move {
            let api = Api::new(this.http.clone(), token);
            match api.account().await {
                Ok(account) => {
                    if this.state.lock().api.is_none() {
                        return;
                    }
                    let avatar = account.avatar_url.clone().unwrap_or_default();
                    let has_avatar = !avatar.is_empty();
                    let name_for_cfg = account.name.clone();
                    let avatar_for_cfg = account.avatar_url.clone();
                    let uid_for_cfg = account.uid;
                    tokio::task::spawn_blocking(move || {
                        config::update_settings(move |s| {
                            if s.user_uid != uid_for_cfg
                                || s.user_name.as_deref() != Some(name_for_cfg.as_str())
                                || s.user_avatar_url != avatar_for_cfg
                            {
                                s.user_uid = uid_for_cfg;
                                s.user_name = Some(name_for_cfg);
                                s.user_avatar_url = avatar_for_cfg;
                            }
                        });
                    });
                    let should_reload_home = {
                        let mut st = this.state.lock();
                        if st.api.is_none() {
                            return;
                        }
                        let had_zero_uid = st.uid == 0;
                        st.uid = account.uid;
                        had_zero_uid && st.page == 0 && st.cards.is_empty()
                    };
                    this.send_event(EVENT_LOGIN_STATUS, &LoginStatusPayload {
                        logged_in: true,
                        busy: false,
                        user_name: account.name,
                        user_avatar: avatar,
                        user_has_avatar: has_avatar,
                    });
                    if should_reload_home {
                        this.clone().load_home();
                    }
                    this.clone().prefetch_likes();
                }
                Err(e) => {
                    if this.state.lock().api.is_none() {
                        return;
                    }
                    if is_auth_rejected_error(&e) {
                        {
                            let mut st = this.state.lock();
                            st.api = None;
                            st.uid = 0;
                        }
                        this.send_event(EVENT_LOGIN_STATUS, &LoginStatusPayload {
                            logged_in: false,
                            busy: false,
                            user_name: String::new(),
                            user_avatar: String::new(),
                            user_has_avatar: false,
                        });
                        if this.state.lock().page == 0
                            && cache::offline_tracks().is_ok_and(|(tracks, _)| !tracks.is_empty())
                        {
                            this.clone().load_downloads();
                        }
                        this.error(format!("Сессия истекла: {e}"));
                    } else {
                        let (page, has_cards) = {
                            let st = this.state.lock();
                            (st.page, !st.cards.is_empty() || !st.list.is_empty())
                        };
                        if page == 0
                            && !has_cards
                            && cache::offline_tracks().is_ok_and(|(tracks, _)| !tracks.is_empty())
                        {
                            this.clone().load_downloads();
                        }
                        this.notify("Нет подключения к сети — включён офлайн-режим");
                    }
                }
            }
        });
    }

    pub fn login(self: Arc<Self>, raw_token: String) {
        let token = extract_oauth_token(&raw_token);
        if token.is_empty() {
            return;
        }
        let my_gen = self.login_gen.fetch_add(1, Ordering::SeqCst) + 1;
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
                    if this.login_gen.load(Ordering::SeqCst) != my_gen {
                        return;
                    }
                    match config::save_token(&token) {
                        Ok(config::TokenSaveOutcome::Keyring) => {}
                        Ok(config::TokenSaveOutcome::FileFallback { .. }) => {
                            this.error("Системное хранилище ключей недоступно — токен сохранён в защищённый файл (0600)");
                        }
                        Err(e) => {
                            this.error(format!("Не удалось сохранить токен: {e}"));
                        }
                    }
                    let avatar = account.avatar_url.clone().unwrap_or_default();
                    let has_avatar = !avatar.is_empty();
                    let name_for_cfg = account.name.clone();
                    let avatar_for_cfg = account.avatar_url.clone();
                    let uid_for_cfg = account.uid;
                    config::update_settings(move |s| {
                        s.user_uid = uid_for_cfg;
                        s.user_name = Some(name_for_cfg);
                        s.user_avatar_url = avatar_for_cfg;
                    });
                    {
                        let mut st = this.state.lock();
                        st.api = Some(api);
                        st.uid = account.uid;
                    }
                    this.send_event(EVENT_LOGIN_STATUS, &LoginStatusPayload {
                        logged_in: true,
                        busy: false,
                        user_name: account.name,
                        user_avatar: avatar,
                        user_has_avatar: has_avatar,
                    });

                    let browsing_downloads = this.state.lock().page == 7;
                    if !browsing_downloads { this.clone().load_home(); }
                    this.clone().prefetch_likes();
                    if this.state.lock().current.is_none() {
                        this.clone().restore_session();
                    }
                }
                Err(e) => {
                    if this.login_gen.load(Ordering::SeqCst) != my_gen {
                        return;
                    }
                    let has_saved_token = config::load_token().is_some();

                    if !is_auth_rejected_error(&e) && has_saved_token {
                        let settings = config::load_settings();
                        let cached_uid = settings.user_uid;
                        let cached_name = settings
                            .user_name
                            .filter(|s| !s.trim().is_empty())
                            .unwrap_or_else(|| "Пользователь".to_string());
                        let cached_avatar = settings.user_avatar_url.unwrap_or_default();
                        let has_avatar = !cached_avatar.is_empty();

                        {
                            let mut st = this.state.lock();
                            st.api = Some(api);
                            st.uid = cached_uid;
                            if st.liked_ids.is_empty()
                                && let Some(likes_view) = cache::load_view::<CachedView>("likes")
                            {
                                st.liked_ids = likes_view.tracks.into_iter().map(|t| t.id).collect();
                            }
                        }

                        this.send_event(EVENT_LOGIN_STATUS, &LoginStatusPayload {
                            logged_in: true,
                            busy: false,
                            user_name: cached_name,
                            user_avatar: cached_avatar,
                            user_has_avatar: has_avatar,
                        });

                        let browsing_downloads = this.state.lock().page == 7;
                        if !browsing_downloads {
                            if cache::load_view::<CachedView>("home").is_some() {
                                this.clone().begin_cached_view(
                                    Some("home"),
                                    0,
                                    "Главная".into(),
                                    "Персональные плейлисты, новинки и ваша коллекция (офлайн)".into(),
                                );
                            } else if cache::offline_tracks().is_ok_and(|(tracks, _)| !tracks.is_empty()) {
                                this.clone().load_downloads();
                            }
                        }
                        this.clone().restore_session();
                        this.notify("Нет подключения к сети — включён офлайн-режим");
                    } else {
                        this.send_event(EVENT_LOGIN_STATUS, &LoginStatusPayload {
                            logged_in: false,
                            busy: false,
                            user_name: String::new(),
                            user_avatar: String::new(),
                            user_has_avatar: false,
                        });
                        if this.state.lock().page == 0
                            && cache::offline_tracks().is_ok_and(|(tracks, _)| !tracks.is_empty())
                        {
                            this.clone().load_downloads();
                        }
                        this.error(format!("Не удалось войти: {e}"));
                    }
                }
            }
        });
    }

    pub fn logout(&self) {
        self.login_gen.fetch_add(1, Ordering::SeqCst);
        self.batch_cancel.store(true, Ordering::SeqCst);
        self.batch_cancel_tx.send_replace(true);
        config::clear_token();
        config::update_settings(|s| {
            s.user_uid = 0;
            s.user_name = None;
            s.user_avatar_url = None;
            s.session = None;
            s.wave_selected.clear();
        });
        {
            let mut st = self.state.lock();
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
        self.lastfm.set_stopped();
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
            artist_links: Vec::new(),
            album: String::new(),
            cover_url: String::new(),
            has_cover: false,
            duration_ms: 0,
            duration_text: "0:00".into(),
            liked: false,
            has_artist: false,
            has_album: false,
            is_ai: false,
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
        let st = self.state.lock();
        api::cover_url(st.view_cover_uri.as_deref(), 400)
            .or_else(|| st.list.iter().find_map(|t| t.cover_url(400)))
            .unwrap_or_default()
    }

    pub fn send_pinned_playlists(&self) {
        let playlists: Vec<serde_json::Value> = {
            let st = self.state.lock();
            st.pinned_playlists
                .iter()
                .map(|p| {
                    serde_json::json!({
                        "uid": p.uid,
                        "kind": p.kind,
                        "key": format!("playlist:{}:{}", p.uid, p.kind),
                        "title": p.title,
                        "cover_url": api::cover_url(p.cover_uri.as_deref(), 100).unwrap_or_default(),
                        "has_cover": p.cover_uri.is_some(),
                    })
                })
                .collect()
        };
        self.send_feature("pinned_playlists", serde_json::json!({ "playlists": playlists }));
    }

    pub fn send_view_feature(&self) {
        let (downloadable, playlist_key, playlist_pinned, is_own_playlist, collection_kind, collection_liked, audio_quality, download_quality, normalize_volume, ai_music_behavior, ai_strict_tracks, show_ai_labels) = {
            let st = self.state.lock();
            let (key, pinned, own) = match &st.active_playlist {
                Some(p) => (
                    format!("playlist:{}:{}", p.uid, p.kind),
                    is_playlist_pinned(&st.pinned_playlists, p.uid, p.kind),
                    st.uid != 0 && p.uid == st.uid,
                ),
                None => (String::new(), false, false),
            };
            let (c_kind, c_liked) = if let Some(p) = &st.active_playlist {
                if st.uid != 0 && p.uid == st.uid {
                    ("own_playlist", false)
                } else {
                    ("playlist", st.liked_playlist_keys.contains(&format!("{}:{}", p.uid, p.kind)))
                }
            } else if let Some(aid) = &st.active_album_id {
                ("album", st.liked_album_ids.contains(aid))
            } else if let Some((arid, _)) = &st.viewed_artist_id {
                ("artist", st.liked_artist_ids.contains(arid))
            } else {
                ("", false)
            };
            let aq = if st.audio_quality.is_empty() { "hq".to_string() } else { st.audio_quality.clone() };
            let dq = if st.download_quality.is_empty() { "mp3".to_string() } else { st.download_quality.clone() };
            let ai_beh = if st.ai_music_behavior.is_empty() { "skip_if_not_liked".to_string() } else { st.ai_music_behavior.clone() };
            (st.collection_downloadable, key, pinned, own, c_kind.to_string(), c_liked, aq, dq, st.normalize_volume, ai_beh, st.ai_strict_tracks, st.show_ai_labels)
        };
        self.send_feature(
            "view",
            serde_json::json!({
                "downloadable": downloadable,
                "playlist_key": playlist_key,
                "playlist_pinned": playlist_pinned,
                "is_own_playlist": is_own_playlist,
                "collection_kind": collection_kind,
                "collection_liked": collection_liked,
                "audio_quality": audio_quality,
                "download_quality": download_quality,
                "normalize_volume": normalize_volume,
                "ai_music_behavior": ai_music_behavior,
                "ai_strict_tracks": ai_strict_tracks,
                "show_ai_labels": show_ai_labels,
            }),
        );
    }

    pub fn toggle_pin_playlist(&self, cmd: &serde_json::Value) {
        let target: Option<config::PinnedPlaylist> = {
            let st = self.state.lock();
            if let Some(idx) = cmd["card_index"].as_u64() {
                match st.cards.get(idx as usize) {
                    Some(CardTarget::Playlist { uid, kind, title, cover_uri, .. }) => Some(config::PinnedPlaylist {
                        uid: *uid,
                        kind: *kind,
                        title: title.clone(),
                        cover_uri: cover_uri.clone(),
                    }),
                    _ => None,
                }
            } else if let (Some(uid), Some(kind)) = (cmd["uid"].as_u64(), cmd["kind"].as_u64()) {
                Some(config::PinnedPlaylist {
                    uid,
                    kind,
                    title: cmd["title"].as_str().unwrap_or("Плейлист").to_string(),
                    cover_uri: cmd["cover_uri"].as_str().filter(|s| !s.is_empty()).map(str::to_string),
                })
            } else {
                st.active_playlist.clone()
            }
        };
        let Some(target) = target else { return };
        let (added, updated_pins, cards_payload) = {
            let mut st = self.state.lock();
            let added = if let Some(pos) = st.pinned_playlists.iter().position(|p| p.uid == target.uid && p.kind == target.kind) {
                st.pinned_playlists.remove(pos);
                false
            } else {
                st.pinned_playlists.push(target);
                true
            };
            let cards_p: Vec<CardItemPayload> = st.cards.iter().map(|c| card_payload(c, &st.pinned_playlists)).collect();
            (added, st.pinned_playlists.clone(), cards_p)
        };
        config::update_settings(|s| s.pinned_playlists = updated_pins);
        self.send_pinned_playlists();
        self.send_view_feature();
        if !cards_payload.is_empty() {
            self.send_event(EVENT_CARDS_LOADED, &CardsPayload { cards: cards_payload });
        }
        self.notify(if added { "Плейлист закреплён" } else { "Плейлист откреплён" });
    }

    pub fn begin_cached_view(&self, key: Option<&str>, page: i32, title: String, subtitle: String) -> u64 {
        let is_artist = key.is_some_and(|k| k.starts_with("artist:"));
        let is_playlist = key.is_some_and(|k| k.starts_with("playlist:"));
        let is_album = key.is_some_and(|k| k.starts_with("album:"));
        let (view, has_cache, eff_title, eff_subtitle, cards_payload, tracks_payload, current_idx, can_wave, artist_info) = {
            let mut st = self.state.lock();
            st.view_id += 1;
            st.page = page;
            st.active_view_key = key.map(str::to_string);
            if !is_playlist {
                st.active_playlist = None;
            }
            if !is_album {
                st.active_album_id = None;
            }
            st.collection_downloadable = key.is_some_and(|k| k == "likes" || k == "chart" || k.starts_with("album:") || k.starts_with("playlist:"));
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
                let cards_p: Vec<CardItemPayload> = c.cards.iter().map(|card| card_payload(card, &st.pinned_playlists)).collect();
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

        self.send_view_feature();
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
            let mut st = self.state.lock();
            let prev = st.views.get(k);
            let is_active = st.view_id == view || st.active_view_key.as_deref() == Some(k);
            let cached = CachedView {
                cover_uri: if is_active { st.view_cover_uri.clone() } else { prev.and_then(|p| p.cover_uri.clone()) },
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
        let tracks_for_ai = tracks.clone();
        let (tracks_p, cards_p, current_idx, current_page) = {
            let mut st = self.state.lock();
            let matches_view = st.view_id == view
                || key.is_some_and(|k| st.active_view_key.as_deref() == Some(k));
            if !matches_view {
                return false;
            }
            st.cards = cards.clone();
            st.viewed_artist_id = viewed_artist_id;
            st.viewed_artist = artist_view.clone();
            let tracks_p: Vec<TrackItemPayload> = tracks
                .iter()
                .map(|t| track_payload(t, &st.liked_ids))
                .collect();
            let cards_p: Vec<CardItemPayload> = cards.iter().map(|card| card_payload(card, &st.pinned_playlists)).collect();
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

        if !tracks_for_ai.is_empty() {
            self.spawn_ai_verification(tracks_for_ai);
        }

        true
    }

    pub fn spawn_ai_verification(&self, tracks: Vec<Track>) {
        let http = self.http.clone();
        let state = self.state.clone();
        let sink = self.sink.clone();
        self.rt_handle.spawn(async move {
            let ai_ids = crate::slopless::check_tracks_batch(&http, &tracks).await;
            if ai_ids.is_empty() {
                return;
            }
            let mut changed = false;
            let (tracks_p, queue_p, cur_list_idx, cur_queue_idx, now_payload) = {
                let mut st = state.lock();
                for t in &mut st.list {
                    if ai_ids.contains(&t.id) && !t.is_ai {
                        t.is_ai = true;
                        changed = true;
                    }
                }
                for t in &mut st.queue {
                    if ai_ids.contains(&t.id) && !t.is_ai {
                        t.is_ai = true;
                        changed = true;
                    }
                }
                for v in st.views.values_mut() {
                    for t in &mut v.tracks {
                        if ai_ids.contains(&t.id) && !t.is_ai {
                            t.is_ai = true;
                        }
                    }
                }
                if !changed {
                    return;
                }
                let tracks_p: Vec<TrackItemPayload> = st.list.iter().map(|t| track_payload(t, &st.liked_ids)).collect();
                let queue_p: Vec<TrackItemPayload> = st.queue.iter().map(|t| track_payload(t, &st.liked_ids)).collect();
                let cur_list_idx = current_list_index(&st);
                let cur_queue_idx = st.current.map_or(-1, |i| i as i32);
                let now_payload = current_track(&st).map(|t| {
                    let cover_url = cache::resolve_track_cover_url(t, 200);
                    NowPlayingPayload {
                        has_track: true,
                        id: t.id.clone(),
                        title: t.title.clone(),
                        artists: t.artists.clone(),
                        artist_links: artist_links_for(t),
                        album: t.album_title.clone(),
                        has_cover: !cover_url.is_empty(),
                        cover_url,
                        duration_ms: t.duration_ms,
                        duration_text: fmt_time(t.duration_ms as f64 / 1000.0),
                        liked: st.liked_ids.contains(&t.id),
                        has_artist: t.artist_id.is_some(),
                        has_album: t.album_id.is_some(),
                        is_ai: t.is_ai || crate::slopless::is_track_ai_fast(t),
                    }
                });
                (tracks_p, queue_p, cur_list_idx, cur_queue_idx, now_payload)
            };
            if let Ok(j) = serde_json::to_string(&TracksPayload { tracks: queue_p, current_index: cur_queue_idx }) {
                sink.on_event(EVENT_QUEUE_LOADED, &j);
            }
            if let Ok(j) = serde_json::to_string(&TracksPayload { tracks: tracks_p, current_index: cur_list_idx }) {
                sink.on_event(EVENT_TRACKS_LOADED, &j);
            }
            if let Some(np) = now_payload
                && let Ok(j) = serde_json::to_string(&np)
            {
                sink.on_event(EVENT_NOW_PLAYING, &j);
            }
        });
    }

    pub fn view_failed(&self, view: u64, what: &str, e: anyhow::Error) {
        let should_report = {
            let st = self.state.lock();
            st.view_id == view && st.list.is_empty() && st.cards.is_empty()
        };
        if should_report {
            self.error(format!("{what}: {e:#}"));
        }
    }

    pub fn should_fetch_view(&self, key: &str, cooldown: Duration) -> bool {
        let mut st = self.state.lock();
        if st.fetching_views.contains(key) {
            return false;
        }
        let has_non_empty_cache = st
            .views
            .get(key)
            .is_some_and(|v| !v.tracks.is_empty() || !v.cards.is_empty());
        if has_non_empty_cache
            && let Some(ts) = st.view_fetched_at.get(key)
            && ts.elapsed() < cooldown
        {
            return false;
        }
        st.fetching_views.insert(key.to_string());
        true
    }

    pub fn finish_fetching_view(&self, key: &str, ok: bool) {
        let mut st = self.state.lock();
        st.fetching_views.remove(key);
        if ok {
            st.view_fetched_at.insert(key.to_string(), std::time::Instant::now());
        }
    }

    pub async fn ensure_uid(&self, api: &Api) -> anyhow::Result<u64> {
        let uid = self.state.lock().uid;
        if uid != 0 {
            return Ok(uid);
        }
        let account = api.account().await?;
        let new_uid = account.uid;
        let name = account.name.clone();
        let avatar = account.avatar_url.clone();
        {
            let mut st = self.state.lock();
            st.uid = new_uid;
        }
        config::update_settings(move |s| {
            s.user_uid = new_uid;
            s.user_name = Some(name);
            s.user_avatar_url = avatar;
        });
        Ok(new_uid)
    }

    pub fn refresh_rows(&self) {
        self.send_queue();
        let (tracks_p, now_liked, current_idx) = {
            let st = self.state.lock();
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

        let st = self.state.lock();
        if let Some(raw_t) = current_track(&st) {
            let t = apply_mod_track_override(raw_t);
            let cover_url = cache::resolve_track_cover_url(&t, 400);
            self.send_event(EVENT_NOW_PLAYING, &NowPlayingPayload {
                has_track: true,
                id: t.id.clone(),
                title: t.title.clone(),
                artists: t.artists.clone(),
                artist_links: artist_links_for(&t),
                album: t.album_title.clone(),
                has_cover: !cover_url.is_empty(),
                cover_url,
                duration_ms: t.duration_ms,
                duration_text: fmt_time(t.duration_ms as f64 / 1000.0),
                liked: now_liked,
                has_artist: t.artist_id.is_some(),
                has_album: t.album_id.is_some(),
                is_ai: t.is_ai || crate::slopless::is_track_ai_fast(&t),
            });
        }
    }

    pub fn prefetch_likes(self: Arc<Self>) {
        let Some(api) = self.api() else { return };
        let this = self.clone();
        self.rt_handle.spawn(async move {
            let Ok(uid) = this.ensure_uid(&api).await else { return };
            let (tracks_res, albums_res, artists_res) = tokio::join!(
                api.liked_track_entries(uid),
                api.liked_albums(uid),
                api.liked_artists(uid),
            );
            let mut st = this.state.lock();
            if let Ok(entries) = tracks_res {
                st.liked_ids = entries.into_iter().map(|(id, _)| id).collect();
            }
            if let Ok(albums) = albums_res {
                st.liked_album_ids = albums.into_iter().map(|a| a.id).collect();
            }
            if let Ok(artists) = artists_res {
                st.liked_artist_ids = artists.into_iter().map(|a| a.id).collect();
            }
            drop(st);
            this.refresh_rows();
            this.send_view_feature();
        });
    }

    pub fn load_home(self: Arc<Self>) {
        let Some(api) = self.api() else {
            let view = self.begin_cached_view(None, 0, "Главная".into(), String::new());
            self.apply_cached_view(view, None, Some("Главная".into()), Some(String::new()), Vec::new(), Vec::new(), None, None);
            return;
        };
        let view = self.begin_cached_view(
            Some("home"),
            0,
            "Главная".into(),
            "Персональные плейлисты, новинки и ваша коллекция".into(),
        );
        if !self.should_fetch_view("home", Duration::from_secs(30)) {
            return;
        }
        let this = self.clone();
        self.rt_handle.spawn(async move {
            let uid = this.ensure_uid(&api).await.unwrap_or(0);
            let (landing_res, playlists_res, albums_res) = if uid != 0 {
                let (l, p, a) = tokio::join!(
                    api.landing_home(),
                    api.user_playlists(uid),
                    api.liked_albums(uid),
                );
                (l, Some(p), Some(a))
            } else {
                (api.landing_home().await, None, None)
            };

            let mut cards = Vec::new();
            let mut seen_playlists = HashSet::new();
            let mut seen_albums = HashSet::new();

            if let Ok(landing) = landing_res {
                for p in landing.personal_playlists.into_iter().take(6) {
                    if seen_playlists.insert((p.uid, p.kind)) {
                        cards.push(playlist_target_in(p, "personal"));
                    }
                }
                for mut a in landing.new_releases.into_iter().take(8) {
                    if seen_albums.insert(a.id.clone()) {
                        a.section = "new_releases".to_string();
                        cards.push(CardTarget::Album(a));
                    }
                }
                for p in landing.new_playlists.into_iter().take(6) {
                    if seen_playlists.insert((p.uid, p.kind)) {
                        cards.push(playlist_target_in(p, "new_playlists"));
                    }
                }
            }
            if let Some(Ok(playlists)) = playlists_res {
                for p in playlists.into_iter().take(8) {
                    if seen_playlists.insert((p.uid, p.kind)) {
                        cards.push(playlist_target_in(p, "user_playlists"));
                    }
                }
            }
            if let Some(Ok(albums)) = albums_res {
                for mut a in albums.into_iter().take(8) {
                    if seen_albums.insert(a.id.clone()) {
                        a.section = "user_albums".to_string();
                        cards.push(CardTarget::Album(a));
                    }
                }
            }

            let ok = !cards.is_empty();
            this.finish_fetching_view("home", ok);
            if ok {
                this.apply_cached_view(
                    view,
                    Some("home"),
                    Some("Главная".into()),
                    Some("Персональные плейлисты, новинки и ваша коллекция".into()),
                    cards,
                    Vec::new(),
                    None,
                    None,
                );
            } else {
                let is_empty_current = {
                    let st = this.state.lock();
                    st.view_id == view && st.cards.is_empty() && st.list.is_empty()
                };
                if is_empty_current {
                    this.send_event(EVENT_VIEW_HEADER, &ViewHeaderPayload {
                        cover_url: String::new(),
                        page: 0,
                        title: "Главная".into(),
                        subtitle: "Нет подключения к сети".into(),
                        loading: false,
                        is_artist_view: false,
                        artist_name: String::new(),
                        artist_genres: String::new(),
                        artist_stats: String::new(),
                        artist_avatar: String::new(),
                        artist_has_avatar: false,
                        can_start_artist_wave: false,
                    });
                }
            }
        });
    }

    pub fn open_chart(self: Arc<Self>) {
        let Some(api) = self.api() else { return };
        let view = self.begin_cached_view(
            Some("chart"),
            6,
            "Чарт Яндекс Музыки".into(),
            "Популярные треки прямо сейчас".into(),
        );
        if !self.should_fetch_view("chart", Duration::from_secs(30)) {
            return;
        }
        let this = self.clone();
        self.rt_handle.spawn(async move {
            match api.chart_tracks().await {
                Ok(tracks) => {
                    this.finish_fetching_view("chart", true);
                    let sub = format!("Топ-{} популярных треков", tracks.len());
                    this.apply_cached_view(
                        view,
                        Some("chart"),
                        Some("Чарт Яндекс Музыки".into()),
                        Some(sub),
                        Vec::new(),
                        tracks,
                        None,
                        None,
                    );
                }
                Err(e) => {
                    this.finish_fetching_view("chart", false);
                    this.view_failed(view, "Чарт", e);
                }
            }
        });
    }

    pub fn open_similar_tracks(self: Arc<Self>, track_id: String, title: String) {
        let Some(api) = self.api() else { return };
        let key = format!("similar:{track_id}");
        let header_title = format!("Похожие: {title}");
        let view = self.begin_cached_view(
            Some(&key),
            6,
            header_title.clone(),
            "Треки в похожем стиле".into(),
        );
        let this = self.clone();
        self.rt_handle.spawn(async move {
            match api.similar_tracks(&track_id).await {
                Ok(tracks) => {
                    let sub = if tracks.is_empty() {
                        "Похожие треки не найдены".to_string()
                    } else {
                        format!("{} похожих треков", tracks.len())
                    };
                    this.apply_cached_view(
                        view,
                        Some(&key),
                        Some(header_title),
                        Some(sub),
                        Vec::new(),
                        tracks,
                        None,
                        None,
                    );
                }
                Err(e) => this.view_failed(view, "Похожие треки", e),
            }
        });
    }

    pub fn open_disliked_tracks(self: Arc<Self>) {
        let Some(api) = self.api() else { self.error("Для просмотра скрытых треков нужен вход"); return };
        let uid = self.state.lock().uid;
        let key = "dislikes";
        let header_title = "Не нравится".to_string();
        let view = self.begin_cached_view(
            Some(key),
            6,
            header_title.clone(),
            "Треки, исключённые из рекомендаций".into(),
        );
        let this = self.clone();
        self.rt_handle.spawn(async move {
            match api.disliked_tracks(uid).await {
                Ok(tracks) => {
                    let sub = if tracks.is_empty() {
                        "Скрытых треков нет".to_string()
                    } else {
                        format!("{} скрытых треков", tracks.len())
                    };
                    this.apply_cached_view(
                        view,
                        Some(key),
                        Some(header_title),
                        Some(sub),
                        Vec::new(),
                        tracks,
                        None,
                        None,
                    );
                }
                Err(e) => this.view_failed(view, "Не нравится", e),
            }
        });
    }

    pub fn load_downloads(self: Arc<Self>) {
        let view = self.begin_cached_view(None, 7, "Загружено".into(), "Читаем загрузки…".into());
        let this = self.clone();
        self.rt_handle.spawn(async move {
            let reader = this.clone();
            match tokio::task::spawn_blocking(move || {
                let known = {
                    let st = reader.state.lock();
                    st.list.iter().chain(st.queue.iter()).cloned().collect::<Vec<_>>()
                };
                cache::recover_offline_metadata(&known);
                cache::offline_tracks()
            }).await {
                Ok(Ok((tracks, bytes))) => {
                    let missing_covers: Vec<Track> = tracks
                        .iter()
                        .filter(|t| t.cover_uri.is_some() && cache::offline_cover_url(&t.id).is_none())
                        .cloned()
                        .collect();
                    let subtitle = format!("{} тр. • {:.1} МБ • На этом устройстве", tracks.len(), bytes as f64 / 1048576.0);
                    this.apply_cached_view(view, None, Some("Загружено".into()), Some(subtitle), Vec::new(), tracks, None, None);
                    if !missing_covers.is_empty() {
                        let bg_core = this.clone();
                        this.rt_handle.spawn(async move {
                            for t in missing_covers {
                                cache::download_offline_cover(&bg_core.http, &t).await;
                            }
                            bg_core.refresh_rows();
                        });
                    }
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
                    let showing_downloads = this.state.lock().page == 7;
                    if showing_downloads { this.clone().load_downloads(); }
                    this.notify("Загрузка удалена с устройства");
                }
                _ => this.error("Не удалось удалить загрузку"),
            }
        });
    }

    pub fn playlist_choices(self: Arc<Self>, id: String) {
        let Some(api) = self.api() else { return };
        let uid = self.state.lock().uid;
        let this = self.clone();
        self.rt_handle.spawn(async move {
            let result = api.own_playlists(uid).await;
            if this.state.lock().uid != uid { return; }
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
        let uid = self.state.lock().uid;
        let this = self.clone();
        self.rt_handle.spawn(async move {
            let result = api.insert_playlist_track(uid, kind, &track).await;
            if this.state.lock().uid != uid { return; }
            match result {
                Ok(()) => {
                    // Invalidate only this playlist; never replace the page the user navigated to.
                    let key = format!("playlist:{uid}:{kind}");
                    {
                        let mut st = this.state.lock();
                        st.views.remove(&key);
                        st.view_fetched_at.remove(&key);
                    }
                    cache::remove_view(&key);
                    this.send_event(EVENT_PLAYLIST_PICKER, &serde_json::json!({"id": id, "stage": "done"}));
                    this.notify(format!("«{}» добавлен в плейлист", track.title));
                }
                Err(e) => this.send_event(EVENT_PLAYLIST_PICKER, &serde_json::json!({"id": id, "stage": "error", "message": format!("Не удалось добавить трек: {e}. Обновите список и повторите.")})),
            }
        });
    }

    pub fn load_likes(self: Arc<Self>) {
        let Some(api) = self.api() else { return };
        let view = self.begin_cached_view(Some("likes"), 2, "Мне нравится".into(), "".into());
        if !self.should_fetch_view("likes", Duration::from_secs(25)) {
            return;
        }
        let this = self.clone();
        self.rt_handle.spawn(async move {
            let res: anyhow::Result<(HashSet<String>, Vec<Track>)> = async {
                let uid = this.ensure_uid(&api).await?;
                let entries = api.liked_track_entries(uid).await?;
                let liked_set: HashSet<String> = entries.iter().map(|(id, _)| id.clone()).collect();

                let mut known_tracks: HashMap<String, Track> = {
                    let st = this.state.lock();
                    let mut map = HashMap::new();
                    if let Some(cached) = st.views.get("likes") {
                        for t in &cached.tracks {
                            map.insert(t.id.clone(), t.clone());
                        }
                    }
                    for t in st.list.iter().chain(st.queue.iter()) {
                        map.entry(t.id.clone()).or_insert_with(|| t.clone());
                    }
                    map
                };

                let missing_composite: Vec<String> = entries
                    .iter()
                    .filter(|(id, _)| !known_tracks.contains_key(id))
                    .map(|(_, full)| full.clone())
                    .collect();

                if !missing_composite.is_empty() {
                    let fetched = api.tracks(&missing_composite).await?;
                    for t in fetched {
                        known_tracks.insert(t.id.clone(), t);
                    }
                }

                let tracks: Vec<Track> = entries
                    .into_iter()
                    .filter_map(|(id, _)| known_tracks.get(&id).cloned())
                    .collect();

                Ok((liked_set, tracks))
            }
            .await;

            match res {
                Ok((liked_set, tracks)) => {
                    this.finish_fetching_view("likes", true);
                    this.state.lock().liked_ids = liked_set;
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
                Err(e) => {
                    this.finish_fetching_view("likes", false);
                    this.view_failed(view, "Не удалось загрузить лайки", e);
                }
            }
        });
    }

    pub fn open_or_start_wave(self: Arc<Self>, seed: String, title: String) {
        let existing = {
            let mut st = self.state.lock();
            if let Some(w) = st.wave.as_ref().filter(|w| w.seed == seed && !w.tracks.is_empty()) {
                let tracks = w.tracks.clone();
                let w_title = w.title.clone();
                let cache_key = w.cache_key();
                st.view_id += 1;
                st.page = 1;
                st.active_view_key = Some(cache_key);
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
            self.send_view_feature();
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
            self.state.lock().wave_selected.values().cloned().collect()
        } else { Vec::new() };
        seeds.sort();
        self.start_wave_filtered(seed, title, seeds, None);
    }

    pub fn load_wave_settings(self: Arc<Self>) {
        let Some(api) = self.api() else { return };
        let uid = self.state.lock().uid;
        let this = self.clone();
        self.rt_handle.spawn(async move {
            let result = api.wave_settings().await;
            if this.state.lock().uid != uid { return; }
            match result {
                Ok(response) => {
                    let groups = crate::wave::groups(&response);
                    let selected = {
                        let mut st = this.state.lock();
                        if st.uid != uid { return; }
                        st.wave_groups = groups.clone();
                        st.wave_selected.retain(|key, seed| groups.iter().any(|g|
                            &g.key == key && g.choices.iter().any(|c| &c.seed == seed)));
                        let legacy_filters = st
                            .wave
                            .as_ref()
                            .filter(|w| w.seed == "user:onyourwave")
                            .map(|w| w.filters.clone())
                            .unwrap_or_default();
                        if st.wave_selected.is_empty() && !legacy_filters.is_empty() {
                            for g in &groups {
                                if let Some(choice) = g.choices.iter().find(|c| legacy_filters.contains(&c.seed)) {
                                    st.wave_selected.insert(g.key.clone(), choice.seed.clone());
                                }
                            }
                        }
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
                let mut st = this.state.lock();
                if st.view_id != view {
                    return;
                }
                st.wave = Some(WaveState {
                    seed: seed.clone(),
                    title: title.clone(),
                    session_id: session.session_id.clone(),
                    batch_id: session.batch_id.clone(),
                    tracks: session.tracks.clone(),
                    filters: filters.clone(),
                    fetching_more: false,
                    resume_on_load: false,
                });
                let persist_selected = selected.is_some();
                if let Some(selected) = selected { st.wave_selected = selected; }
                let selected_snapshot = if persist_selected { Some(st.wave_selected.clone()) } else { None };
                st.unshuffled_queue = None;
                st.queue = session.tracks.clone();
                st.current = None;
                drop(st);
                if let Some(sel) = selected_snapshot {
                    tokio::task::spawn_blocking(move || {
                        config::update_settings(|s| s.wave_selected = sel);
                    });
                }
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
            let selected = this.state.lock().wave_selected.clone();
            this.send_feature("wave_applied", serde_json::json!({"selected": selected}));
        });
    }

    pub fn load_playlists(self: Arc<Self>) {
        let Some(api) = self.api() else { return };
        let view = self.begin_cached_view(
            Some("playlists"),
            3,
            "Плейлисты".into(),
            "Ваши и понравившиеся плейлисты".into(),
        );
        if !self.should_fetch_view("playlists", Duration::from_secs(25)) {
            return;
        }
        let this = self.clone();
        self.rt_handle.spawn(async move {
            let res: anyhow::Result<Vec<api::PlaylistCard>> = async {
                let uid = this.ensure_uid(&api).await?;
                api.user_playlists(uid).await
            }
            .await;
            match res {
                Ok(list) => {
                    this.finish_fetching_view("playlists", true);
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
                Err(e) => {
                    this.finish_fetching_view("playlists", false);
                    this.view_failed(view, "Плейлисты", e);
                }
            }
        });
    }

    pub fn load_albums(self: Arc<Self>) {
        let Some(api) = self.api() else { return };
        let view = self.begin_cached_view(
            Some("albums"),
            4,
            "Альбомы".into(),
            "Понравившиеся альбомы".into(),
        );
        if !self.should_fetch_view("albums", Duration::from_secs(25)) {
            return;
        }
        let this = self.clone();
        self.rt_handle.spawn(async move {
            let res: anyhow::Result<Vec<AlbumCard>> = async {
                let uid = this.ensure_uid(&api).await?;
                api.liked_albums(uid).await
            }
            .await;
            match res {
                Ok(list) => {
                    this.finish_fetching_view("albums", true);
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
                Err(e) => {
                    this.finish_fetching_view("albums", false);
                    this.view_failed(view, "Альбомы", e);
                }
            }
        });
    }

    pub fn load_artists(self: Arc<Self>) {
        let Some(api) = self.api() else { return };
        let view = self.begin_cached_view(
            Some("artists"),
            5,
            "Артисты".into(),
            "Любимые исполнители".into(),
        );
        if !self.should_fetch_view("artists", Duration::from_secs(25)) {
            return;
        }
        let this = self.clone();
        self.rt_handle.spawn(async move {
            let res: anyhow::Result<Vec<ArtistCard>> = async {
                let uid = this.ensure_uid(&api).await?;
                api.liked_artists(uid).await
            }
            .await;
            match res {
                Ok(list) => {
                    this.finish_fetching_view("artists", true);
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
                Err(e) => {
                    this.finish_fetching_view("artists", false);
                    this.view_failed(view, "Артисты", e);
                }
            }
        });
    }

    pub fn search(self: Arc<Self>, query: String) {
        let filter = self.state.lock().search_filter.clone();
        let filter = if ["all", "track", "album", "artist", "playlist"].contains(&filter.as_str()) {
            filter
        } else {
            "all".into()
        };
        self.search_with_filter(query, filter);
    }

    pub fn search_with_filter(self: Arc<Self>, query: String, filter: String) {
        if !["all", "track", "album", "artist", "playlist"].contains(&filter.as_str()) { return; }
        let history = {
            let mut st = self.state.lock();
            st.search_query = query.clone();
            st.search_filter = filter.clone();
            st.search_page = 0;
            st.search_has_more = false;
            st.search_loading_more = false;
            st.search_best = None;
            if !query.trim().is_empty() {
                let trimmed = query.trim().to_string();
                st.search_history.retain(|item| !item.eq_ignore_ascii_case(&trimmed));
                st.search_history.insert(0, trimmed);
                st.search_history.truncate(8);
            }
            st.search_history.clone()
        };
        self.send_feature("search", serde_json::json!({
            "query": query,
            "filter": filter,
            "best": serde_json::Value::Null,
            "has_more": false,
            "loading_more": false,
            "history": history,
        }));
        if query.is_empty() {
            let view = self.begin_cached_view(None, 8, "Поиск музыки".into(), String::new());
            self.apply_cached_view(view, None, Some("Поиск музыки".into()), Some(String::new()), Vec::new(), Vec::new(), None, None);
            return;
        }
        let Some(api) = self.api() else { return };
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
            match api.search_filtered_page(&query, &filter, 0).await {
                Ok(res) => {
                    let mut cards = Vec::new();
                    cards.extend(res.artists.into_iter().map(CardTarget::Artist));
                    cards.extend(res.albums.into_iter().map(CardTarget::Album));
                    cards.extend(res.playlists.into_iter().map(playlist_target));
                    let best = res.best;
                    let has_more = res.has_more;
                    let applied = this.apply_cached_view(
                        view,
                        Some(&key),
                        Some(title),
                        Some("Артисты, альбомы, плейлисты и треки".into()),
                        cards,
                        res.tracks,
                        None,
                        None,
                    );
                    if applied {
                        let (best_json, history) = {
                            let mut st = this.state.lock();
                            st.search_best = best.clone();
                            st.search_page = 0;
                            st.search_has_more = has_more;
                            st.search_loading_more = false;
                            let bj = best
                                .as_ref()
                                .map(|b| search_best_payload(b, &st.liked_ids))
                                .unwrap_or(serde_json::Value::Null);
                            (bj, st.search_history.clone())
                        };
                        this.send_feature("search", serde_json::json!({
                            "query": query,
                            "filter": filter,
                            "best": best_json,
                            "has_more": has_more,
                            "loading_more": false,
                            "history": history,
                        }));
                    }
                }
                Err(e) => this.view_failed(view, "Поиск", e),
            }
        });
    }

    pub fn search_more(self: Arc<Self>) {
        let (query, filter, next_page, view, history) = {
            let mut st = self.state.lock();
            if st.search_query.trim().is_empty() || !st.search_has_more || st.search_loading_more || st.page != 8 {
                return;
            }
            st.search_loading_more = true;
            (st.search_query.clone(), st.search_filter.clone(), st.search_page + 1, st.view_id, st.search_history.clone())
        };
        let Some(api) = self.api() else {
            self.state.lock().search_loading_more = false;
            return;
        };
        self.send_feature("search", serde_json::json!({
            "query": query,
            "filter": filter,
            "has_more": true,
            "loading_more": true,
            "history": history,
        }));
        let this = self.clone();
        self.rt_handle.spawn(async move {
            match api.search_filtered_page(&query, &filter, next_page).await {
                Ok(res) => {
                    let mut new_cards = Vec::new();
                    new_cards.extend(res.artists.into_iter().map(CardTarget::Artist));
                    new_cards.extend(res.albums.into_iter().map(CardTarget::Album));
                    new_cards.extend(res.playlists.into_iter().map(playlist_target));
                    let has_more = res.has_more;

                    let update = {
                        let mut st = this.state.lock();
                        if st.view_id != view || st.page != 8 || st.search_query != query || st.search_filter != filter {
                            st.search_loading_more = false;
                            None
                        } else {
                            let existing_track_ids: HashSet<String> = st.list.iter().map(|t| t.id.clone()).collect();
                            for t in res.tracks {
                                if !existing_track_ids.contains(&t.id) {
                                    st.list.push(t);
                                }
                            }
                            let existing_card_keys: HashSet<String> = st.cards.iter().map(card_dedup_key).collect();
                            for c in new_cards {
                                if !existing_card_keys.contains(&card_dedup_key(&c)) {
                                    st.cards.push(c);
                                }
                            }
                            st.search_page = next_page;
                            st.search_has_more = has_more;
                            st.search_loading_more = false;
                            let cards_p: Vec<CardItemPayload> = st.cards.iter().map(|c| card_payload(c, &st.pinned_playlists)).collect();
                            let tracks_p: Vec<TrackItemPayload> = st.list.iter().map(|t| track_payload(t, &st.liked_ids)).collect();
                            let cur = current_list_index(&st);
                            let best_json = st.search_best
                                .as_ref()
                                .map(|b| search_best_payload(b, &st.liked_ids))
                                .unwrap_or(serde_json::Value::Null);
                            Some((cards_p, tracks_p, cur, best_json, st.search_history.clone()))
                        }
                    };
                    if let Some((cards_p, tracks_p, cur, best_json, history)) = update {
                        this.send_event(EVENT_CARDS_LOADED, &CardsPayload { cards: cards_p });
                        this.send_event(EVENT_TRACKS_LOADED, &TracksPayload { tracks: tracks_p, current_index: cur });
                        this.send_feature("search", serde_json::json!({
                            "query": query,
                            "filter": filter,
                            "best": best_json,
                            "has_more": has_more,
                            "loading_more": false,
                            "history": history,
                        }));
                    }
                }
                Err(e) => {
                    this.state.lock().search_loading_more = false;
                    this.send_feature("search", serde_json::json!({
                        "query": query,
                        "filter": filter,
                        "has_more": true,
                        "loading_more": false,
                    }));
                    this.error(format!("Догрузка поиска: {e}"));
                }
            }
        });
    }

    pub fn open_card(self: Arc<Self>, index: usize) {
        let target = self.state.lock().cards.get(index).cloned();
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
            let mut st = self.state.lock();
            let card_cover = st.cards.iter().find_map(|card| match card {
                CardTarget::Playlist { uid, kind: card_kind, cover_uri, .. } if *uid == owner_uid && *card_kind == kind => cover_uri.clone(),
                _ => None,
            });
            let pin_cover = st.pinned_playlists.iter()
                .find(|p| p.uid == owner_uid && p.kind == kind)
                .and_then(|p| p.cover_uri.clone());
            let cover = card_cover.or(pin_cover);
            st.active_playlist = Some(config::PinnedPlaylist {
                uid: owner_uid,
                kind,
                title: title.clone(),
                cover_uri: cover.clone(),
            });
            cover
        };
        let key = format!("playlist:{owner_uid}:{kind}");
        let view = self.begin_cached_view(Some(&key), 6, title.clone(), "Плейлист".into());
        {
            let mut st = self.state.lock();
            st.active_playlist = Some(config::PinnedPlaylist {
                uid: owner_uid,
                kind,
                title: title.clone(),
                cover_uri: cover.clone(),
            });
            if cover.is_some() {
                st.view_cover_uri = cover;
            }
        }
        self.send_view_feature();
        if !self.should_fetch_view(&key, Duration::from_secs(20)) {
            return;
        }
        let this = self.clone();
        self.rt_handle.spawn(async move {
            match api.playlist_tracks(owner_uid, kind).await {
                Ok(tracks) => {
                    this.finish_fetching_view(&key, true);
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
                Err(e) => {
                    this.finish_fetching_view(&key, false);
                    this.view_failed(view, "Плейлист", e);
                }
            }
        });
    }

    pub fn open_album(self: Arc<Self>, album_id: String) {
        let Some(api) = self.api() else { return };
        let key = format!("album:{album_id}");
        let view = self.begin_cached_view(Some(&key), 6, "Альбом…".into(), "".into());
        self.state.lock().active_album_id = Some(album_id.clone());
        self.send_view_feature();
        if !self.should_fetch_view(&key, Duration::from_secs(20)) {
            return;
        }
        let this = self.clone();
        self.rt_handle.spawn(async move {
            match api.album_with_tracks(&album_id).await {
                Ok((album, mut tracks)) => {
                    this.finish_fetching_view(&key, true);
                    let extra = collect_mod_album_injections(&album_id);
                    if !extra.is_empty() {
                        let existing: HashSet<String> = tracks.iter().map(|t| t.id.clone()).collect();
                        for mut t in extra {
                            if !existing.contains(&t.id) {
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
                    let sub = match album.year {
                        Some(y) if !album.artists.is_empty() => format!("{} • {y}", album.artists),
                        Some(y) => y.to_string(),
                        None => album.artists.clone(),
                    };
                    let title = album.title.clone();
                    {
                        let mut st = this.state.lock();
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
                Err(e) => {
                    this.finish_fetching_view(&key, false);
                    this.view_failed(view, "Альбом", e);
                }
            }
        });
    }

    pub fn open_artist(self: Arc<Self>, artist_id: String) {
        let Some(api) = self.api() else { return };
        let key = format!("artist:{artist_id}");
        let view = self.begin_cached_view(Some(&key), 6, "Артист…".into(), "".into());
        if !self.should_fetch_view(&key, Duration::from_secs(20)) {
            return;
        }
        let this = self.clone();
        self.rt_handle.spawn(async move {
            match api.artist_brief(&artist_id).await {
                Ok(page) => {
                    this.finish_fetching_view(&key, true);
                    let name = page.artist.name.clone();
                    let genres = if page.artist.genres.is_empty() {
                        "Популярные треки и дискография".to_string()
                    } else {
                        page.artist.genres.clone()
                    };
                    let mut cards: Vec<CardTarget> = page.albums.into_iter().map(CardTarget::Album).collect();
                    cards.extend(page.similar_artists.into_iter().map(CardTarget::Artist));
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
                    this.send_view_feature();
                }
                Err(e) => {
                    this.finish_fetching_view(&key, false);
                    this.view_failed(view, "Артист", e);
                }
            }
        });
    }

    pub fn toggle_like_at(self: Arc<Self>, index: usize) {
        let track = self.state.lock().list.get(index).cloned();
        if let Some(t) = track {
            self.toggle_like_track(t);
        }
    }

    /// Resolve a stable track identity, not a row number that may have changed.
    pub fn find_track(&self, id: &str) -> Option<Track> {
        let st = self.state.lock();
        st.list.iter().chain(st.queue.iter())
            .chain(st.views.values().flat_map(|view| view.tracks.iter()))
            .find(|t| t.id == id).cloned()
    }

    pub fn enqueue_track(&self, track: Track, next: bool) {
        {
            let mut st = self.state.lock();
            enqueue_in_state(&mut st, track, next);
        }
        self.persist_session();
        self.send_queue();
        self.notify(if next { "Трек будет играть следующим" } else { "Трек добавлен в очередь" });
    }

    pub fn repeat_track(self: Arc<Self>, track: Track) {
        let index = {
            let mut st = self.state.lock();
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
            let st = self.state.lock();
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
        let (api, audio_quality) = {
            let st = self.state.lock();
            let q = if destination.is_some() {
                match st.download_quality.as_str() {
                    "flac" => "lossless".to_string(),
                    "match" => st.audio_quality.clone(),
                    _ => "hq".to_string(),
                }
            } else {
                st.audio_quality.clone()
            };
            (st.api.clone(), q)
        };
        let Some(api) = api else { return };
        self.notify(format!("Скачиваем «{}»…", track.title));
        let this = self.clone();
        self.rt_handle.spawn(async move {
            let offline = destination.is_none();
            let result: anyhow::Result<()> = async {
                let path = destination.or_else(|| cache::offline_track_path(&track.id))
                    .ok_or_else(|| anyhow::anyhow!("нет каталога данных"))?;
                let info = api.track_stream_info(&track.id, &audio_quality).await?;
                cache::download_to_file(api.http(), &info.url, &path).await?;
                if offline {
                    cache::download_offline_cover(api.http(), &track).await;
                    let metadata = track.clone();
                    tokio::task::spawn_blocking(move || cache::save_offline_metadata(&metadata)).await??;
                }
                Ok(())
            }.await;
            match result {
                Ok(()) => {
                    this.refresh_rows();
                    let showing_downloads = this.state.lock().page == 7;
                    if showing_downloads { this.clone().load_downloads(); }
                    this.notify(format!("«{}» сохранён", track.title));
                }
                Err(e) => this.error(format!("Не удалось скачать «{}»: {e}", track.title)),
            }
        });
    }

    pub fn toggle_like_collection(self: Arc<Self>) {
        #[derive(Clone)]
        enum Target {
            Album(String),
            Artist(String),
            Playlist { owner_uid: u64, kind: u64 },
        }

        let (api, uid, target, add) = {
            let mut st = self.state.lock();
            let Some(api) = st.api.clone() else { return };
            let uid = st.uid;
            if let Some(ref album_id) = st.active_album_id.clone() {
                let add = !st.liked_album_ids.contains(album_id);
                if add {
                    st.liked_album_ids.insert(album_id.clone());
                } else {
                    st.liked_album_ids.remove(album_id);
                }
                (api, uid, Target::Album(album_id.clone()), add)
            } else if let Some((ref artist_id, _)) = st.viewed_artist_id.clone() {
                let add = !st.liked_artist_ids.contains(artist_id);
                if add {
                    st.liked_artist_ids.insert(artist_id.clone());
                } else {
                    st.liked_artist_ids.remove(artist_id);
                }
                (api, uid, Target::Artist(artist_id.clone()), add)
            } else if let Some(ref pl) = st.active_playlist.clone() {
                if pl.uid == uid && uid != 0 {
                    return;
                }
                let key = format!("{}:{}", pl.uid, pl.kind);
                let add = !st.liked_playlist_keys.contains(&key);
                if add {
                    st.liked_playlist_keys.insert(key);
                } else {
                    st.liked_playlist_keys.remove(&key);
                }
                (api, uid, Target::Playlist { owner_uid: pl.uid, kind: pl.kind }, add)
            } else {
                return;
            }
        };
        self.send_view_feature();
        let this = self.clone();
        self.rt_handle.spawn(async move {
            let res = match &target {
                Target::Album(id) => {
                    if add { api.like_album(uid, id).await } else { api.unlike_album(uid, id).await }
                }
                Target::Artist(id) => {
                    if add { api.like_artist(uid, id).await } else { api.unlike_artist(uid, id).await }
                }
                Target::Playlist { owner_uid, kind } => {
                    if add {
                        api.like_playlist(uid, *owner_uid, *kind).await
                    } else {
                        api.unlike_playlist(uid, *owner_uid, *kind).await
                    }
                }
            };
            match res {
                Ok(()) => {
                    {
                        let mut st = this.state.lock();
                        match &target {
                            Target::Album(_) => {
                                st.views.remove("albums");
                                st.view_fetched_at.remove("albums");
                                st.view_fetched_at.remove("home");
                            }
                            Target::Artist(_) => {
                                st.views.remove("artists");
                                st.view_fetched_at.remove("artists");
                            }
                            Target::Playlist { .. } => {
                                st.views.remove("playlists");
                                st.view_fetched_at.remove("playlists");
                                st.view_fetched_at.remove("home");
                            }
                        }
                    }
                    this.notify(if add {
                        "Добавлено в Мою музыку"
                    } else {
                        "Удалено из Моей музыки"
                    });
                }
                Err(e) => {
                    {
                        let mut st = this.state.lock();
                        match &target {
                            Target::Album(id) => {
                                if add { st.liked_album_ids.remove(id); } else { st.liked_album_ids.insert(id.clone()); }
                            }
                            Target::Artist(id) => {
                                if add { st.liked_artist_ids.remove(id); } else { st.liked_artist_ids.insert(id.clone()); }
                            }
                            Target::Playlist { owner_uid, kind } => {
                                let key = format!("{owner_uid}:{kind}");
                                if add { st.liked_playlist_keys.remove(&key); } else { st.liked_playlist_keys.insert(key); }
                            }
                        }
                    }
                    this.send_view_feature();
                    this.error(format!("Не удалось обновить коллекцию: {e:#}"));
                }
            }
        });
    }

    pub fn delete_active_playlist(self: Arc<Self>) {
        let (api, uid, pl) = {
            let st = self.state.lock();
            let Some(api) = st.api.clone() else { return };
            let Some(pl) = st.active_playlist.clone() else { return };
            if pl.uid != st.uid || st.uid == 0 {
                self.error("Можно удалять только собственные плейлисты");
                return;
            }
            (api, st.uid, pl)
        };
        let this = self.clone();
        self.rt_handle.spawn(async move {
            match api.delete_playlist(uid, pl.kind).await {
                Ok(()) => {
                    {
                        let mut st = this.state.lock();
                        st.active_playlist = None;
                        st.pinned_playlists.retain(|p| !(p.uid == pl.uid && p.kind == pl.kind));
                        let key = format!("playlist:{}:{}", pl.uid, pl.kind);
                        st.views.remove("playlists");
                        st.view_fetched_at.remove("playlists");
                        st.view_fetched_at.remove("home");
                        st.views.remove(&key);
                        st.view_fetched_at.remove(&key);
                        let pins = st.pinned_playlists.clone();
                        config::update_settings(|s| s.pinned_playlists = pins);
                    }
                    this.send_pinned_playlists();
                    this.notify(format!("Плейлист «{}» удалён", pl.title));
                    this.load_playlists();
                }
                Err(e) => this.error(format!("Не удалось удалить плейлист: {e:#}")),
            }
        });
    }

    pub fn rename_active_playlist(self: Arc<Self>, new_title: String) {
        let new_title = new_title.trim().to_string();
        if new_title.is_empty() {
            return;
        }
        let (api, uid, pl) = {
            let st = self.state.lock();
            let Some(api) = st.api.clone() else { return };
            let Some(pl) = st.active_playlist.clone() else { return };
            if pl.uid != st.uid || st.uid == 0 {
                self.error("Можно переименовывать только собственные плейлисты");
                return;
            }
            (api, st.uid, pl)
        };
        let this = self.clone();
        self.rt_handle.spawn(async move {
            match api.rename_playlist(uid, pl.kind, &new_title).await {
                Ok(_updated) => {
                    let key = format!("playlist:{}:{}", pl.uid, pl.kind);
                    {
                        let mut st = this.state.lock();
                        if let Some(ref mut active) = st.active_playlist
                            && active.uid == pl.uid
                            && active.kind == pl.kind
                        {
                            active.title = new_title.clone();
                        }
                        for p in &mut st.pinned_playlists {
                            if p.uid == pl.uid && p.kind == pl.kind {
                                p.title = new_title.clone();
                            }
                        }
                        if let Some(cached) = st.views.get_mut(&key) {
                            cached.title = new_title.clone();
                        }
                        st.views.remove("playlists");
                        st.view_fetched_at.remove("playlists");
                        st.view_fetched_at.remove("home");
                        let pins = st.pinned_playlists.clone();
                        config::update_settings(|s| s.pinned_playlists = pins);
                    }
                    this.send_pinned_playlists();
                    this.notify(format!("Плейлист переименован в «{new_title}»"));
                    this.open_playlist(pl.uid, pl.kind, new_title);
                }
                Err(e) => this.error(format!("Не удалось переименовать плейлист: {e:#}")),
            }
        });
    }

    pub fn remove_track_from_active_playlist(self: Arc<Self>, track_id: String) {
        if track_id.is_empty() {
            return;
        }
        let (api, uid, pl) = {
            let st = self.state.lock();
            let Some(api) = st.api.clone() else { return };
            let Some(pl) = st.active_playlist.clone() else { return };
            if pl.uid != st.uid || st.uid == 0 {
                self.error("Можно редактировать только собственные плейлисты");
                return;
            }
            (api, st.uid, pl)
        };
        let this = self.clone();
        self.rt_handle.spawn(async move {
            match api.delete_playlist_track(uid, pl.kind, &track_id).await {
                Ok(()) => {
                    let key = format!("playlist:{}:{}", pl.uid, pl.kind);
                    let mut updated_cache = None;
                    {
                        let mut st = this.state.lock();
                        if let Some(pos) = st.list.iter().position(|t| t.id == track_id) {
                            st.list.remove(pos);
                        }
                        if let Some(cached) = st.views.get_mut(&key) {
                            if let Some(pos) = cached.tracks.iter().position(|t| t.id == track_id) {
                                cached.tracks.remove(pos);
                            }
                            updated_cache = Some(cached.clone());
                        }
                    }
                    if let Some(cached) = updated_cache {
                        cache::save_view(&key, &cached);
                    }
                    this.refresh_rows();
                    this.notify("Трек удалён из плейлиста");
                }
                Err(e) => this.error(format!("Не удалось удалить трек из плейлиста: {e:#}")),
            }
        });
    }

    pub fn toggle_now_like(self: Arc<Self>) {
        let track = current_track(&self.state.lock()).cloned();
        if let Some(t) = track {
            self.toggle_like_track(t);
        }
    }

    pub fn update_likes_cache(&self, track: &Track, add: bool) {
        let mut st = self.state.lock();
        if st.page == 2 {
            if add {
                if !st.list.iter().any(|t| t.id == track.id) {
                    st.list.insert(0, track.clone());
                }
            } else {
                st.list.retain(|t| t.id != track.id);
            }
        }
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
        let (api, add, wave) = {
            let mut st = self.state.lock();
            let Some(api) = st.api.clone() else { return };
            let add = !st.liked_ids.contains(&track.id);
            if add {
                st.liked_ids.insert(track.id.clone());
            } else {
                st.liked_ids.remove(&track.id);
            }
            (api, add, st.wave.clone())
        };
        self.update_likes_cache(&track, add);
        self.refresh_rows();
        let this = self.clone();
        self.rt_handle.spawn(async move {
            let res: anyhow::Result<()> = async {
                let uid = this.ensure_uid(&api).await?;
                if add {
                    api.like_track(uid, &track.id).await
                } else {
                    api.unlike_track(uid, &track.id).await
                }
            }
            .await;
            if let Err(e) = res {
                {
                    let mut st = this.state.lock();
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
            this.lastfm.love_track(&track, add);
        });
    }

    pub fn dislike_now(self: Arc<Self>) {
        let (api, track, played, wave, was_liked) = {
            let mut st = self.state.lock();
            let Some(api) = st.api.clone() else { return };
            let Some(track) = current_track(&st).cloned() else { return };
            let was_liked = st.liked_ids.remove(&track.id);
            (api, track, st.position_secs, st.wave.clone(), was_liked)
        };
        if was_liked {
            self.update_likes_cache(&track, false);
        }
        self.refresh_rows();
        let this = self.clone();
        self.rt_handle.spawn(async move {
            let res: anyhow::Result<()> = async {
                let uid = this.ensure_uid(&api).await?;
                api.dislike_track(uid, &track.id).await
            }
            .await;
            if let Err(e) = res {
                if was_liked {
                    this.state.lock().liked_ids.insert(track.id.clone());
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
            let st = self.state.lock();
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
            let mut st = self.state.lock();
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
        self.lastfm.set_stopped();

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
        let (prev_track, prev_played, prev_play_id, play_id, track, next_track_id, generation, api, uid, current_idx, liked, wave, initial_pos, duration_secs, audio_quality, track_gain, ai_behavior, ai_strict, can_auto_skip) = {
            let mut st = self.state.lock();
            let Some(raw_track) = st.queue.get(index).cloned() else { return };
            let track = apply_mod_track_override(&raw_track);
            let api = st.api.clone();
            let uid = st.uid;
            let prev_track = current_track(&st).cloned();
            let prev_played = st.position_secs;
            let prev_play_id = st.current_play_id.clone();
            let next_track_id = st.queue[index + 1..]
                .iter()
                .find(|t| t.available)
                .map(|t| t.id.clone());
            let duration_secs = track.duration_ms as f64 / 1000.0;
            let initial_pos = start_at.unwrap_or(0.0).clamp(0.0, duration_secs.max(0.0));
            let audio_quality = st.audio_quality.clone();
            let track_gain = if st.normalize_volume { track.r128_gain() } else { 1.0 };
            let ai_behavior = st.ai_music_behavior.clone();
            let ai_strict = st.ai_strict_tracks;
            let can_auto_skip = st.wave.is_some()
                || st.queue[index + 1..]
                    .iter()
                    .any(|t| t.available && !crate::slopless::should_take_action_fast(t, ai_strict));
            st.current = Some(index);
            st.generation += 1;
            let now_ms = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis();
            let play_id = format!("{}-{}-{}", uid, st.generation, now_ms);
            st.current_play_id = play_id.clone();
            st.play_scrobbled = false;
            st.duration_secs = duration_secs;
            st.position_secs = initial_pos;
            st.last_saved_sec = 0;
            st.audio_started = true;
            st.history_generation = None;
            st.resume_at = (initial_pos > 0.0).then_some(initial_pos);
            let liked = st.liked_ids.contains(&track.id);
            (
                prev_track,
                prev_played,
                prev_play_id,
                play_id,
                track,
                next_track_id,
                st.generation,
                api,
                uid,
                current_list_index(&st),
                liked,
                st.wave.clone(),
                initial_pos,
                duration_secs,
                audio_quality,
                track_gain,
                ai_behavior,
                ai_strict,
                can_auto_skip,
            )
        };

        if start_at.is_none()
            && can_auto_skip
            && crate::slopless::should_take_action_fast(&track, ai_strict)
        {
            let do_dislike = ai_behavior == "dislike"
                || (ai_behavior == "dislike_if_not_liked" && !liked);
            let do_skip = do_dislike
                || ai_behavior == "skip"
                || (ai_behavior == "skip_if_not_liked" && !liked);
            if do_skip {
                if wave.is_some() {
                    self.clone().maybe_extend_wave(index);
                }
                if do_dislike {
                    self.notify(format!("ИИ-трек «{}» дизлайкнут и пропущен", track.title));
                    self.dislike_now();
                } else {
                    self.notify(format!("ИИ-трек «{}» пропущен", track.title));
                    self.step(1, true);
                }
                return;
            }
        }

        self.send_queue();
        self.persist_session();

        if let (Some(w), Some(api_fb)) = (wave.clone(), api.clone()) {
            let cur_cid = track.composite_id();
            let prev_cid = prev_track.as_ref().filter(|t| t.id != track.id).map(|t| t.composite_id());
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

        // Report final play-audio/plays for previous track (including My Wave!) and start event for new track
        if let Some(api_scrobble) = api.clone() {
            let prev_report = prev_track
                .filter(|t| t.id != track.id && prev_played >= 5.0 && !prev_play_id.is_empty());
            let cur_track_clone = track.clone();
            let cur_play_id = play_id.clone();
            let in_wave = wave.is_some();
            self.rt_handle.spawn(async move {
                let from = if in_wave { "desktop_win-home-radio-default" } else { "desktop_win-home-playlist_of_the_day-playlist-default" };
                let ctx = if in_wave { Some("radio") } else { None };
                if let Some(prev) = prev_report {
                    let prev_cached = cache::is_track_cached(&prev.id);
                    api_scrobble
                        .play_audio(uid, &prev, &prev_play_id, from, prev_cached, prev_played, prev_played, ctx, None)
                        .await;
                }
                let cur_cached = cache::is_track_cached(&cur_track_clone.id);
                api_scrobble
                    .play_audio(uid, &cur_track_clone, &cur_play_id, from, cur_cached, 0.0, initial_pos, ctx, None)
                    .await;
            });
        }

        let cover_url = cache::resolve_track_cover_url(&track, 400);
        let has_cover = !cover_url.is_empty();

        self.send_event(EVENT_NOW_PLAYING, &NowPlayingPayload {
            has_track: true,
            id: track.id.clone(),
            title: track.title.clone(),
            artists: track.artists.clone(),
            artist_links: artist_links_for(&track),
            album: track.album_title.clone(),
            cover_url: cover_url.clone(),
            has_cover,
            duration_ms: track.duration_ms,
            duration_text: fmt_time(track.duration_ms as f64 / 1000.0),
            liked,
            has_artist: track.artist_id.is_some(),
            has_album: track.album_id.is_some(),
            is_ai: track.is_ai || crate::slopless::is_track_ai_fast(&track),
        });

        let tracks: Vec<TrackItemPayload> = {
            let st = self.state.lock();
            st.list.iter().map(|t| track_payload(t, &st.liked_ids)).collect()
        };

        self.set_playing(false, true);

        let initial_progress = if duration_secs > 0.0 {
            (initial_pos / duration_secs).clamp(0.0, 1.0) as f32
        } else {
            0.0
        };
        self.send_event(EVENT_PLAYBACK_PROGRESS, &PlaybackProgressPayload {
            position_secs: initial_pos,
            duration_secs,
            position_text: fmt_time(initial_pos),
            duration_text: fmt_time(duration_secs),
            progress: initial_progress,
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
        self.lastfm.set_track(&track);

        {
            let this_ai = self.clone();
            let track_ai = track.clone();
            self.rt_handle.spawn(async move {
                let (is_ai_label, should_act) =
                    crate::slopless::check_track_online(&this_ai.http, &track_ai, ai_strict).await;
                if is_ai_label {
                    this_ai.lastfm.mark_track_ai(&track_ai.id);
                    let mut updated = false;
                    {
                        let mut st = this_ai.state.lock();
                        for t in &mut st.queue {
                            if t.id == track_ai.id && !t.is_ai {
                                t.is_ai = true;
                                updated = true;
                            }
                        }
                        for t in &mut st.list {
                            if t.id == track_ai.id && !t.is_ai {
                                t.is_ai = true;
                                updated = true;
                            }
                        }
                    }
                    if updated {
                        this_ai.refresh_rows();
                    }
                }
                if should_act && start_at.is_none() && this_ai.generation() == generation {
                    let (beh, is_liked, can_skip) = {
                        let st = this_ai.state.lock();
                        let is_liked = st.liked_ids.contains(&track_ai.id);
                        let can_skip = st.wave.is_some() || st.queue.len() > 1;
                        (st.ai_music_behavior.clone(), is_liked, can_skip)
                    };
                    if can_skip {
                        let do_dislike = beh == "dislike"
                            || (beh == "dislike_if_not_liked" && !is_liked);
                        let do_skip = do_dislike
                            || beh == "skip"
                            || (beh == "skip_if_not_liked" && !is_liked);
                        if do_dislike {
                            this_ai.notify(format!("ИИ-трек «{}» дизлайкнут и пропущен", track_ai.title));
                            this_ai.dislike_now();
                        } else if do_skip {
                            this_ai.notify(format!("ИИ-трек «{}» пропущен", track_ai.title));
                            this_ai.step(1, true);
                        }
                    }
                }
            });
        }

        let audio_override = lookup_mod_track_override(&track.id);
        let has_custom_audio = audio_override.as_ref().is_some_and(|ov| {
            ov.local_file.is_some() || ov.audio_url.is_some() || ov.audio_track_id.is_some()
        });

        // 1. Mod local file audio override (plays directly from disk, works offline)
        if let Some(ref ov) = audio_override {
            if let Some(ref local_path) = ov.local_file {
                if let Ok(file) = std::fs::File::open(local_path) {
                    if let Ok(meta) = file.metadata() {
                        self.audio.load(
                            generation,
                            SourceData::Cached {
                                file,
                                len: meta.len(),
                                hint: ov.codec.clone(),
                            },
                            track_gain,
                        );
                        if let Some(next_id) = next_track_id {
                            self.prefetch(next_id);
                        }
                        return;
                    }
                }
            }
        }

        if !has_custom_audio {
            if let Some((file, len)) = cache::open_cached_track(&track.id) {
                self.audio.load(
                    generation,
                    SourceData::Cached { file, len, hint: None },
                    track_gain,
                );
                if let Some(next_id) = next_track_id {
                    self.prefetch(next_id);
                }
                return;
            }
        }

        self.audio.stop();

        // 2. Mod direct HTTPS/localhost audio URL override
        if let Some(ref ov) = audio_override {
            if let Some(ref custom_url) = ov.audio_url {
                let is_safe_url = custom_url.starts_with("https://")
                    || custom_url.starts_with("http://127.0.0.1")
                    || custom_url.starts_with("http://localhost");
                if is_safe_url {
                    let http = self.http.clone();
                    let url_owned = custom_url.clone();
                    let cache_id = format!("mod-{}", track.id);
                    let codec_hint = ov.codec.clone();
                    let this = self.clone();
                    self.rt_handle.spawn(async move {
                        let res = cache::stream_track(http, url_owned, cache_id).await;
                        if this.generation() != generation {
                            return;
                        }
                        match res {
                            Ok(reader) => {
                                this.audio.load(
                                    generation,
                                    SourceData::Stream { reader, hint: codec_hint },
                                    track_gain,
                                );
                                if let Some(next_id) = next_track_id {
                                    this.prefetch(next_id);
                                }
                            }
                            Err(e) => {
                                this.set_playing(false, false);
                                this.error(format!("«{}» (мод): {e:#}", track.title));
                            }
                        }
                    });
                    return;
                }
            }
        }

        let Some(api) = api else {
            self.state.lock().audio_started = false;
            self.set_playing(false, false);
            self.error("Трек не сохранён на устройстве. Для загрузки нужен вход в аккаунт.");
            return;
        };

        let resolved_stream_id = audio_override
            .as_ref()
            .and_then(|ov| ov.audio_track_id.clone())
            .filter(|s| !s.trim().is_empty())
            .unwrap_or_else(|| track.id.clone());
        let stream_cache_id = if resolved_stream_id != track.id {
            format!("mod-{}", track.id)
        } else {
            track.id.clone()
        };

        let this = self.clone();
        self.rt_handle.spawn(async move {
            let res = async {
                let info = api.track_stream_info(&resolved_stream_id, &audio_quality).await?;
                if this.generation() != generation {
                    anyhow::bail!("cancelled");
                }
                let reader = cache::stream_track(api.http().clone(), info.url, stream_cache_id).await?;
                Ok::<_, anyhow::Error>((reader, info.codec))
            }
            .await;

            if this.generation() != generation {
                return;
            }
            match res {
                Ok((reader, codec)) => {
                    this.audio.load(
                        generation,
                        SourceData::Stream { reader, hint: Some(codec) },
                        track_gain,
                    );
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
        let (api, audio_quality) = {
            let st = self.state.lock();
            (st.api.clone(), st.audio_quality.clone())
        };
        let Some(api) = api else { return };
        self.rt_handle.spawn(async move {
            let Ok(info) = api.track_stream_info(&track_id, &audio_quality).await else { return };
            let Some(path) = cache::track_path(&track_id) else { return };
            if cache::download_to_file(api.http(), &info.url, &path).await.is_ok() {
                let _ = tokio::task::spawn_blocking(cache::trim_track_cache).await;
            }
        });
    }

    pub fn maybe_extend_wave(self: Arc<Self>, current_index: usize) {
        let (api, session_id, seed, filters, queue_ids) = {
            let mut st = self.state.lock();
            let len = st.queue.len();
            let Some(api) = st.api.clone() else { return };
            let queue_ids: Vec<String> = st.queue.iter().map(Track::composite_id).collect();
            let Some(w) = &mut st.wave else { return };
            if w.fetching_more || current_index + 3 < len {
                return;
            }
            w.fetching_more = true;
            (api, w.session_id.clone(), w.seed.clone(), w.filters.clone(), queue_ids)
        };

        let this = self.clone();
        self.rt_handle.spawn(async move {
            let res = api.rotor_session_tracks(&session_id, &queue_ids).await;
            let (new_session_id, batch_res) = match res {
                Ok(batch) if batch.unknown_session => {
                    let mut seeds = vec![seed.clone()];
                    seeds.extend(filters.clone());
                    let seed_refs: Vec<&str> = seeds.iter().map(String::as_str).collect();
                    match api.rotor_session_new(&seed_refs).await {
                        Ok(new_sess) => (
                            Some(new_sess.session_id),
                            Ok((new_sess.batch_id, new_sess.tracks)),
                        ),
                        Err(e) => (None, Err(e)),
                    }
                }
                Ok(batch) => (None, Ok((batch.batch_id, batch.tracks))),
                Err(e) => (None, Err(e)),
            };
            let resume;
            let mut new_for_view = false;
            let mut wave_cache_update = None;
            let mut fresh_for_ai = Vec::new();
            {
                let mut st = this.state.lock();
                let showing_wave = st.list.len() == st.queue.len()
                    && st.list.iter().zip(&st.queue).all(|(a, b)| a.id == b.id);
                let known: HashSet<String> = st.queue.iter().map(|t| t.id.clone()).collect();
                let State { wave, queue, list, views, .. } = &mut *st;
                let Some(w) = wave.as_mut().filter(|w| w.session_id == session_id) else {
                    return;
                };
                w.fetching_more = false;
                if let Some(new_sid) = new_session_id {
                    w.session_id = new_sid;
                }
                resume = std::mem::take(&mut w.resume_on_load);
                if let Ok((batch_id, more)) = batch_res {
                    if !batch_id.is_empty() {
                        w.batch_id = batch_id;
                    }
                    let fresh: Vec<Track> =
                        more.into_iter().filter(|t| !known.contains(&t.id)).collect();
                    if !fresh.is_empty() {
                        fresh_for_ai = fresh.clone();
                        w.tracks.extend(fresh.iter().cloned());
                        let key = w.cache_key();
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
            if !fresh_for_ai.is_empty() {
                this.spawn_ai_verification(fresh_for_ai);
            }
            if resume {
                this.step(1, false);
            }
        });
    }

    pub fn on_audio(self: Arc<Self>, event: Event) {
        let current = self.generation();
        match event {
            Event::Started(g) | Event::GaplessTransition(g) if g == current => {
                self.mpris.set_status(MprisStatus::Playing, 0.0);
                self.discord.set_status(MprisStatus::Playing, 0.0);
                self.lastfm.on_started();
                let resume = self.state.lock().resume_at.take();
                if let Some(secs) = resume {
                    self.audio.seek(secs);
                    let mut st = self.state.lock();
                    st.position_secs = secs;
                    st.seek_target_secs = secs;
                    st.last_seek_time = Some(std::time::Instant::now());
                }
                self.set_playing(true, false);
            }
            Event::Position { generation, secs, paused } if generation == current => {
                let (local_record, server_scrobble) = {
                    let mut st = self.state.lock();
                    let local_rec = if !paused && secs >= 5.0 && st.history_generation != Some(generation) {
                        st.history_generation = Some(generation);
                        current_track(&st).cloned()
                    } else {
                        None
                    };
                    let threshold = (st.duration_secs * 0.5).clamp(5.0, 30.0);
                    let srv = if !paused && secs >= threshold && !st.play_scrobbled && !st.current_play_id.is_empty() {
                        st.play_scrobbled = true;
                        current_track(&st).cloned().map(|t| (t, st.api.clone(), st.uid, st.current_play_id.clone(), st.wave.is_some()))
                    } else {
                        None
                    };
                    (local_rec, srv)
                };
                if let Some(track) = local_record {
                    let this = self.clone();
                    self.rt_handle.spawn(async move {
                        match tokio::task::spawn_blocking(move || crate::history::record(track)).await {
                            Ok(Ok(tracks)) => this.send_history_tracks(tracks),
                            _ => this.error("Не удалось сохранить историю прослушивания"),
                        }
                    });
                }
                if let Some((track, Some(api), uid, play_id, in_wave)) = server_scrobble {
                    let from_cache = cache::is_track_cached(&track.id);
                    self.rt_handle.spawn(async move {
                        let from = if in_wave { "desktop_win-home-radio-default" } else { "desktop_win-home-playlist_of_the_day-playlist-default" };
                        let ctx = if in_wave { Some("radio") } else { None };
                        api.play_audio(uid, &track, &play_id, from, from_cache, secs, secs, ctx, None).await;
                    });
                }
                let (duration, should_save, ignore_pos, state_changed) = {
                    let mut st = self.state.lock();
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
                self.lastfm.on_position(secs, paused);
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
                let (repeat_mode, cur, ended_report) = {
                    let mut st = self.state.lock();
                    let rep = if !st.current_play_id.is_empty() && st.duration_secs >= 5.0 {
                        let play_id = std::mem::take(&mut st.current_play_id);
                        current_track(&st).cloned().map(|t| (t, st.api.clone(), st.uid, play_id, st.duration_secs, st.wave.is_some()))
                    } else {
                        None
                    };
                    (st.repeat_mode, st.current, rep)
                };
                if let Some((track, Some(api), uid, play_id, dur, in_wave)) = ended_report {
                    let from_cache = cache::is_track_cached(&track.id);
                    self.rt_handle.spawn(async move {
                        let from = if in_wave { "desktop_win-home-radio-default" } else { "desktop_win-home-playlist_of_the_day-playlist-default" };
                        let ctx = if in_wave { Some("radio") } else { None };
                        api.play_audio(uid, &track, &play_id, from, from_cache, dur, dur, ctx, None).await;
                    });
                }
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
                self.lastfm.set_stopped();
                self.state.lock().audio_started = false;
                self.set_playing(false, false);
                self.error(msg);
            }
            _ => {}
        }
    }

    pub fn toggle(self: Arc<Self>) {
        let (started, current, pos, duration_secs) = {
            let st = self.state.lock();
            (st.audio_started, st.current, st.position_secs, st.duration_secs)
        };
        if started {
            self.audio.toggle();
            self.persist_session();
        } else if let Some(idx) = current {
            let resume_pos = (pos > 0.5 && (duration_secs <= 2.0 || pos < duration_secs - 0.5)).then_some(pos);
            self.play_index_at(idx, false, resume_pos);
        }
    }

    pub fn play(self: Arc<Self>) {
        if self.state.lock().audio_started {
            self.audio.play();
        } else {
            self.toggle();
        }
    }

    pub fn toggle_repeat(self: Arc<Self>) {
        let mode = {
            let mut st = self.state.lock();
            st.repeat_mode = (st.repeat_mode + 1) % 3;
            st.repeat_mode
        };
        self.send_playback_state(false);
        self.rt_handle.spawn_blocking(move || {
            config::update_settings(|s| s.repeat_mode = mode);
        });
    }

    pub fn toggle_shuffle(self: Arc<Self>) {
        let (shuffle_on, extend_wave_idx) = {
            let mut st = self.state.lock();
            st.shuffle = !st.shuffle;
            let mut extend_wave = None;
            if st.shuffle {
                if st.unshuffled_queue.is_none() {
                    st.unshuffled_queue = Some(st.queue.clone());
                }
                if let Some(cur) = st.current
                    && cur < st.queue.len()
                {
                    let current_track = st.queue.remove(cur);
                    shuffle_slice(&mut st.queue);
                    st.queue.insert(0, current_track);
                    st.current = Some(0);
                    if st.wave.is_some() && st.queue.len() <= 5 {
                        extend_wave = Some(0);
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
                if let Some(cur) = st.current
                    && let Some(track) = st.queue.get(cur)
                {
                    let id = track.id.clone();
                    if let Some(new_idx) = orig.iter().position(|t| t.id == id) {
                        st.current = Some(new_idx);
                    }
                }
                st.queue = orig;
            }
            (st.shuffle, extend_wave)
        };
        self.send_playback_state(false);
        self.send_queue();
        self.persist_session();
        if let Some(idx) = extend_wave_idx {
            self.clone().maybe_extend_wave(idx);
        }
        self.rt_handle.spawn_blocking(move || {
            config::update_settings(|s| s.shuffle = shuffle_on);
        });
    }

    pub fn toggle_mute(self: Arc<Self>) {
        let new_vol = {
            let mut st = self.state.lock();
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
            let st = self.state.lock();
            (st.duration_secs, st.audio_started)
        };
        if duration > 0.0 {
            let secs = f64::from(fraction) * duration;
            {
                let mut st = self.state.lock();
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
            let mut st = self.state.lock();
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

    pub fn spectrum_levels(&self, out: &mut [f32]) -> usize {
        self.audio.spectrum_levels(out)
    }

    pub fn pause_if_playing(&self) {
        let is_playing = {
            let mut st = self.state.lock();
            if st.playing {
                st.playing = false;
                true
            } else {
                false
            }
        };
        if is_playing {
            self.audio.pause();
            self.send_playback_state(true);
            self.persist_session();
        }
    }

    pub fn save_volume(&self, vol: f32) {
        self.rt_handle.spawn_blocking(move || {
            config::update_settings(|s| s.volume = vol);
        });
    }

    fn snapshot_session(&self) -> Option<config::SavedSession> {
        let st = self.state.lock();
        let idx = st.current?;
        if st.queue.is_empty() {
            return None;
        }
        let wave = st.wave.as_ref().map(|w| config::SavedWaveState {
            seed: w.seed.clone(),
            filters: w.filters.clone(),
            selected: st.wave_selected.clone(),
            title: w.title.clone(),
            session_id: w.session_id.clone(),
            batch_id: w.batch_id.clone(),
            tracks: w.tracks.clone(),
        });
        Some(config::SavedSession {
            queue: st.queue.clone(),
            current_index: idx.min(st.queue.len() - 1),
            position_secs: st.position_secs.max(0.0),
            wave,
            unshuffled_queue: st.unshuffled_queue.clone(),
        })
    }

    pub fn persist_session(&self) {
        let Some(session) = self.snapshot_session() else { return };
        self.rt_handle.spawn_blocking(move || {
            config::update_settings(|s| s.session = Some(session));
        });
    }

    pub fn persist_session_sync(&self) {
        let Some(session) = self.snapshot_session() else { return };
        config::update_settings(|s| s.session = Some(session));
    }

    pub fn clear_saved_session(&self) {
        self.rt_handle.spawn_blocking(move || {
            config::update_settings(|s| s.session = None);
        });
    }

    pub fn apply_saved_session(self: &Arc<Self>, session: config::SavedSession) {
        if session.queue.is_empty() { return };
        let idx = session.current_index.min(session.queue.len() - 1);
        let track = session.queue[idx].clone();
        let duration_secs = track.duration_ms as f64 / 1000.0;
        let pos_secs = if duration_secs > 0.0 {
            session.position_secs.clamp(0.0, duration_secs)
        } else {
            session.position_secs.max(0.0)
        };
        let progress = if duration_secs > 0.0 { (pos_secs / duration_secs) as f32 } else { 0.0 };
        let pos_text = fmt_time(pos_secs);
        let dur_text = fmt_time(duration_secs);

        let (liked, restored_wave_selected) = {
            let mut st = self.state.lock();
            if st.current.is_some() || st.audio_started {
                return;
            }
            st.queue = session.queue;
            st.unshuffled_queue = session.unshuffled_queue;
            st.current = Some(idx);
            st.position_secs = pos_secs;
            st.last_saved_sec = 0;
            st.duration_secs = duration_secs;
            st.audio_started = false;
            if let Some(w) = session.wave {
                if !w.selected.is_empty() {
                    st.wave_selected = w.selected.clone();
                } else if !w.filters.is_empty() && !st.wave_groups.is_empty() {
                    let restored: Vec<(String, String)> = st
                        .wave_groups
                        .iter()
                        .filter_map(|g| {
                            g.choices
                                .iter()
                                .find(|c| w.filters.contains(&c.seed))
                                .map(|c| (g.key.clone(), c.seed.clone()))
                        })
                        .collect();
                    st.wave_selected.extend(restored);
                }
                st.wave = Some(WaveState {
                    seed: w.seed,
                    filters: w.filters,
                    title: w.title,
                    session_id: w.session_id,
                    batch_id: w.batch_id,
                    tracks: w.tracks,
                    fetching_more: false,
                    resume_on_load: false,
                });
            }
            (st.liked_ids.contains(&track.id), st.wave_selected.clone())
        };

        let cover_url = cache::resolve_track_cover_url(&track, 400);
        let has_cover = !cover_url.is_empty();

        self.send_event(EVENT_NOW_PLAYING, &NowPlayingPayload {
            has_track: true,
            id: track.id.clone(),
            title: track.title.clone(),
            artists: track.artists.clone(),
            artist_links: artist_links_for(&track),
            album: track.album_title.clone(),
            cover_url: cover_url.clone(),
            has_cover,
            duration_ms: track.duration_ms,
            duration_text: dur_text.clone(),
            liked,
            has_artist: track.artist_id.is_some(),
            has_album: track.album_id.is_some(),
            is_ai: track.is_ai || crate::slopless::is_track_ai_fast(&track),
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
        self.lastfm.set_track(&track);
        self.send_queue();
        if !restored_wave_selected.is_empty() {
            self.send_feature("wave_applied", serde_json::json!({"selected": restored_wave_selected}));
        }
    }

    pub fn restore_session(self: Arc<Self>) {
        let settings = config::load_settings();
        let Some(session) = settings.session else { return };
        self.apply_saved_session(session);
    }

    pub fn on_mpris(self: Arc<Self>, action: MprisAction) {
        match action {
            MprisAction::Play => self.clone().play(),
            MprisAction::Pause => {
                self.audio.pause();
                self.persist_session();
            }
            MprisAction::Toggle => self.clone().toggle(),
            MprisAction::Stop => {
                self.audio.stop();
                {
                    let mut st = self.state.lock();
                    st.audio_started = false;
                    st.generation += 1;
                }
                self.set_playing(false, false);
                self.mpris.set_status(MprisStatus::Stopped, 0.0);
                self.discord.set_stopped();
                self.lastfm.set_stopped();
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
