mod api;
mod audio;
mod cache;
mod config;
mod discord;
mod dns;
mod mpris;

use std::cell::RefCell;
use std::collections::{HashMap, HashSet, VecDeque};
use std::rc::Rc;
use std::sync::{Arc, Mutex};
use std::time::Duration;

#[global_allocator]
static GLOBAL: mimalloc::MiMalloc = mimalloc::MiMalloc;

use anyhow::Result;
use serde::{Deserialize, Serialize};
use slint::{ComponentHandle, Model, ModelRc, SharedString, VecModel, Weak};
use tokio::runtime::Handle;
use tokio::sync::Semaphore;

use api::{AlbumCard, Api, ArtistCard, Track};
use audio::{Audio, Event, SourceData};
use discord::Discord;
use mpris::{Action as MprisAction, Meta as MprisMeta, Mpris, Status as MprisStatus};

slint::include_modules!();

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
enum CardTarget {
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
    fn cover_uri(&self) -> Option<&str> {
        match self {
            CardTarget::Playlist { cover_uri, .. } => cover_uri.as_deref(),
            CardTarget::Album(a) => a.cover_uri.as_deref(),
            CardTarget::Artist(ar) => ar.cover_uri.as_deref(),
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
struct ArtistViewInfo {
    id: String,
    name: String,
    genres: String,
    stats: String,
    cover_uri: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct CachedView {
    title: String,
    subtitle: String,
    cards: Vec<CardTarget>,
    tracks: Vec<Track>,
    viewed_artist_id: Option<(String, String)>,
    #[serde(default)]
    artist_view: Option<ArtistViewInfo>,
}

#[derive(Clone, Debug)]
struct WaveState {
    seed: String,
    title: String,
    session_id: String,
    batch_id: String,
    tracks: Vec<Track>,
    fetching_more: bool,
    /// Очередь закончилась во время догрузки: продолжить, когда треки придут.
    resume_on_load: bool,
}

#[derive(Default)]
struct State {
    api: Option<Api>,
    uid: u64,
    liked_ids: HashSet<String>,
    /// Карточки, отображаемые над списком треков (плейлисты, альбомы, артисты).
    cards: Vec<CardTarget>,
    /// Если открыта страница артиста — его ID для запуска волны по артисту.
    viewed_artist_id: Option<(String, String)>,
    /// Данные артиста, если сейчас открыта карточка артиста.
    viewed_artist: Option<ArtistViewInfo>,
    /// Треки, которые сейчас показаны в списке.
    list: Vec<Track>,
    /// Очередь воспроизведения.
    queue: Vec<Track>,
    current: Option<usize>,
    duration_secs: f64,
    position_secs: f64,
    /// Активная сессия «Моей волны», если очередь играет из радио.
    wave: Option<WaveState>,
    /// Кэш загруженных вкладок и экранов в памяти.
    views: HashMap<String, CachedView>,
    /// Увеличивается при каждой смене трека или входе/выходе.
    generation: u64,
    /// Увеличивается при каждой смене экрана; поздние ответы старых экранов отбрасываются.
    view_id: u64,
    /// URI обложек, которые уже загружены или загружаются в фоновом режиме.
    covers_loaded: HashSet<String>,
    audio_started: bool,
    last_saved_sec: u64,
    repeat_mode: u8,
    shuffle: bool,
    unshuffled_queue: Option<Vec<Track>>,
    last_unmuted_volume: f32,
    last_seek_time: Option<std::time::Instant>,
    seek_target_secs: f64,
}

const COVER_LRU_CAPACITY: usize = 64;

struct LruImageCache {
    map: HashMap<String, slint::Image>,
    order: VecDeque<String>,
    capacity: usize,
}

impl LruImageCache {
    fn new(capacity: usize) -> Self {
        Self {
            map: HashMap::with_capacity(capacity),
            order: VecDeque::with_capacity(capacity),
            capacity,
        }
    }

    fn get(&mut self, key: &str) -> Option<slint::Image> {
        let img = self.map.get(key)?.clone();
        if let Some(pos) = self.order.iter().position(|k| k == key) {
            self.order.remove(pos);
            self.order.push_back(key.to_string());
        }
        Some(img)
    }

    fn insert(&mut self, key: String, img: slint::Image) {
        if self.map.contains_key(&key) {
            if let Some(pos) = self.order.iter().position(|k| k == &key) {
                self.order.remove(pos);
            }
            self.order.push_back(key.clone());
            self.map.insert(key, img);
            return;
        }
        while self.map.len() >= self.capacity {
            if let Some(oldest) = self.order.pop_front() {
                self.map.remove(&oldest);
            } else {
                break;
            }
        }
        self.order.push_back(key.clone());
        self.map.insert(key, img);
    }
}

thread_local! {
    /// Модель списка треков живёт в UI-потоке; строки обновляются точечно,
    /// чтобы не сбрасывать прокрутку.
    static TRACK_MODEL: RefCell<Option<Rc<VecModel<TrackRow>>>> = const { RefCell::new(None) };
    /// Модель карточек (плейлисты / альбомы / артисты)
    static CARD_MODEL: RefCell<Option<Rc<VecModel<CardItem>>>> = const { RefCell::new(None) };
    /// Ограниченный LRU-кэш декодированных миниатюр обложек в памяти (до 64 шт).
    static COVER_IMAGES: RefCell<LruImageCache> = RefCell::new(LruImageCache::new(COVER_LRU_CAPACITY));
}

fn resolve_cover_image(cover_uri: Option<&str>, size: u32) -> (slint::Image, bool) {
    let Some(uri) = cover_uri else {
        return (slint::Image::default(), false);
    };
    if let Some(img) = COVER_IMAGES.with(|c| c.borrow_mut().get(uri)) {
        return (img, true);
    }
    if let Some(url) = api::cover_url(Some(uri), size) {
        if let Some(bytes) = cache::read_cached_cover(&url) {
            if let Ok(img) = slint::Image::load_from_data(&bytes, None) {
                COVER_IMAGES.with(|c| {
                    c.borrow_mut().insert(uri.to_string(), img.clone());
                });
                return (img, true);
            }
        }
    }
    (slint::Image::default(), false)
}

struct RowMeta {
    track: Track,
    liked: bool,
    cached: bool,
}

impl RowMeta {
    fn from_track(t: &Track, liked_ids: &HashSet<String>) -> Self {
        Self {
            track: t.clone(),
            liked: liked_ids.contains(&t.id),
            cached: cache::is_track_cached(&t.id),
        }
    }

    fn into_row(self) -> TrackRow {
        let (cover, has_cover) = resolve_cover_image(self.track.cover_uri.as_deref(), 100);
        TrackRow {
            title: self.track.title.as_str().into(),
            artists: self.track.artists.as_str().into(),
            album: self.track.album_title.as_str().into(),
            duration: fmt_time(self.track.duration_ms as f64 / 1000.0).into(),
            available: self.track.available,
            liked: self.liked,
            cached: self.cached,
            has_artist: self.track.artist_id.is_some(),
            has_album: self.track.album_id.is_some(),
            cover,
            has_cover,
        }
    }
}

fn sync_card_items(ui: &AppWindow, items: Vec<CardItem>) {
    CARD_MODEL.with(|cell| {
        let mut slot = cell.borrow_mut();
        if let Some(model) = slot.as_ref() && items.len() >= model.row_count() {
            let old_len = model.row_count();
            for (i, item) in items.into_iter().enumerate() {
                if i < old_len {
                    if model.row_data(i).as_ref() != Some(&item) {
                        model.set_row_data(i, item);
                    }
                } else {
                    model.push(item);
                }
            }
            return;
        }
        let model = Rc::new(VecModel::from(items));
        ui.set_cards(ModelRc::from(model.clone()));
        *slot = Some(model);
    });
}

fn reset_card_items(ui: &AppWindow, items: Vec<CardItem>) {
    CARD_MODEL.with(|cell| {
        let model = Rc::new(VecModel::from(items));
        ui.set_cards(ModelRc::from(model.clone()));
        *cell.borrow_mut() = Some(model);
    });
}

/// Обновляет строки списка: точечно, если число строк не изменилось, и добавлением в конец, если выросло.
fn sync_track_rows(ui: &AppWindow, rows: Vec<TrackRow>) {
    TRACK_MODEL.with(|cell| {
        let mut slot = cell.borrow_mut();
        if let Some(model) = slot.as_ref()
            && rows.len() >= model.row_count()
        {
            let old_len = model.row_count();
            for (i, row) in rows.into_iter().enumerate() {
                if i < old_len {
                    if model.row_data(i).as_ref() != Some(&row) {
                        model.set_row_data(i, row);
                    }
                } else {
                    model.push(row);
                }
            }
            return;
        }
        let model = Rc::new(VecModel::from(rows));
        ui.set_tracks(ModelRc::from(model.clone()));
        *slot = Some(model);
    });
}

fn reset_track_rows(ui: &AppWindow, rows: Vec<TrackRow>) {
    TRACK_MODEL.with(|cell| {
        let model = Rc::new(VecModel::from(rows));
        ui.set_tracks(ModelRc::from(model.clone()));
        *cell.borrow_mut() = Some(model);
    });
}

struct App {
    ui: Weak<AppWindow>,
    rt: Handle,
    http: reqwest::Client,
    state: Arc<Mutex<State>>,
    cover_sem: Arc<Semaphore>,
    audio: Audio,
    mpris: Mpris,
    discord: Discord,
}

fn main() -> Result<()> {
    // Немедленно возвращаем освобожденную память операционной системе
    if std::env::var("MIMALLOC_PURGE_DELAY").is_err() {
        unsafe { std::env::set_var("MIMALLOC_PURGE_DELAY", "0"); }
    }

    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()?;
    let rt = runtime.handle().clone();
    let ui = AppWindow::new()?;
    let weak = ui.as_weak();

    let app = Arc::new_cyclic(|me: &std::sync::Weak<App>| {
        let me_audio = me.clone();
        let me_mpris = me.clone();
        App {
            ui: weak.clone(),
            rt: rt.clone(),
            http: api::http_client(),
            state: Arc::new(Mutex::new(State::default())),
            cover_sem: Arc::new(Semaphore::new(8)),
            audio: Audio::spawn(move |event| {
                if let Some(app) = me_audio.upgrade() {
                    app.on_audio(event);
                }
            }),
            mpris: Mpris::spawn(&rt, move |action| {
                if let Some(app) = me_mpris.upgrade() {
                    app.on_mpris(action);
                }
            }),
            discord: Discord::spawn(),
        }
    });

    let settings = config::load_settings();
    let initial_vol = settings.volume;
    ui.set_volume(initial_vol);
    ui.set_repeat_mode(settings.repeat_mode as i32);
    ui.set_shuffle(settings.shuffle);
    app.audio.set_volume(perceptual(initial_vol));
    app.mpris.set_volume(initial_vol);
    {
        let mut st = app.state.lock().unwrap();
        st.repeat_mode = settings.repeat_mode;
        st.shuffle = settings.shuffle;
        st.last_unmuted_volume = if initial_vol > 0.001 { initial_vol } else { 0.7 };
    }
    if let Some(ref url) = settings.user_avatar_url {
        if let Some(bytes) = cache::read_cached_cover(url)
            && let Ok(img) = slint::Image::load_from_data(&bytes, None)
        {
            ui.set_user_avatar(img);
            ui.set_user_has_avatar(true);
        }
    }
    bind_callbacks(&ui, &app);
    spawn_theme_watcher(&ui, &rt);

    if let Some(token) = config::load_token() {
        app.clone().login(token);
    }

    ui.run()?;
    app.persist_session();
    app.audio.stop();
    app.discord.set_stopped();
    // Не ждём зависшие сетевые запросы при выходе.
    runtime.shutdown_background();
    Ok(())
}

fn bind_callbacks(ui: &AppWindow, app: &Arc<App>) {
    let a = app.clone();
    ui.on_login_device(move || a.clone().login_device());
    let a = app.clone();
    ui.on_login_token(move |t| a.clone().login(t.trim().to_string()));
    ui.on_open_url(|url| {
        let _ = std::process::Command::new("xdg-open")
            .arg(url.as_str())
            .spawn();
    });
    ui.on_copy_code(|code| {
        copy_to_clipboard(code.as_str());
    });
    let a = app.clone();
    ui.on_logout(move || a.logout());

    let a = app.clone();
    ui.on_show_home(move || a.clone().load_home());
    let a = app.clone();
    ui.on_start_wave(move || {
        a.clone()
            .open_or_start_wave("user:onyourwave".into(), "Моя волна".into());
    });
    let a = app.clone();
    ui.on_start_artist_wave(move || {
        let artist = a.state.lock().unwrap().viewed_artist_id.clone();
        if let Some((id, name)) = artist {
            a.clone()
                .start_wave(format!("artist:{id}"), format!("Волна: {name}"));
        }
    });
    let a = app.clone();
    ui.on_show_likes(move || a.clone().load_likes());
    let a = app.clone();
    ui.on_show_playlists(move || a.clone().load_playlists());
    let a = app.clone();
    ui.on_show_albums(move || a.clone().load_albums());
    let a = app.clone();
    ui.on_show_artists(move || a.clone().load_artists());
    let a = app.clone();
    ui.on_search(move |q| a.clone().search(q.trim().to_string()));

    let a = app.clone();
    ui.on_open_card(move |i| a.clone().open_card(i as usize));
    let a = app.clone();
    ui.on_open_track_artist(move |i| {
        let id = a
            .state
            .lock()
            .unwrap()
            .list
            .get(i as usize)
            .and_then(|t| t.artist_id.clone());
        if let Some(id) = id {
            a.clone().open_artist(id);
        }
    });
    let a = app.clone();
    ui.on_open_track_album(move |i| {
        let id = a
            .state
            .lock()
            .unwrap()
            .list
            .get(i as usize)
            .and_then(|t| t.album_id.clone());
        if let Some(id) = id {
            a.clone().open_album(id);
        }
    });
    let a = app.clone();
    ui.on_open_now_artist(move || {
        let id = {
            let st = a.state.lock().unwrap();
            st.current
                .and_then(|i| st.queue.get(i))
                .and_then(|t| t.artist_id.clone())
        };
        if let Some(id) = id {
            a.clone().open_artist(id);
        }
    });
    let a = app.clone();
    ui.on_open_now_album(move || {
        let id = {
            let st = a.state.lock().unwrap();
            st.current
                .and_then(|i| st.queue.get(i))
                .and_then(|t| t.album_id.clone())
        };
        if let Some(id) = id {
            a.clone().open_album(id);
        }
    });

    let a = app.clone();
    ui.on_play(move |i| {
        {
            let mut st = a.state.lock().unwrap();
            // Волна остаётся активной, только если кликнули внутри её же списка
            let same_as_queue = st.list.len() == st.queue.len()
                && st.list.iter().zip(&st.queue).all(|(x, y)| x.id == y.id);
            if !same_as_queue {
                st.wave = None;
                st.unshuffled_queue = None;
                st.queue = st.list.clone();
                if st.shuffle && (i as usize + 1) < st.queue.len() {
                    st.unshuffled_queue = Some(st.list.clone());
                    let mut tail = st.queue.split_off(i as usize + 1);
                    shuffle_slice(&mut tail);
                    st.queue.extend(tail);
                }
            }
        }
        a.clone().play_index(i as usize, true);
    });
    let a = app.clone();
    ui.on_toggle_track_like(move |i| a.clone().toggle_like_at(i as usize));
    let a = app.clone();
    ui.on_toggle_now_like(move || a.clone().toggle_now_like());
    let a = app.clone();
    ui.on_dislike_now(move || a.clone().dislike_now());

    let a = app.clone();
    ui.on_toggle(move || a.clone().toggle());
    let a = app.clone();
    ui.on_next(move || a.clone().step(1, true));
    let a = app.clone();
    ui.on_prev(move || a.clone().step(-1, true));
    let a = app.clone();
    ui.on_toggle_repeat(move || a.clone().toggle_repeat());
    let a = app.clone();
    ui.on_toggle_shuffle(move || a.clone().toggle_shuffle());
    let a = app.clone();
    ui.on_toggle_mute(move || a.clone().toggle_mute());
    let a = app.clone();
    let weak = ui.as_weak();
    ui.on_seek(move |fraction| {
        let frac = fraction.clamp(0.0, 1.0);
        let duration = a.state.lock().unwrap().duration_secs;
        if duration > 0.0 {
            let secs = f64::from(frac) * duration;
            a.audio.seek(secs);
            {
                let mut st = a.state.lock().unwrap();
                st.position_secs = secs;
                st.seek_target_secs = secs;
                st.last_seek_time = Some(std::time::Instant::now());
            }
            if let Some(ui) = weak.upgrade() {
                ui.set_progress(frac);
                ui.set_position_text(fmt_time(secs).into());
            }
            a.persist_session();
        }
    });
    let a = app.clone();
    ui.on_set_volume(move |v| {
        a.audio.set_volume(perceptual(v));
        a.mpris.set_volume(v);
        a.save_volume(v);
    });
}

impl App {
    fn api(&self) -> Option<Api> {
        self.state.lock().unwrap().api.clone()
    }

    fn generation(&self) -> u64 {
        self.state.lock().unwrap().generation
    }

    fn ui(&self, f: impl FnOnce(&AppWindow) + Send + 'static) {
        let weak = self.ui.clone();
        let _ = slint::invoke_from_event_loop(move || {
            if let Some(ui) = weak.upgrade() {
                f(&ui);
            }
        });
    }

    fn error(&self, msg: impl Into<String>) {
        let msg = SharedString::from(msg.into());
        self.ui(move |ui| ui.set_status(msg));
    }

    fn login_device(self: Arc<Self>) {
        self.ui(|ui| ui.set_login_busy(true));
        let rt = self.rt.clone();
        rt.spawn(async move {
            let code = match api::request_device_code(&self.http).await {
                Ok(code) => code,
                Err(e) => {
                    self.error(format!("Вход: {e}"));
                    self.ui(|ui| ui.set_login_busy(false));
                    return;
                }
            };
            let (user_code, url) = (code.user_code.clone(), code.verification_url.clone());
            self.ui(move |ui| {
                ui.set_login_code(user_code.into());
                ui.set_login_url(url.into());
            });

            let deadline = tokio::time::Instant::now() + Duration::from_secs(code.expires_in);
            let result = loop {
                tokio::time::sleep(Duration::from_secs(code.interval.max(1))).await;
                if tokio::time::Instant::now() > deadline {
                    break Err(anyhow::anyhow!("время на подтверждение истекло"));
                }
                match api::poll_device_token(&self.http, &code.device_code).await {
                    Ok(Some(token)) => break Ok(token),
                    Ok(None) => continue,
                    Err(e) => break Err(e),
                }
            };
            self.ui(|ui| {
                ui.set_login_code("".into());
                ui.set_login_busy(false);
            });
            match result {
                Ok(token) => self.login(token),
                Err(e) => self.error(format!("Вход: {e}")),
            }
        });
    }

    fn login(self: Arc<Self>, token: String) {
        if token.is_empty() {
            return;
        }
        let rt = self.rt.clone();
        rt.spawn(async move {
            let api = Api::new(self.http.clone(), token.clone());
            match api.account().await {
                Ok(account) => {
                    if let Err(e) = config::save_token(&token) {
                        self.error(format!("Не удалось сохранить токен: {e}"));
                    }
                    {
                        let mut st = self.state.lock().unwrap();
                        st.api = Some(api);
                        st.uid = account.uid;
                    }
                    let name = account.name;
                    let avatar_url = account.avatar_url;
                    self.ui(move |ui| {
                        ui.set_user_name(name.into());
                        ui.set_logged_in(true);
                    });
                    if let Some(ref url) = avatar_url {
                        self.apply_user_avatar(url);
                        let rt = self.rt.clone();
                        let url_clone = url.clone();
                        rt.spawn_blocking(move || {
                            let mut settings = config::load_settings();
                            settings.user_avatar_url = Some(url_clone);
                            let _ = config::save_settings(&settings);
                        });
                    } else {
                        self.ui(|ui| {
                            ui.set_user_has_avatar(false);
                            ui.set_user_avatar(slint::Image::default());
                        });
                        let rt = self.rt.clone();
                        rt.spawn_blocking(move || {
                            let mut settings = config::load_settings();
                            if settings.user_avatar_url.is_some() {
                                settings.user_avatar_url = None;
                                let _ = config::save_settings(&settings);
                            }
                        });
                    }
                    self.clone().load_home();
                    self.clone().prefetch_likes();
                    self.clone().restore_session();
                }
                Err(e) => self.error(format!("Не удалось войти: {e}")),
            }
        });
    }

    fn logout(&self) {
        config::clear_token();
        self.clear_saved_session();
        {
            let mut st = self.state.lock().unwrap();
            *st = State {
                generation: st.generation + 1,
                view_id: st.view_id + 1,
                covers_loaded: std::mem::take(&mut st.covers_loaded),
                ..State::default()
            };
        }
        self.audio.stop();
        self.mpris.set_stopped();
        self.discord.set_stopped();
        self.ui(|ui| {
            ui.set_logged_in(false);
            ui.set_user_name("".into());
            ui.set_user_has_avatar(false);
            ui.set_user_avatar(slint::Image::default());
            ui.set_is_artist_view(false);
            ui.set_artist_has_avatar(false);
            reset_card_items(ui, Vec::new());
            reset_track_rows(ui, Vec::new());
            ui.set_current_index(-1);
            ui.set_has_track(false);
            ui.set_playing(false);
            ui.set_buffering(false);
            ui.set_has_cover(false);
            ui.set_progress(0.0);
        });
        let rt = self.rt.clone();
        rt.spawn_blocking(move || {
            let mut settings = config::load_settings();
            settings.user_avatar_url = None;
            let _ = config::save_settings(&settings);
        });
    }

    /// Переключает экран и возвращает его id для отсева устаревших ответов.
    /// Если `key` есть в кэше (в памяти или на диске), мгновенно отображает кэшированные данные.
    fn begin_cached_view(&self, key: Option<&str>, page: i32, title: String, subtitle: String) -> u64 {
        let is_artist = key.is_some_and(|k| k.starts_with("artist:"));
        let mut cached_tracks = Vec::new();
        let mut cached_cards = Vec::new();
        let (view, has_cache, eff_title, eff_subtitle, cards_for_ui, metas, current_idx, can_wave, artist_info) = {
            let mut st = self.state.lock().unwrap();
            st.view_id += 1;
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
                let metas: Vec<RowMeta> = c
                    .tracks
                    .iter()
                    .map(|t| RowMeta::from_track(t, &st.liked_ids))
                    .collect();
                let can_wave = c.viewed_artist_id.is_some();
                st.cards = c.cards.clone();
                st.list = c.tracks.clone();
                st.viewed_artist_id = c.viewed_artist_id;
                st.viewed_artist = c.artist_view.clone();
                cached_tracks = c.tracks;
                cached_cards = c.cards.clone();
                let cur = current_list_index(&st);
                (view, true, c.title, c.subtitle, c.cards, metas, cur, can_wave, c.artist_view)
            } else {
                st.cards.clear();
                st.list.clear();
                st.viewed_artist_id = None;
                st.viewed_artist = None;
                (view, false, title, subtitle, Vec::new(), Vec::new(), -1, false, None)
            }
        };

        let artist_avatar_to_fetch = if let Some(ref info) = artist_info {
            let cover_uri = info.cover_uri.clone();
            let to_fetch = info.cover_uri.clone();
            let name = info.name.clone();
            let genres = info.genres.clone();
            let stats = info.stats.clone();
            self.ui(move |ui| {
                let (avatar, has_avatar) = resolve_cover_image(cover_uri.as_deref(), 300);
                ui.set_is_artist_view(true);
                ui.set_artist_name(name.into());
                ui.set_artist_genres(genres.into());
                ui.set_artist_stats(stats.into());
                ui.set_artist_avatar(avatar);
                ui.set_artist_has_avatar(has_avatar);
                ui.set_artist_tab(0);
            });
            to_fetch
        } else {
            self.ui(move |ui| {
                ui.set_is_artist_view(is_artist);
                ui.set_artist_has_avatar(false);
            });
            None
        };

        self.ui(move |ui| {
            ui.set_page(page);
            ui.set_list_title(eff_title.into());
            ui.set_list_subtitle(eff_subtitle.into());
            ui.set_can_start_artist_wave(can_wave);
            ui.set_list_loading(!has_cache);
            let card_items: Vec<CardItem> = cards_for_ui.iter().map(card_item).collect();
            reset_card_items(ui, card_items);
            let rows = metas.into_iter().map(RowMeta::into_row).collect();
            reset_track_rows(ui, rows);
            ui.set_current_index(current_idx);
        });
        if !cached_tracks.is_empty() {
            self.load_covers(&cached_tracks);
        }
        if !cached_cards.is_empty() {
            self.load_card_covers(&cached_cards);
        }
        if let Some(uri) = artist_avatar_to_fetch {
            self.load_artist_avatar(uri);
        }
        view
    }

    /// Сохраняет данные в кэш и отображает их, если пользователь ещё не ушёл с этого экрана.
    fn apply_cached_view(
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
                title: title
                    .clone()
                    .or_else(|| prev.map(|p| p.title.clone()))
                    .unwrap_or_default(),
                subtitle: subtitle
                    .clone()
                    .or_else(|| prev.map(|p| p.subtitle.clone()))
                    .unwrap_or_default(),
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
        let (metas, current_idx) = {
            let mut st = self.state.lock().unwrap();
            if st.view_id != view {
                return false;
            }
            st.cards = cards.clone();
            st.viewed_artist_id = viewed_artist_id;
            st.viewed_artist = artist_view.clone();
            let metas: Vec<RowMeta> = tracks
                .iter()
                .map(|t| RowMeta::from_track(t, &st.liked_ids))
                .collect();
            st.list = tracks.clone();
            (metas, current_list_index(&st))
        };

        let artist_avatar_to_fetch = if let Some(ref info) = artist_view {
            let cover_uri = info.cover_uri.clone();
            let to_fetch = info.cover_uri.clone();
            let name = info.name.clone();
            let genres = info.genres.clone();
            let stats = info.stats.clone();
            self.ui(move |ui| {
                let (avatar, has_avatar) = resolve_cover_image(cover_uri.as_deref(), 300);
                ui.set_is_artist_view(true);
                ui.set_artist_name(name.into());
                ui.set_artist_genres(genres.into());
                ui.set_artist_stats(stats.into());
                ui.set_artist_avatar(avatar);
                ui.set_artist_has_avatar(has_avatar);
                ui.set_artist_tab(0);
            });
            to_fetch
        } else {
            self.ui(|ui| {
                ui.set_is_artist_view(false);
                ui.set_artist_has_avatar(false);
            });
            None
        };

        let cards_for_ui = cards.clone();
        self.ui(move |ui| {
            if let Some(t) = title {
                ui.set_list_title(t.into());
            }
            if let Some(s) = subtitle {
                ui.set_list_subtitle(s.into());
            }
            ui.set_can_start_artist_wave(can_wave);
            let card_items: Vec<CardItem> = cards_for_ui.iter().map(card_item).collect();
            let rows = metas.into_iter().map(RowMeta::into_row).collect();
            sync_card_items(ui, card_items);
            sync_track_rows(ui, rows);
            ui.set_current_index(current_idx);
            ui.set_list_loading(false);
        });
        self.load_covers(&tracks);
        self.load_card_covers(&cards);
        if let Some(uri) = artist_avatar_to_fetch {
            self.load_artist_avatar(uri);
        }
        true
    }

    fn view_failed(&self, view: u64, what: &str, e: anyhow::Error) {
        let is_current = self.state.lock().unwrap().view_id == view;
        if is_current {
            self.ui(|ui| ui.set_list_loading(false));
            self.error(format!("{what}: {e:#}"));
        }
    }

    /// Обновляет строки на месте (лайки, отметки кэша, догруженные треки волны).
    fn refresh_rows(&self) {
        let (metas, now_liked, current_idx) = {
            let st = self.state.lock().unwrap();
            let metas: Vec<RowMeta> = st
                .list
                .iter()
                .map(|t| RowMeta::from_track(t, &st.liked_ids))
                .collect();
            let now_liked = current_track(&st).is_some_and(|t| st.liked_ids.contains(&t.id));
            (metas, now_liked, current_list_index(&st))
        };
        self.ui(move |ui| {
            let rows = metas.into_iter().map(RowMeta::into_row).collect();
            sync_track_rows(ui, rows);
            ui.set_now_liked(now_liked);
            ui.set_current_index(current_idx);
        });
    }

    /// Асинхронно подгружает миниатюры обложек для списка треков и точечно обновляет строки.
    fn load_covers(&self, tracks: &[Track]) {
        let mut to_fetch = Vec::new();
        {
            let mut st = self.state.lock().unwrap();
            for t in tracks {
                if let (Some(uri), Some(url)) = (t.cover_uri.as_ref(), t.cover_url(100))
                    && st.covers_loaded.insert(uri.clone())
                {
                    to_fetch.push((uri.clone(), url));
                }
            }
        }
        for (uri, url) in to_fetch {
            let http = self.http.clone();
            let sem = self.cover_sem.clone();
            let state = self.state.clone();
            let weak = self.ui.clone();
            self.rt.spawn(async move {
                let _permit = sem.acquire().await;
                let Ok(bytes) = cache::fetch_cover(&http, &url).await else {
                    state.lock().unwrap().covers_loaded.remove(&uri);
                    return;
                };
                let _ = slint::invoke_from_event_loop(move || {
                    let Ok(image) = slint::Image::load_from_data(&bytes, None) else {
                        state.lock().unwrap().covers_loaded.remove(&uri);
                        return;
                    };
                    COVER_IMAGES.with(|c| {
                        c.borrow_mut().insert(uri.clone(), image.clone());
                    });
                    if weak.upgrade().is_none() {
                        return;
                    }
                    let matching_indices: Vec<usize> = state
                        .lock()
                        .unwrap()
                        .list
                        .iter()
                        .enumerate()
                        .filter_map(|(i, t)| (t.cover_uri.as_deref() == Some(uri.as_str())).then_some(i))
                        .collect();
                    TRACK_MODEL.with(|cell| {
                        let Some(model) = cell.borrow().as_ref().cloned() else { return };
                        for i in matching_indices {
                            if let Some(mut row) = model.row_data(i) {
                                row.cover = image.clone();
                                row.has_cover = true;
                                model.set_row_data(i, row);
                            }
                        }
                    });
                });
            });
        }
    }

    /// Асинхронно подгружает миниатюры обложек для карточек и обновляет их в списке.
    fn load_card_covers(&self, cards: &[CardTarget]) {
        let mut to_fetch = Vec::new();
        {
            let mut st = self.state.lock().unwrap();
            for c in cards {
                if let Some(uri) = c.cover_uri() {
                    if let Some(url) = api::cover_url(Some(uri), 100) {
                        if st.covers_loaded.insert(uri.to_string()) {
                            to_fetch.push((uri.to_string(), url));
                        }
                    }
                }
            }
        }
        for (uri, url) in to_fetch {
            let http = self.http.clone();
            let sem = self.cover_sem.clone();
            let state = self.state.clone();
            let weak = self.ui.clone();
            self.rt.spawn(async move {
                let _permit = sem.acquire().await;
                let Ok(bytes) = cache::fetch_cover(&http, &url).await else {
                    state.lock().unwrap().covers_loaded.remove(&uri);
                    return;
                };
                let _ = slint::invoke_from_event_loop(move || {
                    let Ok(image) = slint::Image::load_from_data(&bytes, None) else {
                        state.lock().unwrap().covers_loaded.remove(&uri);
                        return;
                    };
                    COVER_IMAGES.with(|c| {
                        c.borrow_mut().insert(uri.clone(), image.clone());
                    });
                    if weak.upgrade().is_none() {
                        return;
                    }
                    let matching_indices: Vec<usize> = state
                        .lock()
                        .unwrap()
                        .cards
                        .iter()
                        .enumerate()
                        .filter_map(|(i, c)| (c.cover_uri() == Some(&uri)).then_some(i))
                        .collect();
                    CARD_MODEL.with(|cell| {
                        let Some(model) = cell.borrow().as_ref().cloned() else { return };
                        for i in matching_indices {
                            if let Some(mut item) = model.row_data(i) {
                                item.cover = image.clone();
                                item.has_cover = true;
                                model.set_row_data(i, item);
                            }
                        }
                    });
                });
            });
        }
    }

    /// Подгружает крупную аватарку артиста для шапки страницы артиста.
    fn load_artist_avatar(&self, uri: String) {
        let Some(url) = api::cover_url(Some(&uri), 300) else { return };
        let http = self.http.clone();
        let sem = self.cover_sem.clone();
        let weak = self.ui.clone();
        self.rt.spawn(async move {
            let _permit = sem.acquire().await;
            let Ok(bytes) = cache::fetch_cover(&http, &url).await else { return };
            let _ = slint::invoke_from_event_loop(move || {
                let Ok(image) = slint::Image::load_from_data(&bytes, None) else { return };
                COVER_IMAGES.with(|c| {
                    c.borrow_mut().insert(uri, image.clone());
                });
                if let Some(ui) = weak.upgrade() {
                    ui.set_artist_avatar(image);
                    ui.set_artist_has_avatar(true);
                }
            });
        });
    }

    /// Отображает аватарку пользователя (из локального кэша или загружая по сети).
    fn apply_user_avatar(&self, url: &str) {
        if let Some(bytes) = cache::read_cached_cover(url) {
            let weak = self.ui.clone();
            let _ = slint::invoke_from_event_loop(move || {
                if let Some(ui) = weak.upgrade()
                    && let Ok(img) = slint::Image::load_from_data(&bytes, None)
                {
                    ui.set_user_avatar(img);
                    ui.set_user_has_avatar(true);
                }
            });
            return;
        }
        self.load_user_avatar(url.to_string());
    }

    fn load_user_avatar(&self, url: String) {
        let http = self.http.clone();
        let weak = self.ui.clone();
        self.rt.spawn(async move {
            let Ok(bytes) = cache::fetch_cover(&http, &url).await else { return };
            let _ = slint::invoke_from_event_loop(move || {
                let Ok(image) = slint::Image::load_from_data(&bytes, None) else { return };
                if let Some(ui) = weak.upgrade() {
                    ui.set_user_avatar(image);
                    ui.set_user_has_avatar(true);
                }
            });
        });
    }

    fn prefetch_likes(self: Arc<Self>) {
        let Some(api) = self.api() else { return };
        let uid = self.state.lock().unwrap().uid;
        let rt = self.rt.clone();
        rt.spawn(async move {
            if let Ok(entries) = api.liked_track_entries(uid).await {
                let set: HashSet<String> = entries.into_iter().map(|(id, _)| id).collect();
                self.state.lock().unwrap().liked_ids = set;
                self.refresh_rows();
            }
        });
    }

    fn load_home(self: Arc<Self>) {
        let Some(api) = self.api() else { return };
        let uid = self.state.lock().unwrap().uid;
        let view = self.begin_cached_view(
            Some("home"),
            0,
            "Главная".into(),
            "Ваша музыка и рекомендации".into(),
        );
        let rt = self.rt.clone();
        rt.spawn(async move {
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

            self.apply_cached_view(
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

    fn load_likes(self: Arc<Self>) {
        let Some(api) = self.api() else { return };
        let uid = self.state.lock().unwrap().uid;
        let view = self.begin_cached_view(Some("likes"), 2, "Мне нравится".into(), "".into());
        let rt = self.rt.clone();
        rt.spawn(async move {
            match api.liked_tracks(uid).await {
                Ok((liked_set, tracks)) => {
                    self.state.lock().unwrap().liked_ids = liked_set;
                    self.apply_cached_view(
                        view,
                        Some("likes"),
                        Some("Мне нравится".into()),
                        Some("".into()),
                        Vec::new(),
                        tracks,
                        None,
                        None,
                    );
                    // Сердечко текущего трека могло измениться
                    self.refresh_rows();
                }
                Err(e) => self.view_failed(view, "Не удалось загрузить лайки", e),
            }
        });
    }

    /// Открывает уже активную сессию волны (без сброса списка и трека) или создаёт новую.
    fn open_or_start_wave(self: Arc<Self>, seed: String, title: String) {
        let existing = {
            let mut st = self.state.lock().unwrap();
            if let Some(w) = st.wave.as_ref().filter(|w| w.seed == seed && !w.tracks.is_empty()) {
                let tracks = w.tracks.clone();
                let w_title = w.title.clone();
                st.view_id += 1;
                let view = st.view_id;
                st.cards.clear();
                st.viewed_artist_id = None;
                st.viewed_artist = None;
                let metas: Vec<RowMeta> = tracks
                    .iter()
                    .map(|t| RowMeta::from_track(t, &st.liked_ids))
                    .collect();
                st.list = tracks.clone();
                let cur = current_list_index(&st);
                Some((view, w_title, metas, cur, tracks))
            } else {
                None
            }
        };

        if let Some((_view, w_title, metas, cur, tracks)) = existing {
            self.ui(move |ui| {
                ui.set_page(1);
                ui.set_is_artist_view(false);
                ui.set_artist_has_avatar(false);
                ui.set_list_title(w_title.into());
                ui.set_list_subtitle("Персональный поток рекомендаций".into());
                ui.set_can_start_artist_wave(false);
                ui.set_list_loading(false);
                reset_card_items(ui, Vec::new());
                let rows = metas.into_iter().map(RowMeta::into_row).collect();
                reset_track_rows(ui, rows);
                ui.set_current_index(cur);
            });
            self.load_covers(&tracks);
            return;
        }

        self.start_wave(seed, title);
    }

    fn start_wave(self: Arc<Self>, seed: String, title: String) {
        let Some(api) = self.api() else { return };
        let cache_key = format!("wave:{seed}");
        let view = self.begin_cached_view(
            Some(&cache_key),
            1,
            title.clone(),
            "Персональный поток рекомендаций".into(),
        );
        let rt = self.rt.clone();
        rt.spawn(async move {
            let session = match api.rotor_session_new(&[seed.as_str()]).await {
                Ok(s) => s,
                Err(e) => return self.view_failed(view, "Моя волна", e),
            };
            if session.tracks.is_empty() {
                return self.view_failed(view, "Моя волна", anyhow::anyhow!("волна не вернула треков"));
            }
            {
                let mut st = self.state.lock().unwrap();
                // Пользователь мог уйти на другой экран, пока создавалась сессия
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
                // Новая очередь: прошлый трек не относится к этой сессии
                st.current = None;
            }
            let (sid, bid) = (session.session_id.clone(), session.batch_id.clone());
            let api_fb = api.clone();
            tokio::spawn(async move {
                api_fb.rotor_feedback(&sid, &bid, "radioStarted", None, None).await;
            });
            self.apply_cached_view(
                view,
                Some(&cache_key),
                Some(title),
                Some("Персональный поток рекомендаций".into()),
                Vec::new(),
                session.tracks,
                None,
                None,
            );
            self.play_index(0, false);
        });
    }

    fn load_playlists(self: Arc<Self>) {
        let Some(api) = self.api() else { return };
        let uid = self.state.lock().unwrap().uid;
        let view = self.begin_cached_view(
            Some("playlists"),
            3,
            "Плейлисты".into(),
            "Ваши и понравившиеся плейлисты".into(),
        );
        let rt = self.rt.clone();
        rt.spawn(async move {
            match api.user_playlists(uid).await {
                Ok(list) => {
                    let cards = list.into_iter().map(playlist_target).collect();
                    self.apply_cached_view(
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
                Err(e) => self.view_failed(view, "Плейлисты", e),
            }
        });
    }

    fn load_albums(self: Arc<Self>) {
        let Some(api) = self.api() else { return };
        let uid = self.state.lock().unwrap().uid;
        let view = self.begin_cached_view(
            Some("albums"),
            4,
            "Альбомы".into(),
            "Понравившиеся альбомы".into(),
        );
        let rt = self.rt.clone();
        rt.spawn(async move {
            match api.liked_albums(uid).await {
                Ok(list) => {
                    let cards = list.into_iter().map(CardTarget::Album).collect();
                    self.apply_cached_view(
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
                Err(e) => self.view_failed(view, "Альбомы", e),
            }
        });
    }

    fn load_artists(self: Arc<Self>) {
        let Some(api) = self.api() else { return };
        let uid = self.state.lock().unwrap().uid;
        let view = self.begin_cached_view(
            Some("artists"),
            5,
            "Артисты".into(),
            "Любимые исполнители".into(),
        );
        let rt = self.rt.clone();
        rt.spawn(async move {
            match api.liked_artists(uid).await {
                Ok(list) => {
                    let cards = list.into_iter().map(CardTarget::Artist).collect();
                    self.apply_cached_view(
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
                Err(e) => self.view_failed(view, "Артисты", e),
            }
        });
    }

    fn search(self: Arc<Self>, query: String) {
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
        let rt = self.rt.clone();
        rt.spawn(async move {
            match api.search_all(&query).await {
                Ok(res) => {
                    let mut cards = Vec::new();
                    cards.extend(res.artists.into_iter().take(4).map(CardTarget::Artist));
                    cards.extend(res.albums.into_iter().take(4).map(CardTarget::Album));
                    cards.extend(res.playlists.into_iter().take(3).map(playlist_target));
                    self.apply_cached_view(
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
                Err(e) => self.view_failed(view, "Поиск", e),
            }
        });
    }

    fn open_card(self: Arc<Self>, index: usize) {
        let target = self.state.lock().unwrap().cards.get(index).cloned();
        let Some(target) = target else { return };
        match target {
            CardTarget::Playlist { uid, kind, title, .. } => self.open_playlist(uid, kind, title),
            CardTarget::Album(album) => self.open_album(album.id),
            CardTarget::Artist(artist) => self.open_artist(artist.id),
        }
    }

    fn open_playlist(self: Arc<Self>, owner_uid: u64, kind: u64, title: String) {
        let Some(api) = self.api() else { return };
        let key = format!("playlist:{owner_uid}:{kind}");
        let view = self.begin_cached_view(Some(&key), 6, title.clone(), "Плейлист".into());
        let rt = self.rt.clone();
        rt.spawn(async move {
            match api.playlist_tracks(owner_uid, kind).await {
                Ok(tracks) => {
                    self.apply_cached_view(
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
                Err(e) => self.view_failed(view, "Плейлист", e),
            }
        });
    }

    fn open_album(self: Arc<Self>, album_id: String) {
        let Some(api) = self.api() else { return };
        let key = format!("album:{album_id}");
        let view = self.begin_cached_view(Some(&key), 6, "Альбом…".into(), "".into());
        let rt = self.rt.clone();
        rt.spawn(async move {
            match api.album_with_tracks(&album_id).await {
                Ok((album, tracks)) => {
                    let sub = match album.year {
                        Some(y) if !album.artists.is_empty() => format!("{} • {y}", album.artists),
                        Some(y) => y.to_string(),
                        None => album.artists.clone(),
                    };
                    let title = album.title.clone();
                    self.apply_cached_view(
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
                Err(e) => self.view_failed(view, "Альбом", e),
            }
        });
    }

    fn open_artist(self: Arc<Self>, artist_id: String) {
        let Some(api) = self.api() else { return };
        let key = format!("artist:{artist_id}");
        let view = self.begin_cached_view(Some(&key), 6, "Артист…".into(), "".into());
        let rt = self.rt.clone();
        rt.spawn(async move {
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
                    self.apply_cached_view(
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
                Err(e) => self.view_failed(view, "Артист", e),
            }
        });
    }

    fn toggle_like_at(self: Arc<Self>, index: usize) {
        let track = self.state.lock().unwrap().list.get(index).cloned();
        if let Some(t) = track {
            self.toggle_like_track(t);
        }
    }

    fn toggle_now_like(self: Arc<Self>) {
        let track = current_track(&self.state.lock().unwrap()).cloned();
        if let Some(t) = track {
            self.toggle_like_track(t);
        }
    }

    fn update_likes_cache(&self, track: &Track, add: bool) {
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

    fn toggle_like_track(self: Arc<Self>, track: Track) {
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
        let rt = self.rt.clone();
        rt.spawn(async move {
            let res = if add {
                api.like_track(uid, &track.id).await
            } else {
                api.unlike_track(uid, &track.id).await
            };
            if let Err(e) = res {
                // Откатываем оптимистичное изменение
                {
                    let mut st = self.state.lock().unwrap();
                    if add {
                        st.liked_ids.remove(&track.id);
                    } else {
                        st.liked_ids.insert(track.id.clone());
                    }
                }
                self.update_likes_cache(&track, !add);
                self.refresh_rows();
                self.error(format!("Лайк: {e:#}"));
                return;
            }
            if let Some(w) = wave {
                let ev = if add { "like" } else { "unlike" };
                api.rotor_feedback(&w.session_id, &w.batch_id, ev, Some(&track.composite_id()), None)
                    .await;
            }
        });
    }

    fn dislike_now(self: Arc<Self>) {
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
        self.rt.spawn(async move {
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
        // Сам переход отправит в волну `skip`
        self.step(1, true);
    }

    /// Переход по очереди. Недоступные треки пропускаются.
    fn step(self: Arc<Self>, delta: isize, manual_skip: bool) {
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

    /// Очередь доиграла до конца.
    fn finish_queue(&self) {
        let waiting_for_wave = {
            let mut st = self.state.lock().unwrap();
            // Волна ещё догружает треки: on_audio продолжит, когда они придут
            let waiting = st.wave.as_ref().is_some_and(|w| w.fetching_more);
            if waiting && let Some(w) = &mut st.wave {
                w.resume_on_load = true;
            }
            waiting
        };
        if waiting_for_wave {
            self.ui(|ui| ui.set_buffering(true));
            return;
        }
        self.mpris.set_status(MprisStatus::Stopped, 0.0);
        self.discord.set_stopped();
        self.ui(|ui| {
            ui.set_playing(false);
            ui.set_progress(0.0);
            ui.set_position_text("0:00".into());
        });
    }

    fn play_index(self: Arc<Self>, index: usize, manual_skip: bool) {
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
            self.rt.spawn(async move {
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

        let (title, artists) = (track.title.clone(), track.artists.clone());
        let duration = fmt_time(track.duration_ms as f64 / 1000.0);
        let has_artist = track.artist_id.is_some();
        let has_album = track.album_id.is_some();
        self.ui(move |ui| {
            ui.set_current_index(current_idx);
            ui.set_has_track(true);
            ui.set_buffering(true);
            ui.set_playing(false);
            ui.set_now_liked(liked);
            ui.set_now_has_artist(has_artist);
            ui.set_now_has_album(has_album);
            ui.set_now_title(title.into());
            ui.set_now_artists(artists.into());
            ui.set_duration_text(duration.into());
            ui.set_position_text("0:00".into());
            ui.set_progress(0.0);
            ui.set_has_cover(false);
        });

        self.mpris.set_track(
            MprisMeta {
                id: track.id.clone(),
                title: track.title.clone(),
                artists: track.artists.clone(),
                duration_us: (track.duration_ms as i64) * 1000,
                cover_url: track.cover_url(400),
            },
            MprisStatus::Paused,
        );
        self.discord.set_track(&track, MprisStatus::Paused);

        if let Some(url) = track.cover_url(200) {
            let this = self.clone();
            self.rt.spawn(async move {
                let Ok(bytes) = cache::fetch_cover(&this.http, &url).await else { return };
                let weak = this.ui.clone();
                let this2 = this.clone();
                let _ = slint::invoke_from_event_loop(move || {
                    // Обложка могла опоздать: трек уже сменили
                    if this2.generation() != generation {
                        return;
                    }
                    if let Some(ui) = weak.upgrade()
                        && let Ok(image) = slint::Image::load_from_data(&bytes, None)
                    {
                        ui.set_now_cover(image);
                        ui.set_has_cover(true);
                    }
                });
            });
        }

        if let Some((file, len)) = cache::open_cached_track(&track.id) {
            self.audio.load(generation, SourceData::Cached { file, len });
            if let Some(next_id) = next_track_id {
                self.prefetch(next_id);
            }
            return;
        }

        // Старый трек не должен доигрывать, пока грузится новый
        self.audio.stop();

        let this = self.clone();
        self.rt.spawn(async move {
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
                    this.ui(|ui| ui.set_buffering(false));
                    this.error(format!("«{}»: {e:#}", track.title));
                }
            }
        });
    }

    /// Фоновая предзагрузка следующего трека в дисковый кэш.
    fn prefetch(self: Arc<Self>, track_id: String) {
        if cache::is_track_cached(&track_id) {
            return;
        }
        let Some(api) = self.api() else { return };
        let rt = self.rt.clone();
        rt.spawn(async move {
            let Ok(url) = api.track_direct_url(&track_id).await else { return };
            let Ok(resp) = api.http().get(url).send().await else { return };
            let Ok(resp) = resp.error_for_status() else { return };
            let Ok(bytes) = resp.bytes().await else { return };
            let _ = tokio::task::spawn_blocking(move || cache::save_track(&track_id, &bytes)).await;
            self.refresh_rows();
        });
    }

    /// Если в «Моей волне» осталось меньше 3 треков до конца очереди, подгружаем ещё партию.
    fn maybe_extend_wave(self: Arc<Self>, current_index: usize) {
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

        let rt = self.rt.clone();
        rt.spawn(async move {
            let res = api.rotor_session_tracks(&session_id, &queue_ids).await;
            let resume;
            let mut new_for_view = Vec::new();
            let mut wave_cache_update = None;
            {
                let mut st = self.state.lock().unwrap();
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
                    // Волна иногда повторяет треки, которые уже есть в очереди
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
                        new_for_view = fresh.clone();
                    }
                    queue.extend(fresh);
                }
            }
            if let Some((key, cached)) = wave_cache_update {
                cache::save_view(&key, &cached);
            }
            if !new_for_view.is_empty() {
                self.refresh_rows();
                self.load_covers(&new_for_view);
            }
            if resume {
                self.step(1, false);
            }
        });
    }

    fn on_audio(self: Arc<Self>, event: Event) {
        let current = self.generation();
        match event {
            Event::Started(g) if g == current => {
                self.mpris.set_status(MprisStatus::Playing, 0.0);
                self.discord.set_status(MprisStatus::Playing, 0.0);
                self.ui(|ui| {
                    ui.set_buffering(false);
                    ui.set_playing(true);
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
                let text = fmt_time(secs);
                self.ui(move |ui| {
                    ui.set_playing(!paused);
                    ui.set_progress(progress);
                    ui.set_position_text(text.into());
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
                self.ui(|ui| ui.set_playing(false));
                self.step(1, false);
            }
            // generation 0 — ошибка открытия аудиоустройства
            Event::Error(g, msg) if g == current || g == 0 => {
                self.mpris.set_status(MprisStatus::Stopped, 0.0);
                self.discord.set_stopped();
                self.ui(|ui| {
                    ui.set_buffering(false);
                    ui.set_playing(false);
                });
                self.error(msg);
            }
            // Событие от уже сменённого трека
            _ => {}
        }
    }

    fn toggle(self: Arc<Self>) {
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

    fn toggle_repeat(self: Arc<Self>) {
        let mode = {
            let mut st = self.state.lock().unwrap();
            st.repeat_mode = (st.repeat_mode + 1) % 3;
            st.repeat_mode
        };
        self.ui(move |ui| ui.set_repeat_mode(mode as i32));
        let rt = self.rt.clone();
        rt.spawn_blocking(move || {
            let mut settings = config::load_settings();
            settings.repeat_mode = mode;
            let _ = config::save_settings(&settings);
        });
    }

    fn toggle_shuffle(self: Arc<Self>) {
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
        self.ui(move |ui| ui.set_shuffle(shuffle_on));
        let rt = self.rt.clone();
        rt.spawn_blocking(move || {
            let mut settings = config::load_settings();
            settings.shuffle = shuffle_on;
            let _ = config::save_settings(&settings);
        });
    }

    fn toggle_mute(self: Arc<Self>) {
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
            self.ui(move |ui| ui.set_volume(new_vol));
        }
    }

    fn save_volume(&self, vol: f32) {
        let rt = self.rt.clone();
        rt.spawn_blocking(move || {
            let mut settings = config::load_settings();
            settings.volume = vol;
            let _ = config::save_settings(&settings);
        });
    }

    fn persist_session(&self) {
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

        let rt = self.rt.clone();
        rt.spawn_blocking(move || {
            let mut settings = config::load_settings();
            settings.session = Some(session);
            let _ = config::save_settings(&settings);
        });
    }

    fn clear_saved_session(&self) {
        let rt = self.rt.clone();
        rt.spawn_blocking(move || {
            let mut settings = config::load_settings();
            settings.session = None;
            let _ = config::save_settings(&settings);
        });
    }

    fn restore_session(self: Arc<Self>) {
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

        let title = track.title.clone();
        let artists = track.artists.clone();
        let has_album = track.album_id.is_some();
        let has_artist = track.artist_id.is_some();
        let cover_uri = track.cover_uri.clone();

        self.ui(move |ui| {
            ui.set_has_track(true);
            ui.set_playing(false);
            ui.set_buffering(false);
            ui.set_now_title(title.into());
            ui.set_now_artists(artists.into());
            ui.set_now_has_album(has_album);
            ui.set_now_has_artist(has_artist);
            ui.set_now_liked(liked);
            ui.set_duration_text(dur_text.into());
            ui.set_position_text(pos_text.into());
            ui.set_progress(progress);
            let (img, has_img) = resolve_cover_image(cover_uri.as_deref(), 200);
            ui.set_now_cover(img);
            ui.set_has_cover(has_img);
        });

        if let Some(url) = track.cover_url(200) {
            let this = self.clone();
            let generation = self.generation();
            self.rt.spawn(async move {
                let Ok(bytes) = cache::fetch_cover(&this.http, &url).await else { return };
                let weak = this.ui.clone();
                let this2 = this.clone();
                let _ = slint::invoke_from_event_loop(move || {
                    if this2.generation() != generation {
                        return;
                    }
                    if let Some(ui) = weak.upgrade()
                        && let Ok(image) = slint::Image::load_from_data(&bytes, None)
                    {
                        ui.set_now_cover(image);
                        ui.set_has_cover(true);
                    }
                });
            });
        }

        self.mpris.set_track(
            MprisMeta {
                id: track.id.clone(),
                title: track.title.clone(),
                artists: track.artists.clone(),
                duration_us: (track.duration_ms as i64) * 1000,
                cover_url: track.cover_url(400),
            },
            MprisStatus::Paused,
        );
        self.discord.set_track(&track, MprisStatus::Paused);
    }

    fn on_mpris(self: Arc<Self>, action: MprisAction) {
        match action {
            MprisAction::Play => self.clone().toggle(),
            MprisAction::Pause => self.audio.pause(),
            MprisAction::Toggle => self.clone().toggle(),
            MprisAction::Stop => {
                self.audio.stop();
                self.ui(|ui| {
                    ui.set_playing(false);
                    ui.set_buffering(false);
                });
                self.mpris.set_status(MprisStatus::Stopped, 0.0);
                self.discord.set_stopped();
            }
            MprisAction::Next => self.step(1, true),
            MprisAction::Prev => self.step(-1, true),
            MprisAction::SeekRelative(delta) => self.audio.seek_relative(delta),
            MprisAction::SeekAbsolute(secs) => self.audio.seek(secs),
            MprisAction::SetVolume(v) => {
                self.audio.set_volume(perceptual(v));
                self.save_volume(v);
                self.ui(move |ui| ui.set_volume(v));
            }
            MprisAction::Quit => {
                let _ = slint::quit_event_loop();
            }
        }
    }
}

fn current_track(st: &State) -> Option<&Track> {
    st.current.and_then(|i| st.queue.get(i))
}

/// Индекс играющего трека в видимом списке, если он там есть.
fn current_list_index(st: &State) -> i32 {
    current_track(st)
        .and_then(|cur| st.list.iter().position(|t| t.id == cur.id))
        .map_or(-1, |i| i as i32)
}

fn playlist_target(p: api::PlaylistCard) -> CardTarget {
    CardTarget::Playlist {
        uid: p.uid,
        kind: p.kind,
        title: format!("{} ({})", p.title, p.subtitle),
        cover_uri: p.cover_uri,
    }
}

fn card_item(t: &CardTarget) -> CardItem {
    let (cover, has_cover) = resolve_cover_image(t.cover_uri(), 100);
    match t {
        CardTarget::Playlist { title, .. } => CardItem {
            title: title.as_str().into(),
            subtitle: "Плейлист".into(),
            kind: "playlist".into(),
            cover,
            has_cover,
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
            CardItem {
                title: a.title.as_str().into(),
                subtitle: parts.join(" • ").into(),
                kind: "album".into(),
                cover,
                has_cover,
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
            CardItem {
                title: ar.name.as_str().into(),
                subtitle: sub.into(),
                kind: "artist".into(),
                cover,
                has_cover,
            }
        }
    }
}

fn fmt_time(secs: f64) -> String {
    let s = secs.max(0.0) as u64;
    if s >= 3600 {
        format!("{}:{:02}:{:02}", s / 3600, s / 60 % 60, s % 60)
    } else {
        format!("{}:{:02}", s / 60, s % 60)
    }
}

fn perceptual(v: f32) -> f32 {
    v.clamp(0.0, 1.0).powi(2)
}

fn copy_to_clipboard(text: &str) {
    use std::io::Write;
    use std::process::{Command, Stdio};

    let candidates: &[(&str, &[&str])] = &[
        ("wl-copy", &[]),
        ("xclip", &["-selection", "clipboard"]),
        ("xsel", &["--clipboard", "--input"]),
    ];

    for (bin, args) in candidates {
        if let Ok(mut child) = Command::new(bin)
            .args(*args)
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
        {
            if let Some(mut stdin) = child.stdin.take() {
                let _ = stdin.write_all(text.as_bytes());
            }
            return;
        }
    }
}

fn apply_palette(ui: &AppWindow, p: config::QsPalette) {
    let th = ui.global::<Theme>();
    th.set_bg(p.bg);
    th.set_surface_low(p.surface_low);
    th.set_surface(p.surface);
    th.set_surface_hi(p.surface_hi);
    th.set_surface_highest(p.surface_highest);
    th.set_text(p.text);
    th.set_muted(p.muted);
    th.set_outline(p.outline);
    th.set_accent(p.accent);
    th.set_on_accent(p.on_accent);
    th.set_secondary_container(p.secondary_container);
    th.set_on_secondary_container(p.on_secondary_container);
    th.set_danger(p.danger);
    th.set_on_danger(p.on_danger);
}

fn spawn_theme_watcher(ui: &AppWindow, rt: &Handle) {
    let mut last_mtime = None;
    if let Some((palette, mtime)) = config::load_quickshell_palette() {
        apply_palette(ui, palette);
        last_mtime = mtime;
    }
    let Some(path) = config::quickshell_colors_path() else {
        return;
    };
    let weak = ui.as_weak();
    rt.spawn(async move {
        loop {
            tokio::time::sleep(Duration::from_secs(2)).await;
            let mtime = std::fs::metadata(&path).ok().and_then(|m| m.modified().ok());
            if mtime.is_some() && mtime != last_mtime
                && let Some((palette, new_mtime)) = config::load_quickshell_palette()
            {
                last_mtime = new_mtime;
                let weak_ui = weak.clone();
                let _ = slint::invoke_from_event_loop(move || {
                    if let Some(ui) = weak_ui.upgrade() {
                        apply_palette(&ui, palette);
                    }
                });
            }
        }
    });
}

fn shuffle_slice<T>(slice: &mut [T]) {
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
