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
    EVENT_STATUS_MSG = 9
};

typedef struct CoreHandle CoreHandle;
typedef void (*EventCallback)(int32_t event_type, const char *json_data, void *user_data);

CoreHandle *ymusic_core_new(EventCallback callback, void *user_data);
void ymusic_core_free(CoreHandle *handle);

void ymusic_core_login_device(CoreHandle *handle);
void ymusic_core_login_token(CoreHandle *handle, const char *token);
void ymusic_core_logout(CoreHandle *handle);

void ymusic_core_load_home(CoreHandle *handle);
void ymusic_core_load_likes(CoreHandle *handle);
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
void ymusic_core_open_now_album(CoreHandle *handle);

void ymusic_core_play(CoreHandle *handle, uintptr_t index);
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

#ifdef __cplusplus
}
#endif
