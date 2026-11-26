#![allow(clippy::missing_safety_doc)]

use std::backtrace::Backtrace;
use std::cell::Cell;
use std::ffi::{CStr, CString};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::os::raw::{c_char, c_void};
use std::panic::{self, AssertUnwindSafe};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Once};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::core::{EventSink, YMusicCore};

pub type EventCallback = extern "C" fn(event_type: i32, json_data: *const c_char, user_data: *mut c_void);

thread_local! {
    static IN_FFI_CALLBACK: Cell<usize> = const { Cell::new(0) };
}

static PANIC_HOOK_ONCE: Once = Once::new();

pub fn crash_log_path() -> Option<PathBuf> {
    #[cfg(target_os = "windows")]
    let base = dirs::data_local_dir();
    #[cfg(not(target_os = "windows"))]
    let base = dirs::state_dir().or_else(dirs::data_local_dir);
    base.map(|d| d.join("ymusic").join("crash.log"))
}

pub fn install_panic_hook() {
    PANIC_HOOK_ONCE.call_once(|| {
        let prev = panic::take_hook();
        panic::set_hook(Box::new(move |info| {
            let bt = Backtrace::force_capture();
            let ts = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0);
            let msg = format!("[{ts}] PANIC: {info}\nBacktrace:\n{bt}\n---\n");
            eprintln!("{msg}");
            if let Some(path) = crash_log_path() {
                if let Some(parent) = path.parent() {
                    let _ = fs::create_dir_all(parent);
                }
                if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(&path) {
                    let _ = file.write_all(msg.as_bytes());
                }
            }
            prev(info);
        }));
    });
}

fn format_panic_payload(payload: &(dyn std::any::Any + Send)) -> String {
    if let Some(s) = payload.downcast_ref::<&str>() {
        (*s).to_string()
    } else if let Some(s) = payload.downcast_ref::<String>() {
        s.clone()
    } else {
        "unknown panic payload".to_string()
    }
}

macro_rules! ffi_guard {
    ($fn_name:literal, $default:expr, $body:block) => {{
        match panic::catch_unwind(AssertUnwindSafe(move || $body)) {
            Ok(val) => val,
            Err(payload) => {
                eprintln!(
                    "[ymusic_core::ffi] caught panic in {}: {}",
                    $fn_name,
                    format_panic_payload(payload.as_ref())
                );
                $default
            }
        }
    }};
}

pub struct FfiSink {
    callback: EventCallback,
    user_data: *mut c_void,
    /// Lock-free shutdown flag: prevents new callbacks after `ymusic_core_free`.
    closed: AtomicBool,
    /// Number of currently executing callbacks across all threads.
    active_calls: AtomicUsize,
}

unsafe impl Send for FfiSink {}
unsafe impl Sync for FfiSink {}

struct ActiveCallGuard<'a>(&'a FfiSink);

impl Drop for ActiveCallGuard<'_> {
    fn drop(&mut self) {
        IN_FFI_CALLBACK.with(|c| c.set(c.get().saturating_sub(1)));
        self.0.active_calls.fetch_sub(1, Ordering::Release);
    }
}

impl FfiSink {
    fn new(callback: EventCallback, user_data: *mut c_void) -> Self {
        Self {
            callback,
            user_data,
            closed: AtomicBool::new(false),
            active_calls: AtomicUsize::new(0),
        }
    }

    fn close_and_wait(&self) {
        self.closed.store(true, Ordering::Release);
        let self_depth = IN_FFI_CALLBACK.with(Cell::get);
        while self.active_calls.load(Ordering::Acquire) > self_depth {
            std::thread::yield_now();
        }
    }
}

impl EventSink for FfiSink {
    fn on_event(&self, event_type: i32, json_data: &str) {
        if self.closed.load(Ordering::Acquire) {
            return;
        }
        self.active_calls.fetch_add(1, Ordering::AcqRel);
        IN_FFI_CALLBACK.with(|c| c.set(c.get() + 1));
        let _guard = ActiveCallGuard(self);

        // Re-check after incrementing active_calls to close the TOCTOU window with close_and_wait().
        if self.closed.load(Ordering::Acquire) {
            return;
        }
        if let Ok(c_str) = CString::new(json_data) {
            (self.callback)(event_type, c_str.as_ptr(), self.user_data);
        }
    }
}

pub struct CoreHandle {
    pub core: Arc<YMusicCore>,
    sink: Arc<FfiSink>,
}

#[unsafe(no_mangle)]
pub extern "C" fn ymusic_core_new(callback: EventCallback, user_data: *mut c_void) -> *mut CoreHandle {
    install_panic_hook();
    ffi_guard!("ymusic_core_new", std::ptr::null_mut(), {
        let sink = Arc::new(FfiSink::new(callback, user_data));
        let core = YMusicCore::new(sink.clone());
        Box::into_raw(Box::new(CoreHandle { core, sink }))
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_free(handle: *mut CoreHandle) {
    ffi_guard!("ymusic_core_free", (), {
        if !handle.is_null() {
            let h = unsafe { Box::from_raw(handle) };
            h.sink.close_and_wait();
            h.core.shutdown();
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_login_device(handle: *mut CoreHandle) {
    ffi_guard!("ymusic_core_login_device", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            h.core.clone().login_device();
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_login_token(handle: *mut CoreHandle, token: *const c_char) {
    ffi_guard!("ymusic_core_login_token", (), {
        if let Some(h) = unsafe { handle.as_ref() } && !token.is_null() {
            if let Ok(t) = unsafe { CStr::from_ptr(token) }.to_str() {
                h.core.clone().login(t.trim().to_string());
            }
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_cancel_login(handle: *mut CoreHandle) {
    ffi_guard!("ymusic_core_cancel_login", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            h.core.cancel_login();
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_logout(handle: *mut CoreHandle) {
    ffi_guard!("ymusic_core_logout", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            h.core.logout();
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_load_home(handle: *mut CoreHandle) {
    ffi_guard!("ymusic_core_load_home", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            h.core.clone().load_home();
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_load_likes(handle: *mut CoreHandle) {
    ffi_guard!("ymusic_core_load_likes", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            h.core.clone().load_likes();
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_load_downloads(handle: *mut CoreHandle) {
    ffi_guard!("ymusic_core_load_downloads", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            h.core.clone().load_downloads();
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_feature(handle: *mut CoreHandle, json: *const c_char) {
    ffi_guard!("ymusic_core_feature", (), {
        if let Some(h) = unsafe { handle.as_ref() } && !json.is_null()
            && let Ok(json) = unsafe { CStr::from_ptr(json) }.to_str()
            && let Ok(cmd) = serde_json::from_str(json)
        {
            h.core.clone().feature_command(cmd);
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_playlist_choices(handle: *mut CoreHandle, id: *const c_char) {
    ffi_guard!("ymusic_core_playlist_choices", (), {
        if let Some(h) = unsafe { handle.as_ref() } && !id.is_null()
            && let Ok(id) = unsafe { CStr::from_ptr(id) }.to_str()
        {
            h.core.clone().playlist_choices(id.into());
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_add_to_playlist(handle: *mut CoreHandle, id: *const c_char, kind: u64) {
    ffi_guard!("ymusic_core_add_to_playlist", (), {
        if let Some(h) = unsafe { handle.as_ref() } && !id.is_null()
            && let Ok(id) = unsafe { CStr::from_ptr(id) }.to_str()
        {
            h.core.clone().add_to_playlist(id.into(), kind);
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_remove_download(handle: *mut CoreHandle, id: *const c_char) {
    ffi_guard!("ymusic_core_remove_download", (), {
        if let Some(h) = unsafe { handle.as_ref() } && !id.is_null()
            && let Ok(id) = unsafe { CStr::from_ptr(id) }.to_str()
        {
            h.core.clone().remove_download(id.to_string());
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_load_playlists(handle: *mut CoreHandle) {
    ffi_guard!("ymusic_core_load_playlists", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            h.core.clone().load_playlists();
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_load_albums(handle: *mut CoreHandle) {
    ffi_guard!("ymusic_core_load_albums", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            h.core.clone().load_albums();
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_load_artists(handle: *mut CoreHandle) {
    ffi_guard!("ymusic_core_load_artists", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            h.core.clone().load_artists();
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_start_wave(handle: *mut CoreHandle) {
    ffi_guard!("ymusic_core_start_wave", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            h.core.clone().open_or_start_wave("user:onyourwave".into(), "Моя волна".into());
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_start_artist_wave(handle: *mut CoreHandle) {
    ffi_guard!("ymusic_core_start_artist_wave", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            let artist = h.core.state.lock().viewed_artist_id.clone();
            if let Some((id, name)) = artist {
                h.core.clone().start_wave(format!("artist:{id}"), format!("Волна: {name}"));
            }
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_search(handle: *mut CoreHandle, query: *const c_char) {
    ffi_guard!("ymusic_core_search", (), {
        if let Some(h) = unsafe { handle.as_ref() } && !query.is_null() {
            if let Ok(q) = unsafe { CStr::from_ptr(query) }.to_str() {
                h.core.clone().search(q.trim().to_string());
            }
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_open_card(handle: *mut CoreHandle, index: usize) {
    ffi_guard!("ymusic_core_open_card", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            h.core.clone().open_card(index);
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_open_track_artist(handle: *mut CoreHandle, index: usize) {
    ffi_guard!("ymusic_core_open_track_artist", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            let id = h.core.state.lock().list.get(index).and_then(|t| t.artist_id.clone());
            if let Some(id) = id {
                h.core.clone().open_artist(id);
            }
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_open_track_album(handle: *mut CoreHandle, index: usize) {
    ffi_guard!("ymusic_core_open_track_album", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            let id = h.core.state.lock().list.get(index).and_then(|t| t.album_id.clone());
            if let Some(id) = id {
                h.core.clone().open_album(id);
            }
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_open_now_artist(handle: *mut CoreHandle) {
    ffi_guard!("ymusic_core_open_now_artist", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            let id = {
                let st = h.core.state.lock();
                st.current.and_then(|i| st.queue.get(i)).and_then(|t| t.artist_id.clone())
            };
            if let Some(id) = id {
                h.core.clone().open_artist(id);
            }
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_open_artist(handle: *mut CoreHandle, artist_id: *const c_char) {
    ffi_guard!("ymusic_core_open_artist", (), {
        if let Some(h) = unsafe { handle.as_ref() } && !artist_id.is_null()
            && let Ok(id) = unsafe { CStr::from_ptr(artist_id) }.to_str()
            && !id.is_empty()
        {
            h.core.clone().open_artist(id.to_string());
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_open_now_album(handle: *mut CoreHandle) {
    ffi_guard!("ymusic_core_open_now_album", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            let id = {
                let st = h.core.state.lock();
                st.current.and_then(|i| st.queue.get(i)).and_then(|t| t.album_id.clone())
            };
            if let Some(id) = id {
                h.core.clone().open_album(id);
            }
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_play(handle: *mut CoreHandle, index: usize) {
    ffi_guard!("ymusic_core_play", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            let rt = h.core.rt_handle.clone();
            let core = h.core.clone();
            rt.spawn(async move {
                {
                    let mut st = core.state.lock();
                    let same_as_queue = st.list.len() == st.queue.len()
                        && st.list.iter().zip(&st.queue).all(|(x, y)| x.id == y.id);
                    if !same_as_queue {
                        st.wave = None;
                        st.unshuffled_queue = None;
                        st.queue = st.list.clone();
                        if st.shuffle && (index + 1) < st.queue.len() {
                            st.unshuffled_queue = Some(st.list.clone());
                            let mut tail = st.queue.split_off(index + 1);
                            crate::core::shuffle_slice(&mut tail);
                            st.queue.extend(tail);
                        }
                    }
                }
                core.play_index(index, true);
            });
        }
    })
}

/// action: 0 = play next, 1 = append, 2 = play on repeat.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_track_action(handle: *mut CoreHandle, id: *const c_char, action: i32) {
    ffi_guard!("ymusic_core_track_action", (), {
        if let Some(h) = unsafe { handle.as_ref() } && !id.is_null()
            && let Ok(id) = unsafe { CStr::from_ptr(id) }.to_str()
            && let Some(track) = h.core.find_track(id)
        {
            let core = h.core.clone();
            h.core.rt_handle.spawn(async move {
                if action == 3 {
                    let index = core.state.lock().queue.iter().position(|t| t.id == track.id);
                    if let Some(index) = index { core.play_index(index, true); }
                }
                else if action == 4 { core.toggle_like_track(track); }
                else if action == 5 {
                    if let Some(id) = track.artist_id { core.open_artist(id); }
                }
                else if action == 6 {
                    if let Some(id) = track.album_id { core.open_album(id); }
                }
                else if action == 2 { core.repeat_track(track); }
                else if action == 0 || action == 1 { core.enqueue_track(track, action == 0); }
            });
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_download_track(handle: *mut CoreHandle, id: *const c_char, path: *const c_char) {
    ffi_guard!("ymusic_core_download_track", (), {
        if let Some(h) = unsafe { handle.as_ref() } && !id.is_null() && !path.is_null()
            && let (Ok(id), Ok(path)) = (unsafe { CStr::from_ptr(id) }.to_str(), unsafe { CStr::from_ptr(path) }.to_str())
            && let Some(track) = h.core.find_track(id)
        {
            let destination = (!path.is_empty()).then(|| std::path::PathBuf::from(path));
            h.core.clone().download_track(track, destination);
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_toggle(handle: *mut CoreHandle) {
    ffi_guard!("ymusic_core_toggle", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            let rt = h.core.rt_handle.clone();
            let core = h.core.clone();
            rt.spawn(async move {
                core.toggle();
            });
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_next(handle: *mut CoreHandle) {
    ffi_guard!("ymusic_core_next", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            let rt = h.core.rt_handle.clone();
            let core = h.core.clone();
            rt.spawn(async move {
                core.step(1, true);
            });
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_prev(handle: *mut CoreHandle) {
    ffi_guard!("ymusic_core_prev", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            let rt = h.core.rt_handle.clone();
            let core = h.core.clone();
            rt.spawn(async move {
                core.step(-1, true);
            });
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_seek(handle: *mut CoreHandle, fraction: f32) {
    ffi_guard!("ymusic_core_seek", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            let rt = h.core.rt_handle.clone();
            let core = h.core.clone();
            rt.spawn(async move {
                core.seek(fraction);
            });
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_set_volume(handle: *mut CoreHandle, volume: f32) {
    ffi_guard!("ymusic_core_set_volume", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            let rt = h.core.rt_handle.clone();
            let core = h.core.clone();
            rt.spawn(async move {
                core.set_volume(volume);
            });
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_set_discord_enabled(handle: *mut CoreHandle, enabled: bool) {
    ffi_guard!("ymusic_core_set_discord_enabled", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            h.core.set_discord_enabled(enabled);
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_set_discord_config(
    handle: *mut CoreHandle,
    config_json: *const c_char,
) {
    ffi_guard!("ymusic_core_set_discord_config", (), {
        if let Some(h) = unsafe { handle.as_ref() }
            && !config_json.is_null()
            && let Ok(json) = unsafe { CStr::from_ptr(config_json) }.to_str()
            && let Ok(config) = serde_json::from_str::<crate::discord::DiscordConfig>(json)
        {
            h.core.set_discord_config(config);
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_toggle_mute(handle: *mut CoreHandle) {
    ffi_guard!("ymusic_core_toggle_mute", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            let rt = h.core.rt_handle.clone();
            let core = h.core.clone();
            rt.spawn(async move {
                core.toggle_mute();
            });
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_toggle_shuffle(handle: *mut CoreHandle) {
    ffi_guard!("ymusic_core_toggle_shuffle", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            let rt = h.core.rt_handle.clone();
            let core = h.core.clone();
            rt.spawn(async move {
                core.toggle_shuffle();
            });
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_toggle_repeat(handle: *mut CoreHandle) {
    ffi_guard!("ymusic_core_toggle_repeat", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            let rt = h.core.rt_handle.clone();
            let core = h.core.clone();
            rt.spawn(async move {
                core.toggle_repeat();
            });
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_toggle_like(handle: *mut CoreHandle, index: usize) {
    ffi_guard!("ymusic_core_toggle_like", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            let rt = h.core.rt_handle.clone();
            let core = h.core.clone();
            rt.spawn(async move {
                core.toggle_like_at(index);
            });
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_toggle_now_like(handle: *mut CoreHandle) {
    ffi_guard!("ymusic_core_toggle_now_like", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            let rt = h.core.rt_handle.clone();
            let core = h.core.clone();
            rt.spawn(async move {
                core.toggle_now_like();
            });
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_dislike_now(handle: *mut CoreHandle) {
    ffi_guard!("ymusic_core_dislike_now", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            let rt = h.core.rt_handle.clone();
            let core = h.core.clone();
            rt.spawn(async move {
                core.dislike_now();
            });
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_save_session(handle: *mut CoreHandle) {
    ffi_guard!("ymusic_core_save_session", (), {
        if let Some(h) = unsafe { handle.as_ref() } {
            h.core.persist_session_sync();
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_spectrum_levels(handle: *mut CoreHandle, out: *mut f32, capacity: u32) -> u32 {
    ffi_guard!("ymusic_core_spectrum_levels", 0, {
        if out.is_null() || capacity == 0 {
            return 0;
        }
        let slice = unsafe { std::slice::from_raw_parts_mut(out, capacity as usize) };
        if let Some(h) = unsafe { handle.as_ref() } {
            h.core.spectrum_levels(slice) as u32
        } else {
            slice.fill(0.0);
            0
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_hook_subscribe(
    handle: *mut CoreHandle,
    point: *const c_char,
    enabled: bool,
) {
    ffi_guard!("ymusic_hook_subscribe", (), {
        if let Some(h) = unsafe { handle.as_ref() }
            && !point.is_null()
            && let Ok(name) = unsafe { CStr::from_ptr(point) }.to_str()
            && let Some(hp) = crate::hooks::HookPoint::parse(name)
        {
            h.core.hooks.subscribe(hp, enabled);
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_hook_response(
    handle: *mut CoreHandle,
    id: u64,
    json: *const c_char,
) {
    ffi_guard!("ymusic_hook_response", (), {
        if let Some(h) = unsafe { handle.as_ref() }
            && !json.is_null()
            && let Ok(raw) = unsafe { CStr::from_ptr(json) }.to_str()
        {
            h.core.hooks.respond(id, raw.to_string());
        }
    })
}

#[cfg(test)]
mod ffi_tests {
    use super::*;

    extern "C" fn count_callback(_event_type: i32, _json: *const c_char, user_data: *mut c_void) {
        if !user_data.is_null() {
            let counter = unsafe { &*(user_data as *const AtomicUsize) };
            counter.fetch_add(1, Ordering::SeqCst);
        }
    }

    #[test]
    fn ffi_guard_catches_panic_without_abort() {
        let res = ffi_guard!("test_panic", -1i32, {
            panic!("simulated ffi panic");
        });
        assert_eq!(res, -1);
    }

    #[test]
    fn sink_drops_events_after_close_and_allows_reentrant_close() {
        let hits = AtomicUsize::new(0);
        let sink = Arc::new(FfiSink::new(
            count_callback,
            (&hits as *const AtomicUsize) as *mut c_void,
        ));
        sink.on_event(1, "{}");
        assert_eq!(hits.load(Ordering::SeqCst), 1);

        sink.close_and_wait();
        sink.on_event(1, "{}");
        assert_eq!(hits.load(Ordering::SeqCst), 1);

        // Re-entrant close_and_wait inside callback must not deadlock
        extern "C" fn reentrant_cb(_ev: i32, _json: *const c_char, user_data: *mut c_void) {
            let s = unsafe { &*(user_data as *const FfiSink) };
            s.close_and_wait();
        }
        let boxed = Box::new(FfiSink::new(reentrant_cb, std::ptr::null_mut()));
        let ptr = Box::into_raw(boxed);
        unsafe {
            (*ptr).user_data = ptr as *mut c_void;
            (*ptr).on_event(1, "{}");
            assert!((*ptr).closed.load(Ordering::Acquire));
            drop(Box::from_raw(ptr));
        }
    }

    #[test]
    fn create_and_free_handle_safely() {
        let hits = AtomicUsize::new(0);
        let handle = ymusic_core_new(
            count_callback,
            (&hits as *const AtomicUsize) as *mut c_void,
        );
        assert!(!handle.is_null());
        unsafe {
            let mut buf = [0.0f32; 8];
            let n = ymusic_core_spectrum_levels(handle, buf.as_mut_ptr(), 8);
            assert!(n <= 8);
            ymusic_core_free(handle);
            // Null handle must be a safe no-op
            ymusic_core_free(std::ptr::null_mut());
            ymusic_core_toggle(std::ptr::null_mut());
        }
    }
}
