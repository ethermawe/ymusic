#include "YMusicBackend.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QMetaObject>
#include <QDebug>

YMusicBackend::YMusicBackend(QObject *parent)
    : QObject(parent) {
    m_core = ymusic_core_new(&YMusicBackend::cCallback, this);
}

YMusicBackend::~YMusicBackend() {
    if (m_core) {
        ymusic_core_free(m_core);
        m_core = nullptr;
    }
}

void YMusicBackend::cCallback(int32_t eventType, const char *jsonData, void *userData) {
    auto *backend = static_cast<YMusicBackend*>(userData);
    if (!backend || !jsonData) return;

    QString json = QString::fromUtf8(jsonData);
    QMetaObject::invokeMethod(backend, [backend, eventType, json]() {
        backend->handleEvent(eventType, json);
    }, Qt::QueuedConnection);
}

void YMusicBackend::handleEvent(int eventType, const QString &jsonData) {
    QJsonDocument doc = QJsonDocument::fromJson(jsonData.toUtf8());
    QJsonObject obj = doc.object();

    switch (eventType) {
    case EVENT_LOGIN_STATUS: {
        m_loggedIn = obj["logged_in"].toBool();
        m_loginBusy = obj["busy"].toBool();
        m_userName = obj["user_name"].toString();
        m_userAvatar = obj["user_avatar"].toString();
        m_userHasAvatar = obj["user_has_avatar"].toBool();
        emit authChanged();
        break;
    }
    case EVENT_LOGIN_DEVICE_CODE: {
        m_loginCode = obj["user_code"].toString();
        m_loginUrl = obj["verification_url"].toString();
        emit authChanged();
        break;
    }
    case EVENT_NOW_PLAYING: {
        m_hasTrack = obj["has_track"].toBool();
        m_nowId = obj["id"].toString();
        m_nowTitle = obj["title"].toString();
        m_nowArtists = obj["artists"].toString();
        m_nowAlbum = obj["album"].toString();
        m_nowCover = obj["cover_url"].toString();
        m_hasCover = obj["has_cover"].toBool();
        m_durationText = obj["duration_text"].toString();
        m_nowLiked = obj["liked"].toBool();
        m_nowHasArtist = obj["has_artist"].toBool();
        m_nowHasAlbum = obj["has_album"].toBool();
        emit nowPlayingChanged();
        break;
    }
    case EVENT_PLAYBACK_PROGRESS: {
        m_progress = obj["progress"].toDouble();
        m_positionText = obj["position_text"].toString();
        emit progressChanged();
        break;
    }
    case EVENT_PLAYBACK_STATE: {
        m_playing = obj["playing"].toBool();
        m_buffering = obj["buffering"].toBool();
        m_volume = obj["volume"].toDouble();
        m_shuffle = obj["shuffle"].toBool();
        m_repeatMode = obj["repeat_mode"].toInt();
        m_trackModel.setPlaying(m_playing);
        emit playbackStateChanged();
        emit volumeChanged();
        break;
    }
    case EVENT_TRACKS_LOADED: {
        QJsonArray arr = obj["tracks"].toArray();
        int curIdx = obj["current_index"].toInt();
        m_trackModel.setTracks(arr, curIdx);
        break;
    }
    case EVENT_CARDS_LOADED: {
        QJsonArray arr = obj["cards"].toArray();
        m_cardModel.setCards(arr);
        break;
    }
    case EVENT_VIEW_HEADER: {
        int newPage = obj["page"].toInt();
        if (newPage == 6 && m_page != 6) {
            m_previousPage = m_page;
        }
        m_page = newPage;
        m_listTitle = obj["title"].toString();
        m_listSubtitle = obj["subtitle"].toString();
        m_listLoading = obj["loading"].toBool();
        m_isArtistView = obj["is_artist_view"].toBool();
        m_artistName = obj["artist_name"].toString();
        m_artistGenres = obj["artist_genres"].toString();
        m_artistStats = obj["artist_stats"].toString();
        m_artistAvatar = obj["artist_avatar"].toString();
        m_artistHasAvatar = obj["artist_has_avatar"].toBool();
        m_canStartArtistWave = obj["can_start_artist_wave"].toBool();
        emit viewHeaderChanged();
        break;
    }
    case EVENT_STATUS_MSG: {
        m_statusMessage = obj["text"].toString();
        emit statusChanged();
        break;
    }
    default:
        break;
    }
}

void YMusicBackend::loginDevice() {
    if (m_core) ymusic_core_login_device(m_core);
}

void YMusicBackend::loginToken(const QString &token) {
    if (m_core) ymusic_core_login_token(m_core, token.toUtf8().constData());
}

void YMusicBackend::logout() {
    if (m_core) ymusic_core_logout(m_core);
}

void YMusicBackend::loadHome() {
    if (m_core) ymusic_core_load_home(m_core);
}

void YMusicBackend::loadLikes() {
    if (m_core) ymusic_core_load_likes(m_core);
}

void YMusicBackend::loadPlaylists() {
    if (m_core) ymusic_core_load_playlists(m_core);
}

void YMusicBackend::loadAlbums() {
    if (m_core) ymusic_core_load_albums(m_core);
}

void YMusicBackend::loadArtists() {
    if (m_core) ymusic_core_load_artists(m_core);
}

void YMusicBackend::goBack() {
    switch (m_previousPage) {
    case 0: loadHome(); break;
    case 1: startWave(); break;
    case 2: loadLikes(); break;
    case 3: loadPlaylists(); break;
    case 4: loadAlbums(); break;
    case 5: loadArtists(); break;
    default: loadHome(); break;
    }
}

void YMusicBackend::startWave() {
    if (m_core) ymusic_core_start_wave(m_core);
}

void YMusicBackend::startArtistWave() {
    if (m_core) ymusic_core_start_artist_wave(m_core);
}

void YMusicBackend::search(const QString &query) {
    if (m_core) ymusic_core_search(m_core, query.toUtf8().constData());
}

void YMusicBackend::openCard(int index) {
    if (m_core) ymusic_core_open_card(m_core, index);
}

void YMusicBackend::openTrackArtist(int index) {
    if (m_core) ymusic_core_open_track_artist(m_core, index);
}

void YMusicBackend::openTrackAlbum(int index) {
    if (m_core) ymusic_core_open_track_album(m_core, index);
}

void YMusicBackend::openNowArtist() {
    if (m_core) ymusic_core_open_now_artist(m_core);
}

void YMusicBackend::openNowAlbum() {
    if (m_core) ymusic_core_open_now_album(m_core);
}

void YMusicBackend::play(int index) {
    if (m_core) ymusic_core_play(m_core, index);
}

void YMusicBackend::toggle() {
    if (m_core) ymusic_core_toggle(m_core);
}

void YMusicBackend::next() {
    if (m_core) ymusic_core_next(m_core);
}

void YMusicBackend::prev() {
    if (m_core) ymusic_core_prev(m_core);
}

void YMusicBackend::seek(qreal fraction) {
    if (m_core) ymusic_core_seek(m_core, static_cast<float>(fraction));
}

void YMusicBackend::setVolume(qreal vol) {
    if (m_core) ymusic_core_set_volume(m_core, static_cast<float>(vol));
}

void YMusicBackend::toggleMute() {
    if (m_core) ymusic_core_toggle_mute(m_core);
}

void YMusicBackend::toggleShuffle() {
    if (m_core) ymusic_core_toggle_shuffle(m_core);
}

void YMusicBackend::toggleRepeat() {
    if (m_core) ymusic_core_toggle_repeat(m_core);
}

void YMusicBackend::toggleLike(int index) {
    if (m_core) ymusic_core_toggle_like(m_core, index);
}

void YMusicBackend::toggleNowLike() {
    if (m_core) ymusic_core_toggle_now_like(m_core);
}

void YMusicBackend::dislikeNow() {
    if (m_core) ymusic_core_dislike_now(m_core);
}

void YMusicBackend::clearStatus() {
    m_statusMessage.clear();
    emit statusChanged();
}
