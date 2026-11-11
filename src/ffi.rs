use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};
use std::sync::Arc;

use crate::core::{EventSink, YMusicCore};

pub type EventCallback = extern "C" fn(event_type: i32, json_data: *const c_char, user_data: *mut c_void);

pub struct FfiSink {
    callback: EventCallback,
    user_data: *mut c_void,
}

unsafe impl Send for FfiSink {}
unsafe impl Sync for FfiSink {}

impl EventSink for FfiSink {
    fn on_event(&self, event_type: i32, json_data: &str) {
        if let Ok(c_str) = CString::new(json_data) {
            (self.callback)(event_type, c_str.as_ptr(), self.user_data);
        }
    }
}

pub struct CoreHandle {
    pub core: Arc<YMusicCore>,
}

#[unsafe(no_mangle)]
pub extern "C" fn ymusic_core_new(callback: EventCallback, user_data: *mut c_void) -> *mut CoreHandle {
    let sink = Arc::new(FfiSink { callback, user_data });
    let core = YMusicCore::new(sink);
    Box::into_raw(Box::new(CoreHandle { core }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_free(handle: *mut CoreHandle) {
    if !handle.is_null() {
        let h = unsafe { Box::from_raw(handle) };
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
        {
            let mut st = h.core.state.lock().unwrap();
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
        h.core.clone().play_index(index, true);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_toggle(handle: *mut CoreHandle) {
    if let Some(h) = unsafe { handle.as_ref() } {
        h.core.clone().toggle();
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_next(handle: *mut CoreHandle) {
    if let Some(h) = unsafe { handle.as_ref() } {
        h.core.clone().step(1, true);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_prev(handle: *mut CoreHandle) {
    if let Some(h) = unsafe { handle.as_ref() } {
        h.core.clone().step(-1, true);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_seek(handle: *mut CoreHandle, fraction: f32) {
    if let Some(h) = unsafe { handle.as_ref() } {
        h.core.seek(fraction);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_set_volume(handle: *mut CoreHandle, volume: f32) {
    if let Some(h) = unsafe { handle.as_ref() } {
        h.core.set_volume(volume);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_toggle_mute(handle: *mut CoreHandle) {
    if let Some(h) = unsafe { handle.as_ref() } {
        h.core.clone().toggle_mute();
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_toggle_shuffle(handle: *mut CoreHandle) {
    if let Some(h) = unsafe { handle.as_ref() } {
        h.core.clone().toggle_shuffle();
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_toggle_repeat(handle: *mut CoreHandle) {
    if let Some(h) = unsafe { handle.as_ref() } {
        h.core.clone().toggle_repeat();
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_toggle_like(handle: *mut CoreHandle, index: usize) {
    if let Some(h) = unsafe { handle.as_ref() } {
        h.core.clone().toggle_like_at(index);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_toggle_now_like(handle: *mut CoreHandle) {
    if let Some(h) = unsafe { handle.as_ref() } {
        h.core.clone().toggle_now_like();
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ymusic_core_dislike_now(handle: *mut CoreHandle) {
    if let Some(h) = unsafe { handle.as_ref() } {
        h.core.clone().dislike_now();
    }
}
