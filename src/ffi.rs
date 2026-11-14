use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};
use std::sync::{Arc, RwLock};

use crate::core::{EventSink, YMusicCore};

pub type EventCallback = extern "C" fn(event_type: i32, json_data: *const c_char, user_data: *mut c_void);

pub struct FfiSink {
    callback: EventCallback,
    user_data: *mut c_void,
    /// После `ymusic_core_free` фоновые задачи ещё могут слать события,
    /// а `user_data` к этому моменту уже освобождён на стороне C++.
    closed: RwLock<bool>,
}

unsafe impl Send for FfiSink {}
unsafe impl Sync for FfiSink {}

impl EventSink for FfiSink {
    fn on_event(&self, event_type: i32, json_data: &str) {
        let closed = self.closed.read().unwrap_or_else(|e| e.into_inner());
        if *closed {
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
    let sink = Arc::new(FfiSink { callback, user_data, closed: RwLock::new(false) });
    let core = YMusicCore::new(sink.clone());
    Box::into_raw(Box::new(CoreHandle { core, sink }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_free(handle: *mut CoreHandle) {
    if !handle.is_null() {
        let h = unsafe { Box::from_raw(handle) };
        // Дожидаемся завершения уже идущих колбэков и запрещаем новые.
        *h.sink.closed.write().unwrap_or_else(|e| e.into_inner()) = true;
        h.core.shutdown();
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_login_device(handle: *mut CoreHandle) {
    if let Some(h) = unsafe { handle.as_ref() } {
        h.core.clone().login_device();
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_login_token(handle: *mut CoreHandle, token: *const c_char) {
    if let Some(h) = unsafe { handle.as_ref() } && !token.is_null() {
        if let Ok(t) = unsafe { CStr::from_ptr(token) }.to_str() {
            h.core.clone().login(t.trim().to_string());
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_logout(handle: *mut CoreHandle) {
    if let Some(h) = unsafe { handle.as_ref() } {
        h.core.logout();
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_load_home(handle: *mut CoreHandle) {
    if let Some(h) = unsafe { handle.as_ref() } {
        h.core.clone().load_home();
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_load_likes(handle: *mut CoreHandle) {
    if let Some(h) = unsafe { handle.as_ref() } {
        h.core.clone().load_likes();
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_load_downloads(handle: *mut CoreHandle) {
    if let Some(h) = unsafe { handle.as_ref() } { h.core.clone().load_downloads(); }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_feature(handle: *mut CoreHandle, json: *const c_char) {
    if let Some(h) = unsafe { handle.as_ref() } && !json.is_null()
        && let Ok(json) = unsafe { CStr::from_ptr(json) }.to_str()
        && let Ok(cmd) = serde_json::from_str(json)
    { h.core.clone().feature_command(cmd); }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_playlist_choices(handle: *mut CoreHandle, id: *const c_char) {
    if let Some(h) = unsafe { handle.as_ref() } && !id.is_null()
        && let Ok(id) = unsafe { CStr::from_ptr(id) }.to_str()
    { h.core.clone().playlist_choices(id.into()); }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_add_to_playlist(handle: *mut CoreHandle, id: *const c_char, kind: u64) {
    if let Some(h) = unsafe { handle.as_ref() } && !id.is_null()
        && let Ok(id) = unsafe { CStr::from_ptr(id) }.to_str()
    { h.core.clone().add_to_playlist(id.into(), kind); }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_remove_download(handle: *mut CoreHandle, id: *const c_char) {
    if let Some(h) = unsafe { handle.as_ref() } && !id.is_null()
        && let Ok(id) = unsafe { CStr::from_ptr(id) }.to_str()
    { h.core.clone().remove_download(id.to_string()); }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_load_playlists(handle: *mut CoreHandle) {
    if let Some(h) = unsafe { handle.as_ref() } {
        h.core.clone().load_playlists();
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_load_albums(handle: *mut CoreHandle) {
    if let Some(h) = unsafe { handle.as_ref() } {
        h.core.clone().load_albums();
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_load_artists(handle: *mut CoreHandle) {
    if let Some(h) = unsafe { handle.as_ref() } {
        h.core.clone().load_artists();
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_start_wave(handle: *mut CoreHandle) {
    if let Some(h) = unsafe { handle.as_ref() } {
        h.core.clone().open_or_start_wave("user:onyourwave".into(), "Моя волна".into());
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_start_artist_wave(handle: *mut CoreHandle) {
    if let Some(h) = unsafe { handle.as_ref() } {
        let artist = h.core.state.lock().unwrap().viewed_artist_id.clone();
        if let Some((id, name)) = artist {
            h.core.clone().start_wave(format!("artist:{id}"), format!("Волна: {name}"));
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_search(handle: *mut CoreHandle, query: *const c_char) {
    if let Some(h) = unsafe { handle.as_ref() } && !query.is_null() {
        if let Ok(q) = unsafe { CStr::from_ptr(query) }.to_str() {
            h.core.clone().search(q.trim().to_string());
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_open_card(handle: *mut CoreHandle, index: usize) {
    if let Some(h) = unsafe { handle.as_ref() } {
        h.core.clone().open_card(index);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_open_track_artist(handle: *mut CoreHandle, index: usize) {
    if let Some(h) = unsafe { handle.as_ref() } {
        let id = h.core.state.lock().unwrap().list.get(index).and_then(|t| t.artist_id.clone());
        if let Some(id) = id {
            h.core.clone().open_artist(id);
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_open_track_album(handle: *mut CoreHandle, index: usize) {
    if let Some(h) = unsafe { handle.as_ref() } {
        let id = h.core.state.lock().unwrap().list.get(index).and_then(|t| t.album_id.clone());
        if let Some(id) = id {
            h.core.clone().open_album(id);
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_open_now_artist(handle: *mut CoreHandle) {
    if let Some(h) = unsafe { handle.as_ref() } {
        let id = {
            let st = h.core.state.lock().unwrap();
            st.current.and_then(|i| st.queue.get(i)).and_then(|t| t.artist_id.clone())
        };
        if let Some(id) = id {
            h.core.clone().open_artist(id);
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_open_artist(handle: *mut CoreHandle, artist_id: *const c_char) {
    if let Some(h) = unsafe { handle.as_ref() } && !artist_id.is_null()
        && let Ok(id) = unsafe { CStr::from_ptr(artist_id) }.to_str()
        && !id.is_empty()
    {
        h.core.clone().open_artist(id.to_string());
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_open_now_album(handle: *mut CoreHandle) {
    if let Some(h) = unsafe { handle.as_ref() } {
        let id = {
            let st = h.core.state.lock().unwrap();
            st.current.and_then(|i| st.queue.get(i)).and_then(|t| t.album_id.clone())
        };
        if let Some(id) = id {
            h.core.clone().open_album(id);
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_play(handle: *mut CoreHandle, index: usize) {
    if let Some(h) = unsafe { handle.as_ref() } {
        let rt = h.core.rt_handle.clone();
        let core = h.core.clone();
        rt.spawn(async move {
            {
                let mut st = core.state.lock().unwrap();
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
}

/// action: 0 = play next, 1 = append, 2 = play on repeat.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_track_action(handle: *mut CoreHandle, id: *const c_char, action: i32) {
    if let Some(h) = unsafe { handle.as_ref() } && !id.is_null()
        && let Ok(id) = unsafe { CStr::from_ptr(id) }.to_str()
        && let Some(track) = h.core.find_track(id)
    {
        let core = h.core.clone();
        h.core.rt_handle.spawn(async move {
            if action == 3 {
                let index = core.state.lock().unwrap().queue.iter().position(|t| t.id == track.id);
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
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_download_track(handle: *mut CoreHandle, id: *const c_char, path: *const c_char) {
    if let Some(h) = unsafe { handle.as_ref() } && !id.is_null() && !path.is_null()
        && let (Ok(id), Ok(path)) = (unsafe { CStr::from_ptr(id) }.to_str(), unsafe { CStr::from_ptr(path) }.to_str())
        && let Some(track) = h.core.find_track(id)
    {
        let destination = (!path.is_empty()).then(|| std::path::PathBuf::from(path));
        h.core.clone().download_track(track, destination);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_toggle(handle: *mut CoreHandle) {
    if let Some(h) = unsafe { handle.as_ref() } {
        let rt = h.core.rt_handle.clone();
        let core = h.core.clone();
        rt.spawn(async move {
            core.toggle();
        });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_next(handle: *mut CoreHandle) {
    if let Some(h) = unsafe { handle.as_ref() } {
        let rt = h.core.rt_handle.clone();
        let core = h.core.clone();
        rt.spawn(async move {
            core.step(1, true);
        });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_prev(handle: *mut CoreHandle) {
    if let Some(h) = unsafe { handle.as_ref() } {
        let rt = h.core.rt_handle.clone();
        let core = h.core.clone();
        rt.spawn(async move {
            core.step(-1, true);
        });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_seek(handle: *mut CoreHandle, fraction: f32) {
    if let Some(h) = unsafe { handle.as_ref() } {
        let rt = h.core.rt_handle.clone();
        let core = h.core.clone();
        rt.spawn(async move {
            core.seek(fraction);
        });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_set_volume(handle: *mut CoreHandle, volume: f32) {
    if let Some(h) = unsafe { handle.as_ref() } {
        let rt = h.core.rt_handle.clone();
        let core = h.core.clone();
        rt.spawn(async move {
            core.set_volume(volume);
        });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_set_discord_enabled(handle: *mut CoreHandle, enabled: bool) {
    if let Some(h) = unsafe { handle.as_ref() } {
        h.core.set_discord_enabled(enabled);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_toggle_mute(handle: *mut CoreHandle) {
    if let Some(h) = unsafe { handle.as_ref() } {
        let rt = h.core.rt_handle.clone();
        let core = h.core.clone();
        rt.spawn(async move {
            core.toggle_mute();
        });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_toggle_shuffle(handle: *mut CoreHandle) {
    if let Some(h) = unsafe { handle.as_ref() } {
        let rt = h.core.rt_handle.clone();
        let core = h.core.clone();
        rt.spawn(async move {
            core.toggle_shuffle();
        });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_toggle_repeat(handle: *mut CoreHandle) {
    if let Some(h) = unsafe { handle.as_ref() } {
        let rt = h.core.rt_handle.clone();
        let core = h.core.clone();
        rt.spawn(async move {
            core.toggle_repeat();
        });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_toggle_like(handle: *mut CoreHandle, index: usize) {
    if let Some(h) = unsafe { handle.as_ref() } {
        let rt = h.core.rt_handle.clone();
        let core = h.core.clone();
        rt.spawn(async move {
            core.toggle_like_at(index);
        });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_toggle_now_like(handle: *mut CoreHandle) {
    if let Some(h) = unsafe { handle.as_ref() } {
        let rt = h.core.rt_handle.clone();
        let core = h.core.clone();
        rt.spawn(async move {
            core.toggle_now_like();
        });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_dislike_now(handle: *mut CoreHandle) {
    if let Some(h) = unsafe { handle.as_ref() } {
        let rt = h.core.rt_handle.clone();
        let core = h.core.clone();
        rt.spawn(async move {
            core.dislike_now();
        });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_spectrum_levels(handle: *mut CoreHandle, out: *mut f32, capacity: u32) -> u32 {
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
}
