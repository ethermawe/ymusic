use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio::runtime::Handle;

use crate::api::Track;
use crate::config;
use crate::core::{EVENT_FEATURE, EventSink};

const LASTFM_ENDPOINT: &str = "https://ws.audioscrobbler.com/2.0/";
const MAX_PENDING_SCROBBLES: usize = 500;
const AUTH_POLL_ATTEMPTS: usize = 40; // ~100s at 2.5s interval

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct PendingScrobble {
    pub artist: String,
    pub track: String,
    #[serde(default)]
    pub album: String,
    #[serde(default)]
    pub duration: u64,
    pub timestamp: u64,
}

#[derive(Clone, Debug, Default)]
pub struct LastfmConfig {
    pub enabled: bool,
    pub now_playing: bool,
    pub love_on_like: bool,
    pub skip_ai: bool,
    pub custom_api_key: String,
    pub custom_api_secret: String,
}

#[derive(Clone, Debug)]
struct ActiveTrackState {
    id: String,
    artist: String,
    title: String,
    album: String,
    duration_secs: f64,
    is_ai: bool,
    started_ts: u64,
    accumulated_play_secs: f64,
    last_pos_secs: Option<f64>,
    now_playing_sent: bool,
    scrobbled: bool,
}

impl ActiveTrackState {
    fn new(track: &Track) -> Self {
        let artist = track
            .artist_links
            .first()
            .map(|(_, name)| name.trim())
            .filter(|s| !s.is_empty())
            .unwrap_or(track.artists.trim())
            .to_string();
        let duration_secs = if track.duration_ms > 0 {
            track.duration_ms as f64 / 1000.0
        } else {
            0.0
        };
        Self {
            id: track.id.clone(),
            artist,
            title: track.title.trim().to_string(),
            album: track.album_title.trim().to_string(),
            duration_secs,
            is_ai: track.is_ai,
            started_ts: unix_now(),
            accumulated_play_secs: 0.0,
            last_pos_secs: None,
            now_playing_sent: false,
            scrobbled: false,
        }
    }

    fn scrobble_threshold_secs(&self) -> Option<f64> {
        if self.artist.is_empty() || self.title.is_empty() {
            return None;
        }
        // Last.fm rule: track must be > 30s; scrobble after 50% or 240s, whichever comes first.
        if self.duration_secs > 0.0 && self.duration_secs < 30.0 {
            return None;
        }
        let target = if self.duration_secs > 0.0 {
            (self.duration_secs * 0.5).min(240.0).max(30.0)
        } else {
            120.0
        };
        Some(target)
    }

    fn advance_position(&mut self, secs: f64, paused: bool) -> bool {
        if self.scrobbled {
            return false;
        }
        if paused {
            self.last_pos_secs = Some(secs);
            return false;
        }
        if let Some(prev) = self.last_pos_secs {
            let delta = secs - prev;
            // Ignore pauses, backwards seeks, and big forward seeks (> 2.5s between updates).
            if delta > 0.0 && delta < 2.5 {
                self.accumulated_play_secs += delta;
            }
        }
        self.last_pos_secs = Some(secs);

        let Some(threshold) = self.scrobble_threshold_secs() else {
            return false;
        };
        if self.accumulated_play_secs >= threshold {
            self.scrobbled = true;
            return true;
        }
        false
    }
}

struct Inner {
    http: Client,
    rt: Option<Handle>,
    sink: Option<Arc<dyn EventSink>>,
    config: LastfmConfig,
    session_key: Option<String>,
    username: Option<String>,
    auth_gen: u64,
    authorizing: bool,
    status_text: String,
    is_error: bool,
    active: Option<ActiveTrackState>,
    pending: Vec<PendingScrobble>,
    flushing: bool,
}

#[derive(Clone)]
pub struct Lastfm {
    inner: Arc<Mutex<Inner>>,
}

impl Lastfm {
    pub fn disabled() -> Self {
        Self {
            inner: Arc::new(Mutex::new(Inner {
                http: Client::new(),
                rt: None,
                sink: None,
                config: LastfmConfig::default(),
                session_key: None,
                username: None,
                auth_gen: 0,
                authorizing: false,
                status_text: String::new(),
                is_error: false,
                active: None,
                pending: Vec::new(),
                flushing: false,
            })),
        }
    }

    pub fn spawn_with_sink(rt: Handle, http: Client, sink: Arc<dyn EventSink>) -> Self {
        Self {
            inner: Arc::new(Mutex::new(Inner {
                http,
                rt: Some(rt),
                sink: Some(sink),
                config: LastfmConfig::default(),
                session_key: None,
                username: None,
                auth_gen: 0,
                authorizing: false,
                status_text: String::new(),
                is_error: false,
                active: None,
                pending: Vec::new(),
                flushing: false,
            })),
        }
    }

    pub fn load_initial(&self, settings: &config::UserSettings) {
        let session = config::load_lastfm_session();
        let pending = load_pending_scrobbles();
        {
            let mut st = self.inner.lock().unwrap();
            st.config = LastfmConfig {
                enabled: settings.lastfm_enabled,
                now_playing: settings.lastfm_now_playing,
                love_on_like: settings.lastfm_love_on_like,
                skip_ai: settings.lastfm_skip_ai,
                custom_api_key: settings.lastfm_custom_api_key.clone().unwrap_or_default(),
                custom_api_secret: settings.lastfm_custom_api_secret.clone().unwrap_or_default(),
            };
            st.session_key = session;
            st.username = settings.lastfm_username.clone();
            st.pending = pending;
            st.status_text = build_default_status(&st);
            st.is_error = false;
        }
        self.emit_status(None);
        self.flush_pending();
    }

    pub fn set_config(&self, next: LastfmConfig) {
        let custom_key = next.custom_api_key.trim().to_string();
        let custom_secret = next.custom_api_secret.trim().to_string();
        config::update_settings(|s| {
            s.lastfm_enabled = next.enabled;
            s.lastfm_now_playing = next.now_playing;
            s.lastfm_love_on_like = next.love_on_like;
            s.lastfm_skip_ai = next.skip_ai;
            s.lastfm_custom_api_key = (!custom_key.is_empty()).then(|| custom_key.clone());
            if !custom_secret.is_empty() {
                s.lastfm_custom_api_secret = Some(custom_secret.clone());
            } else if custom_key.is_empty() {
                s.lastfm_custom_api_secret = None;
            }
        });

        {
            let mut st = self.inner.lock().unwrap();
            st.config.enabled = next.enabled;
            st.config.now_playing = next.now_playing;
            st.config.love_on_like = next.love_on_like;
            st.config.skip_ai = next.skip_ai;
            st.config.custom_api_key = custom_key;
            if !custom_secret.is_empty() {
                st.config.custom_api_secret = custom_secret;
            } else if st.config.custom_api_key.is_empty() {
                st.config.custom_api_secret.clear();
            }
            st.status_text = build_default_status(&st);
            st.is_error = false;
        }
        self.emit_status(None);
        self.flush_pending();
    }

    pub fn clear_custom_keys(&self) {
        config::update_settings(|s| {
            s.lastfm_custom_api_key = None;
            s.lastfm_custom_api_secret = None;
        });
        {
            let mut st = self.inner.lock().unwrap();
            st.config.custom_api_key.clear();
            st.config.custom_api_secret.clear();
            st.status_text = build_default_status(&st);
            st.is_error = false;
        }
        self.emit_status(None);
    }

    pub fn start_auth(&self) {
        let (rt, http, creds, auth_gen_id) = {
            let mut st = self.inner.lock().unwrap();
            let Some(rt) = st.rt.clone() else { return };
            let Some(creds) = resolve_credentials(&st.config) else {
                st.authorizing = false;
                st.is_error = true;
                st.status_text = "Укажите API Key и Secret Last.fm".to_string();
                drop(st);
                self.emit_status(None);
                return;
            };
            st.auth_gen = st.auth_gen.wrapping_add(1);
            st.authorizing = true;
            st.is_error = false;
            st.status_text = "Запрашиваем токен авторизации…".to_string();
            (rt, st.http.clone(), creds, st.auth_gen)
        };
        self.emit_status(None);

        let this = self.clone();
        rt.spawn(async move {
            let token = match fetch_auth_token(&http, &creds).await {
                Ok(t) => t,
                Err(e) => {
                    let mut st = this.inner.lock().unwrap();
                    if st.auth_gen == auth_gen_id {
                        st.authorizing = false;
                        st.is_error = true;
                        st.status_text = format!("Ошибка Last.fm: {e}");
                    }
                    drop(st);
                    this.emit_status(None);
                    return;
                }
            };

            let auth_url = format!(
                "https://www.last.fm/api/auth/?api_key={}&token={}",
                creds.api_key, token
            );
            {
                let mut st = this.inner.lock().unwrap();
                if st.auth_gen != auth_gen_id {
                    return;
                }
                st.status_text = "Подтвердите вход в открывшемся окне браузера…".to_string();
                st.is_error = false;
            }
            this.emit_status(Some(auth_url));

            for _ in 0..AUTH_POLL_ATTEMPTS {
                tokio::time::sleep(Duration::from_millis(2500)).await;
                {
                    let st = this.inner.lock().unwrap();
                    if st.auth_gen != auth_gen_id || !st.authorizing {
                        return;
                    }
                }
                match fetch_auth_session(&http, &creds, &token).await {
                    Ok(SessionPoll::Authorized { name, key }) => {
                        let _ = config::save_lastfm_session(&key);
                        let uname = name.clone();
                        config::update_settings(|s| {
                            s.lastfm_username = Some(uname);
                            s.lastfm_enabled = true;
                        });
                        {
                            let mut st = this.inner.lock().unwrap();
                            if st.auth_gen != auth_gen_id {
                                return;
                            }
                            st.authorizing = false;
                            st.session_key = Some(key);
                            st.username = Some(name);
                            st.config.enabled = true;
                            st.is_error = false;
                            st.status_text = build_default_status(&st);
                        }
                        this.emit_status(None);
                        this.flush_pending();
                        return;
                    }
                    Ok(SessionPoll::Pending) => continue,
                    Err(e) => {
                        let mut st = this.inner.lock().unwrap();
                        if st.auth_gen == auth_gen_id {
                            st.authorizing = false;
                            st.is_error = true;
                            st.status_text = format!("Вход отклонён: {e}");
                        }
                        drop(st);
                        this.emit_status(None);
                        return;
                    }
                }
            }

            let mut st = this.inner.lock().unwrap();
            if st.auth_gen == auth_gen_id && st.authorizing {
                st.authorizing = false;
                st.is_error = true;
                st.status_text = "Время ожидания подтверждения истекло".to_string();
            }
            drop(st);
            this.emit_status(None);
        });
    }

    pub fn cancel_auth(&self) {
        {
            let mut st = self.inner.lock().unwrap();
            st.auth_gen = st.auth_gen.wrapping_add(1);
            st.authorizing = false;
            st.is_error = false;
            st.status_text = build_default_status(&st);
        }
        self.emit_status(None);
    }

    pub fn disconnect(&self) {
        config::clear_lastfm_session();
        config::update_settings(|s| {
            s.lastfm_username = None;
        });
        {
            let mut st = self.inner.lock().unwrap();
            st.auth_gen = st.auth_gen.wrapping_add(1);
            st.authorizing = false;
            st.session_key = None;
            st.username = None;
            st.is_error = false;
            st.status_text = build_default_status(&st);
        }
        self.emit_status(None);
    }

    pub fn set_track(&self, track: &Track) {
        let mut st = self.inner.lock().unwrap();
        st.active = Some(ActiveTrackState::new(track));
    }

    pub fn set_stopped(&self) {
        let mut st = self.inner.lock().unwrap();
        st.active = None;
    }

    pub fn mark_track_ai(&self, track_id: &str) {
        let mut st = self.inner.lock().unwrap();
        if let Some(active) = st.active.as_mut()
            && active.id == track_id
        {
            active.is_ai = true;
        }
    }

    pub fn on_started(&self) {
        let (rt, http, creds, sk, np) = {
            let mut guard = self.inner.lock().unwrap();
            let st = &mut *guard;
            let Some(active) = st.active.as_mut() else { return };
            active.started_ts = unix_now();
            active.accumulated_play_secs = 0.0;
            active.last_pos_secs = Some(0.0);
            active.scrobbled = false;

            if !st.config.enabled || !st.config.now_playing || (st.config.skip_ai && active.is_ai) {
                return;
            }
            if active.now_playing_sent || active.artist.is_empty() || active.title.is_empty() {
                return;
            }
            let Some(rt) = st.rt.clone() else { return };
            let Some(creds) = resolve_credentials(&st.config) else { return };
            let Some(sk) = st.session_key.clone() else { return };
            active.now_playing_sent = true;
            let req = (
                active.artist.clone(),
                active.title.clone(),
                active.album.clone(),
                active.duration_secs.round() as u64,
            );
            (rt, st.http.clone(), creds, sk, req)
        };

        let this = self.clone();
        rt.spawn(async move {
            if let Err(ApiErr::InvalidSession) =
                send_now_playing(&http, &creds, &sk, &np.0, &np.1, &np.2, np.3).await
            {
                this.handle_invalid_session();
            }
        });
    }

    pub fn on_position(&self, secs: f64, paused: bool) {
        let pending_item = {
            let mut guard = self.inner.lock().unwrap();
            let st = &mut *guard;
            let skip_ai = st.config.skip_ai;
            let enabled = st.config.enabled;
            let has_session = st.session_key.is_some();
            let send_np = enabled && st.config.now_playing && has_session;

            let Some(active) = st.active.as_mut() else {
                return;
            };
            if skip_ai && active.is_ai {
                return;
            }

            // If resume/unpause happened without a fresh Started event, still send NowPlaying once.
            if !paused && send_np && !active.now_playing_sent && !active.artist.is_empty() && !active.title.is_empty() {
                active.now_playing_sent = true;
                if let (Some(rt), Some(creds), Some(sk)) = (
                    st.rt.clone(),
                    resolve_credentials(&st.config),
                    st.session_key.clone(),
                ) {
                    let http = st.http.clone();
                    let artist = active.artist.clone();
                    let title = active.title.clone();
                    let album = active.album.clone();
                    let dur = active.duration_secs.round() as u64;
                    let this = self.clone();
                    rt.spawn(async move {
                        if let Err(ApiErr::InvalidSession) =
                            send_now_playing(&http, &creds, &sk, &artist, &title, &album, dur).await
                        {
                            this.handle_invalid_session();
                        }
                    });
                }
            }

            if !enabled || !has_session {
                return;
            }
            if active.advance_position(secs, paused) {
                Some(PendingScrobble {
                    artist: active.artist.clone(),
                    track: active.title.clone(),
                    album: active.album.clone(),
                    duration: active.duration_secs.round() as u64,
                    timestamp: active.started_ts.max(1),
                })
            } else {
                None
            }
        };

        if let Some(scrobble) = pending_item {
            {
                let mut st = self.inner.lock().unwrap();
                push_pending(&mut st.pending, scrobble);
                save_pending_scrobbles(&st.pending);
            }
            self.emit_status(None);
            self.flush_pending();
        }
    }

    pub fn love_track(&self, track: &Track, loved: bool) {
        let (rt, http, creds, sk, artist, title) = {
            let st = self.inner.lock().unwrap();
            if !st.config.enabled || !st.config.love_on_like || (st.config.skip_ai && track.is_ai) {
                return;
            }
            let Some(rt) = st.rt.clone() else { return };
            let Some(creds) = resolve_credentials(&st.config) else { return };
            let Some(sk) = st.session_key.clone() else { return };
            let artist = track
                .artist_links
                .first()
                .map(|(_, name)| name.trim())
                .filter(|s| !s.is_empty())
                .unwrap_or(track.artists.trim())
                .to_string();
            let title = track.title.trim().to_string();
            if artist.is_empty() || title.is_empty() {
                return;
            }
            (rt, st.http.clone(), creds, sk, artist, title)
        };

        let this = self.clone();
        rt.spawn(async move {
            if let Err(ApiErr::InvalidSession) =
                send_love(&http, &creds, &sk, &artist, &title, loved).await
            {
                this.handle_invalid_session();
            }
        });
    }

    fn flush_pending(&self) {
        let (rt, http, creds, sk, batch) = {
            let mut st = self.inner.lock().unwrap();
            if st.flushing || !st.config.enabled || st.pending.is_empty() {
                return;
            }
            let Some(rt) = st.rt.clone() else { return };
            let Some(creds) = resolve_credentials(&st.config) else { return };
            let Some(sk) = st.session_key.clone() else { return };
            st.flushing = true;
            let count = st.pending.len().min(50);
            (rt, st.http.clone(), creds, sk, st.pending[..count].to_vec())
        };

        let this = self.clone();
        rt.spawn(async move {
            let res = send_scrobble_batch(&http, &creds, &sk, &batch).await;
            let mut trigger_next = false;
            match res {
                Ok(()) => {
                    let mut st = this.inner.lock().unwrap();
                    st.flushing = false;
                    let drain_n = batch.len().min(st.pending.len());
                    st.pending.drain(..drain_n);
                    save_pending_scrobbles(&st.pending);
                    st.is_error = false;
                    st.status_text = build_default_status(&st);
                    trigger_next = !st.pending.is_empty();
                }
                Err(ApiErr::InvalidSession) => {
                    this.inner.lock().unwrap().flushing = false;
                    this.handle_invalid_session();
                    return;
                }
                Err(ApiErr::Network(msg)) => {
                    let mut st = this.inner.lock().unwrap();
                    st.flushing = false;
                    eprintln!("[lastfm] scrobble deferred ({msg})");
                }
            }
            this.emit_status(None);
            if trigger_next {
                this.flush_pending();
            }
        });
    }

    fn handle_invalid_session(&self) {
        config::clear_lastfm_session();
        config::update_settings(|s| {
            s.lastfm_username = None;
        });
        {
            let mut st = self.inner.lock().unwrap();
            st.session_key = None;
            st.username = None;
            st.is_error = true;
            st.status_text = "Сессия Last.fm истекла — войдите заново".to_string();
        }
        self.emit_status(None);
    }

    pub fn emit_status(&self, auth_url: Option<String>) {
        let (sink, payload) = {
            let st = self.inner.lock().unwrap();
            let Some(sink) = st.sink.clone() else { return };
            let has_builtin = builtin_credentials().is_some();
            let configured = resolve_credentials(&st.config).is_some();
            let payload = serde_json::json!({
                "type": "lastfm_status",
                "has_builtin_keys": has_builtin,
                "configured": configured,
                "connected": st.session_key.is_some(),
                "authorizing": st.authorizing,
                "username": st.username.clone().unwrap_or_default(),
                "text": st.status_text,
                "is_error": st.is_error,
                "pending_count": st.pending.len(),
                "enabled": st.config.enabled,
                "now_playing": st.config.now_playing,
                "love_on_like": st.config.love_on_like,
                "skip_ai": st.config.skip_ai,
                "custom_api_key": st.config.custom_api_key,
                "has_custom_secret": !st.config.custom_api_secret.is_empty(),
                "auth_url": auth_url.unwrap_or_default(),
            });
            (sink, payload)
        };
        sink.on_event(EVENT_FEATURE, &payload.to_string());
    }
}

#[derive(Clone, Debug)]
struct Credentials {
    api_key: String,
    api_secret: String,
}

fn builtin_credentials() -> Option<Credentials> {
    let compile_key = option_env!("LASTFM_API_KEY").map(str::trim).filter(|s| !s.is_empty());
    let compile_secret = option_env!("LASTFM_API_SECRET").map(str::trim).filter(|s| !s.is_empty());

    let runtime_key = std::env::var("LASTFM_API_KEY").ok().map(|s| s.trim().to_string()).filter(|s| !s.is_empty());
    let runtime_secret = std::env::var("LASTFM_API_SECRET").ok().map(|s| s.trim().to_string()).filter(|s| !s.is_empty());

    let api_key = runtime_key.or_else(|| compile_key.map(str::to_string))?;
    let api_secret = runtime_secret.or_else(|| compile_secret.map(str::to_string))?;
    Some(Credentials { api_key, api_secret })
}

fn resolve_credentials(cfg: &LastfmConfig) -> Option<Credentials> {
    let ck = cfg.custom_api_key.trim();
    let cs = cfg.custom_api_secret.trim();
    if !ck.is_empty() && !cs.is_empty() {
        return Some(Credentials {
            api_key: ck.to_string(),
            api_secret: cs.to_string(),
        });
    }
    builtin_credentials()
}

fn build_default_status(st: &Inner) -> String {
    if st.authorizing {
        return "Ожидаем подтверждения в браузере…".to_string();
    }
    if resolve_credentials(&st.config).is_none() {
        return "Нужны API Key и Secret".to_string();
    }
    if st.session_key.is_some() {
        let user = st.username.as_deref().filter(|s| !s.is_empty()).unwrap_or("подключён");
        if !st.config.enabled {
            return format!("{user} (скробблинг отключён)");
        }
        if st.pending.is_empty() {
            return format!("Подключён ({user})");
        }
        return format!("Подключён ({user}, в очереди: {})", st.pending.len());
    }
    "Не подключён".to_string()
}

fn unix_now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

pub fn compute_api_sig(params: &[(&str, &str)], api_secret: &str) -> String {
    let mut sorted = BTreeMap::new();
    for (k, v) in params {
        if *k != "format" && *k != "callback" {
            sorted.insert(*k, *v);
        }
    }
    let mut raw = String::new();
    for (k, v) in sorted {
        raw.push_str(k);
        raw.push_str(v);
    }
    raw.push_str(api_secret);
    format!("{:x}", md5::compute(raw.as_bytes()))
}

enum SessionPoll {
    Pending,
    Authorized { name: String, key: String },
}

enum ApiErr {
    InvalidSession,
    Network(String),
}

async fn fetch_auth_token(http: &Client, creds: &Credentials) -> Result<String, String> {
    let mut params = vec![
        ("method", "auth.getToken"),
        ("api_key", creds.api_key.as_str()),
    ];
    let sig = compute_api_sig(&params, &creds.api_secret);
    params.push(("api_sig", sig.as_str()));
    params.push(("format", "json"));

    let resp = http
        .get(LASTFM_ENDPOINT)
        .query(&params)
        .timeout(Duration::from_secs(10))
        .send()
        .await
        .map_err(|e| e.to_string())?;
    let val: Value = resp.json().await.map_err(|e| e.to_string())?;
    if let Some(msg) = val["message"].as_str() {
        return Err(msg.to_string());
    }
    val["token"]
        .as_str()
        .map(str::to_string)
        .ok_or_else(|| "пустой токен Last.fm".to_string())
}

async fn fetch_auth_session(
    http: &Client,
    creds: &Credentials,
    token: &str,
) -> Result<SessionPoll, String> {
    let mut params = vec![
        ("method", "auth.getSession"),
        ("api_key", creds.api_key.as_str()),
        ("token", token),
    ];
    let sig = compute_api_sig(&params, &creds.api_secret);
    params.push(("api_sig", sig.as_str()));
    params.push(("format", "json"));

    let resp = http
        .get(LASTFM_ENDPOINT)
        .query(&params)
        .timeout(Duration::from_secs(10))
        .send()
        .await
        .map_err(|e| e.to_string())?;
    let val: Value = resp.json().await.map_err(|e| e.to_string())?;
    if let Some(code) = val["error"].as_i64() {
        if code == 14 {
            return Ok(SessionPoll::Pending);
        }
        let msg = val["message"].as_str().unwrap_or("ошибка авторизации");
        return Err(msg.to_string());
    }
    let name = val["session"]["name"].as_str().unwrap_or("").to_string();
    let key = val["session"]["key"]
        .as_str()
        .filter(|s| !s.is_empty())
        .ok_or_else(|| "Last.fm не вернул ключ сессии".to_string())?
        .to_string();
    Ok(SessionPoll::Authorized { name, key })
}

async fn post_signed(
    http: &Client,
    creds: &Credentials,
    owned_params: Vec<(String, String)>,
) -> Result<(), ApiErr> {
    let borrowed: Vec<(&str, &str)> = owned_params
        .iter()
        .map(|(k, v)| (k.as_str(), v.as_str()))
        .collect();
    let sig = compute_api_sig(&borrowed, &creds.api_secret);

    let mut form = owned_params;
    form.push(("api_sig".to_string(), sig));
    form.push(("format".to_string(), "json".to_string()));

    let resp = http
        .post(LASTFM_ENDPOINT)
        .form(&form)
        .timeout(Duration::from_secs(12))
        .send()
        .await
        .map_err(|e| ApiErr::Network(e.to_string()))?;

    let status = resp.status();
    let val: Value = resp
        .json()
        .await
        .map_err(|e| ApiErr::Network(e.to_string()))?;
    if let Some(err_code) = val["error"].as_i64() {
        if err_code == 9 || err_code == 4 || err_code == 10 {
            return Err(ApiErr::InvalidSession);
        }
        let msg = val["message"].as_str().unwrap_or("Last.fm API error");
        return Err(ApiErr::Network(format!("{err_code}: {msg}")));
    }
    if !status.is_success() {
        return Err(ApiErr::Network(format!("HTTP {status}")));
    }
    Ok(())
}

async fn send_now_playing(
    http: &Client,
    creds: &Credentials,
    sk: &str,
    artist: &str,
    title: &str,
    album: &str,
    duration: u64,
) -> Result<(), ApiErr> {
    let mut params = vec![
        ("method".into(), "track.updateNowPlaying".into()),
        ("api_key".into(), creds.api_key.clone()),
        ("sk".into(), sk.to_string()),
        ("artist".into(), artist.to_string()),
        ("track".into(), title.to_string()),
    ];
    if !album.is_empty() {
        params.push(("album".into(), album.to_string()));
    }
    if duration > 0 {
        params.push(("duration".into(), duration.to_string()));
    }
    post_signed(http, creds, params).await
}

async fn send_love(
    http: &Client,
    creds: &Credentials,
    sk: &str,
    artist: &str,
    title: &str,
    loved: bool,
) -> Result<(), ApiErr> {
    let method = if loved { "track.love" } else { "track.unlove" };
    let params = vec![
        ("method".into(), method.into()),
        ("api_key".into(), creds.api_key.clone()),
        ("sk".into(), sk.to_string()),
        ("artist".into(), artist.to_string()),
        ("track".into(), title.to_string()),
    ];
    post_signed(http, creds, params).await
}

async fn send_scrobble_batch(
    http: &Client,
    creds: &Credentials,
    sk: &str,
    batch: &[PendingScrobble],
) -> Result<(), ApiErr> {
    if batch.is_empty() {
        return Ok(());
    }
    let mut params = vec![
        ("method".into(), "track.scrobble".into()),
        ("api_key".into(), creds.api_key.clone()),
        ("sk".into(), sk.to_string()),
    ];
    for (idx, item) in batch.iter().enumerate() {
        params.push((format!("artist[{idx}]"), item.artist.clone()));
        params.push((format!("track[{idx}]"), item.track.clone()));
        params.push((format!("timestamp[{idx}]"), item.timestamp.to_string()));
        if !item.album.is_empty() {
            params.push((format!("album[{idx}]"), item.album.clone()));
        }
        if item.duration > 0 {
            params.push((format!("duration[{idx}]"), item.duration.to_string()));
        }
    }
    post_signed(http, creds, params).await
}

fn pending_path() -> Option<PathBuf> {
    dirs::config_dir().map(|d| d.join("ymusic").join("lastfm_pending.json"))
}

fn push_pending(queue: &mut Vec<PendingScrobble>, item: PendingScrobble) {
    if queue.len() >= MAX_PENDING_SCROBBLES {
        let drop_n = queue.len() - MAX_PENDING_SCROBBLES + 1;
        queue.drain(..drop_n);
    }
    queue.push(item);
}

fn load_pending_scrobbles_from(path: &Path) -> Vec<PendingScrobble> {
    let Ok(data) = fs::read_to_string(path) else {
        return Vec::new();
    };
    serde_json::from_str(&data).unwrap_or_default()
}

fn save_pending_scrobbles_to(path: &Path, items: &[PendingScrobble]) {
    if items.is_empty() {
        let _ = fs::remove_file(path);
        return;
    }
    if let Some(dir) = path.parent() {
        let _ = fs::create_dir_all(dir);
    }
    if let Ok(data) = serde_json::to_string(items) {
        let _ = fs::write(path, data);
    }
}

fn load_pending_scrobbles() -> Vec<PendingScrobble> {
    pending_path()
        .map(|p| load_pending_scrobbles_from(&p))
        .unwrap_or_default()
}

fn save_pending_scrobbles(items: &[PendingScrobble]) {
    if let Some(path) = pending_path() {
        save_pending_scrobbles_to(&path, items);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_track(duration_ms: u64) -> Track {
        Track {
            id: "101".into(),
            album_id: None,
            artist_id: None,
            artist_links: vec![("1".into(), "Artist Name".into())],
            title: "Song Title".into(),
            artists: "Artist Name".into(),
            album_title: "Album".into(),
            cover_uri: None,
            duration_ms,
            available: true,
            is_ai: false,
            r128_i: None,
            r128_tp: None,
            has_sync_lyrics: false,
            has_text_lyrics: false,
        }
    }

    #[test]
    fn computes_md5_api_sig_sorted_excluding_format() {
        let sig = compute_api_sig(
            &[
                ("token", "tok123"),
                ("format", "json"),
                ("method", "auth.getSession"),
                ("api_key", "key456"),
            ],
            "sec789",
        );
        // Expected preimage: api_keykey456methodauth.getSessiontokentok123sec789
        let expected = format!(
            "{:x}",
            md5::compute(b"api_keykey456methodauth.getSessiontokentok123sec789")
        );
        assert_eq!(sig, expected);
    }

    #[test]
    fn scrobble_threshold_ignores_pauses_and_seeks_and_fires_once() {
        let mut active = ActiveTrackState::new(&sample_track(180_000)); // 3 min -> threshold 90s
        assert!(!active.advance_position(0.0, false));
        // Seeking straight from 1s to 120s must NOT trigger scrobble
        assert!(!active.advance_position(1.0, false));
        assert!(!active.advance_position(120.0, false));
        // Paused ticks don't count
        assert!(!active.advance_position(121.0, true));
        assert!(!active.advance_position(122.0, true));
        // Real 1s steps accumulate cleanly up to 90s
        let mut pos = 122.0;
        let mut fired = 0;
        for _ in 0..95 {
            pos += 1.0;
            if active.advance_position(pos, false) {
                fired += 1;
            }
        }
        assert_eq!(fired, 1);

        // Tracks shorter than 30s never scrobble
        let mut short = ActiveTrackState::new(&sample_track(25_000));
        for sec in 0..25 {
            assert!(!short.advance_position(sec as f64, false));
        }
    }

    #[test]
    fn pending_scrobbles_persist_and_cap() {
        let dir = std::env::temp_dir().join(format!("ymusic-lfm-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        let path = dir.join("lastfm_pending.json");
        let mut q = Vec::new();
        for i in 0..505u64 {
            push_pending(
                &mut q,
                PendingScrobble {
                    artist: "A".into(),
                    track: format!("T{i}"),
                    album: String::new(),
                    duration: 180,
                    timestamp: 1000 + i,
                },
            );
        }
        assert_eq!(q.len(), MAX_PENDING_SCROBBLES);
        save_pending_scrobbles_to(&path, &q);
        let loaded = load_pending_scrobbles_from(&path);
        assert_eq!(loaded.len(), MAX_PENDING_SCROBBLES);
        assert_eq!(loaded[0].track, "T5");
        let _ = fs::remove_dir_all(&dir);
    }
}
