#pragma once

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

enum YMusicEventType {
    EVENT_LOGIN_STATUS = 1,
    EVENT_LOGIN_DEVICE_CODE = 2,
    EVENT_NOW_PLAYING = 3,
    EVENT_PLAYBACK_PROGRESS = 4,
    EVENT_PLAYBACK_STATE = 5,
    EVENT_TRACKS_LOADED = 6,
    EVENT_CARDS_LOADED = 7,
    EVENT_VIEW_HEADER = 8,
    EVENT_STATUS_MSG = 9,
    EVENT_QUEUE_LOADED = 10,
    EVENT_PLAYLIST_PICKER = 11,
    EVENT_FEATURE = 12
};

typedef struct CoreHandle CoreHandle;
typedef void (*EventCallback)(int32_t event_type, const char *json_data, void *user_data);

/*
 * Lifetime & thread-safety contract:
 * - `callback` may be invoked from background worker threads with `user_data`.
 * - `callback` is invoked without holding internal Rust locks.
 * - `ymusic_core_free(handle)` marks the sink closed, waits for any in-flight
 *   callbacks on other threads to finish (re-entrant calls from inside the
 *   callback itself will not deadlock), and shuts down the core runtime.
 * - After `ymusic_core_free` returns, `callback` is guaranteed not to be called
 *   again for that handle, so `user_data` may be destroyed safely.
 * - Passing NULL to any function is a safe no-op. Panics are caught at the FFI
 *   boundary and logged to crash.log instead of unwinding into C++.
 */
CoreHandle *ymusic_core_new(EventCallback callback, void *user_data);
void ymusic_core_free(CoreHandle *handle);

void ymusic_core_login_device(CoreHandle *handle);
void ymusic_core_login_token(CoreHandle *handle, const char *token);
void ymusic_core_cancel_login(CoreHandle *handle);
void ymusic_core_logout(CoreHandle *handle);

void ymusic_core_load_home(CoreHandle *handle);
void ymusic_core_load_likes(CoreHandle *handle);
void ymusic_core_load_downloads(CoreHandle *handle);
void ymusic_core_feature(CoreHandle *handle, const char *json);
void ymusic_core_playlist_choices(CoreHandle *handle, const char *id);
void ymusic_core_add_to_playlist(CoreHandle *handle, const char *id, uint64_t kind);
void ymusic_core_remove_download(CoreHandle *handle, const char *id);
void ymusic_core_load_playlists(CoreHandle *handle);
void ymusic_core_load_albums(CoreHandle *handle);
void ymusic_core_load_artists(CoreHandle *handle);

void ymusic_core_start_wave(CoreHandle *handle);
void ymusic_core_start_artist_wave(CoreHandle *handle);
void ymusic_core_search(CoreHandle *handle, const char *query);

void ymusic_core_open_card(CoreHandle *handle, uintptr_t index);
void ymusic_core_open_track_artist(CoreHandle *handle, uintptr_t index);
void ymusic_core_open_track_album(CoreHandle *handle, uintptr_t index);
void ymusic_core_open_now_artist(CoreHandle *handle);
void ymusic_core_open_artist(CoreHandle *handle, const char *artist_id);
void ymusic_core_open_now_album(CoreHandle *handle);
void ymusic_core_set_discord_enabled(CoreHandle *handle, bool enabled);
void ymusic_core_set_discord_config(CoreHandle *handle, const char *config_json);

void ymusic_core_play(CoreHandle *handle, uintptr_t index);
void ymusic_core_track_action(CoreHandle *handle, const char *id, int32_t action);
void ymusic_core_download_track(CoreHandle *handle, const char *id, const char *path);
void ymusic_core_toggle(CoreHandle *handle);
void ymusic_core_next(CoreHandle *handle);
void ymusic_core_prev(CoreHandle *handle);
void ymusic_core_seek(CoreHandle *handle, float fraction);
void ymusic_core_set_volume(CoreHandle *handle, float volume);
void ymusic_core_toggle_mute(CoreHandle *handle);
void ymusic_core_toggle_shuffle(CoreHandle *handle);
void ymusic_core_toggle_repeat(CoreHandle *handle);
void ymusic_core_toggle_like(CoreHandle *handle, uintptr_t index);
void ymusic_core_toggle_now_like(CoreHandle *handle);
void ymusic_core_dislike_now(CoreHandle *handle);
void ymusic_core_save_session(CoreHandle *handle);
uint32_t ymusic_core_spectrum_levels(CoreHandle *handle, float *out, uint32_t capacity);

void ymusic_hook_subscribe(CoreHandle *handle, const char *point, bool enabled);
void ymusic_hook_response(CoreHandle *handle, uint64_t id, const char *json);

#ifdef __cplusplus
}
#endif
