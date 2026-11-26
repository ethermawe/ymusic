#include "YMusicBackend.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QMetaObject>
#include <QDebug>
#include <QGuiApplication>
#include <QClipboard>
#include <QCryptographicHash>
#include <QDesktopServices>
#include <QDir>
#include <QFileInfo>
#include <QUrl>
#include <algorithm>
#include <cmath>

YMusicBackend::YMusicBackend(QObject *parent)
    : QObject(parent) {
    s_instance = this;
    m_sleepTimer.setInterval(250);
    connect(&m_sleepTimer, &QTimer::timeout, this, &YMusicBackend::sleepTimerTick);
    m_core = ymusic_core_new(&YMusicBackend::cCallback, this);
    feature({{"action", "history"}});
}

YMusicBackend::~YMusicBackend() {
    if (s_instance == this) s_instance = nullptr;
    if (m_core) {
        ymusic_core_free(m_core);
        m_core = nullptr;
    }
}

int YMusicBackend::spectrumLevels(float *out, int count) const {
    if (!m_core || !out || count <= 0) return 0;
    return static_cast<int>(ymusic_core_spectrum_levels(m_core, out, static_cast<uint32_t>(count)));
}

void YMusicBackend::cCallback(int32_t eventType, const char *jsonData, void *userData) {
    auto *backend = static_cast<YMusicBackend*>(userData);
    if (!backend || !jsonData) return;

    QPointer<YMusicBackend> self(backend);
    QString json = QString::fromUtf8(jsonData);
    QMetaObject::invokeMethod(backend, [self, eventType, json]() {
        if (self) {
            self->handleEvent(eventType, json);
        }
    }, Qt::QueuedConnection);
}

void YMusicBackend::handleEvent(int eventType, const QString &jsonData) {
    QJsonDocument doc = QJsonDocument::fromJson(jsonData.toUtf8());
    QJsonObject obj = doc.object();

    switch (eventType) {
    case EVENT_LOGIN_STATUS: {
        m_loggedIn = obj["logged_in"].toBool();
        m_loginBusy = obj["busy"].toBool();
        if (!m_loginBusy) m_authReady = true;
        if (!m_loginBusy) {
            m_loginCode.clear();
            m_loginUrl.clear();
        }
        if (!m_loggedIn && !m_loginBusy) {
            m_waveSettings.clear();
            emit featuresChanged();
        }
        m_userName = obj["user_name"].toString();
        m_userAvatar = obj["user_avatar"].toString();
        m_userHasAvatar = obj["user_has_avatar"].toBool();
        emit authChanged();
        break;
    }
    case EVENT_LOGIN_DEVICE_CODE: {
        if (!m_loginBusy) break;
        m_loginCode = obj["user_code"].toString();
        m_loginUrl = obj["verification_url"].toString();
        emit authChanged();
        break;
    }
    case EVENT_NOW_PLAYING: {
        const QString nextId = obj["id"].toString();
        const bool nextHasTrack = obj["has_track"].toBool();
        if (nextId != m_nowId || nextHasTrack != m_hasTrack) {
            ++m_trackInstanceId;
        }
        m_hasTrack = nextHasTrack;
        m_nowId = nextId;
        m_nowTitle = obj["title"].toString();
        m_nowArtists = obj["artists"].toString();
        m_nowArtistLinks = obj["artist_links"].toArray().toVariantList();
        m_nowAlbum = obj["album"].toString();
        m_nowCover = obj["cover_url"].toString();
        m_hasCover = obj["has_cover"].toBool();
        m_durationText = obj["duration_text"].toString();
        m_nowLiked = obj["liked"].toBool();
        m_nowHasArtist = obj["has_artist"].toBool();
        m_nowHasAlbum = obj["has_album"].toBool();
        m_nowIsAi = obj["is_ai"].toBool();
        emit nowPlayingChanged();
        break;
    }
    case EVENT_PLAYBACK_PROGRESS: {
        m_progress = obj["progress"].toDouble();
        m_positionText = obj["position_text"].toString();
        m_positionSecs = obj["position_secs"].toDouble();
        m_durationSecs = obj["duration_secs"].toDouble();
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
        m_queueModel.setPlaying(m_playing);
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
    case EVENT_QUEUE_LOADED: {
        m_queueModel.setTracks(obj["tracks"].toArray(), obj["current_index"].toInt(-1));
        break;
    }
    case EVENT_PLAYLIST_PICKER: {
        emit playlistPickerResult(obj["id"].toString(), obj["stage"].toString(),
                                  obj["playlists"].toArray().toVariantList(), obj["message"].toString());
        break;
    }
    case EVENT_FEATURE: {
        const auto type = obj["type"].toString();
        if (type == "history") m_historyModel.setTracks(obj["tracks"].toArray(), -1);
        else if (type == "view") {
            m_collectionDownloadable = obj["downloadable"].toBool();
            m_activePlaylistKey = obj["playlist_key"].toString();
            m_activePlaylistPinned = obj["playlist_pinned"].toBool();
            m_isOwnPlaylist = obj["is_own_playlist"].toBool();
            m_collectionKind = obj["collection_kind"].toString();
            m_collectionLiked = obj["collection_liked"].toBool();
            if (obj.contains("audio_quality")) m_audioQuality = obj["audio_quality"].toString("hq");
            if (obj.contains("download_quality")) m_downloadQuality = obj["download_quality"].toString("mp3");
            if (obj.contains("normalize_volume")) m_normalizeVolume = obj["normalize_volume"].toBool(true);
            if (obj.contains("ai_music_behavior")) m_aiMusicBehavior = obj["ai_music_behavior"].toString("skip_if_not_liked");
            if (obj.contains("ai_strict_tracks")) m_aiStrictTracks = obj["ai_strict_tracks"].toBool(false);
            if (obj.contains("show_ai_labels")) m_showAiLabels = obj["show_ai_labels"].toBool(true);
        }
        else if (type == "search_suggest") {
            m_searchSuggestions = obj["suggestions"].toArray().toVariantList();
            m_searchQuickTracks = obj["tracks"].toArray().toVariantList();
            m_searchSuggestBest = obj["best"].isObject() ? obj["best"].toObject().toVariantMap() : QVariantMap();
            if (obj.contains("history")) m_searchHistory = obj["history"].toArray().toVariantList();
        }
        else if (type == "search_history") {
            m_searchHistory = obj["history"].toArray().toVariantList();
        }
        else if (type == "pinned_playlists") m_pinnedPlaylists = obj["playlists"].toArray().toVariantList();
        else if (type == "search") {
            m_searchQuery = obj["query"].toString();
            m_searchFilter = obj["filter"].toString("all");
            if (obj.contains("best")) {
                m_searchBest = obj["best"].isObject() ? obj["best"].toObject().toVariantMap() : QVariantMap();
            }
            if (obj.contains("has_more")) m_searchHasMore = obj["has_more"].toBool(false);
            if (obj.contains("loading_more")) m_searchLoadingMore = obj["loading_more"].toBool(false);
            if (obj.contains("history")) m_searchHistory = obj["history"].toArray().toVariantList();
        } else if (type == "hook_request") {
            const quint64 id = static_cast<quint64>(obj["id"].toInteger(0));
            const QString point = obj["point"].toString();
            const QVariant payload = obj["payload"].toVariant();
            emit hookRequestReceived(id, point, payload);
            break;
        } else if (type == "mod_warning") {
            emit modWarningReceived(obj["message"].toString());
            break;
        } else if (type == "batch") m_batch = obj.toVariantMap();
        else if (type == "wave_settings") m_waveSettings = obj.toVariantMap();
        else if (type == "wave_applied") m_waveSettings["selected"] = obj["selected"].toObject().toVariantMap();
        else if (type == "copy_track_link") copyText(obj["url"].toString());
        else if (type == "discord_status") {
            m_discordConnected = obj["connected"].toBool(false);
            m_discordStatus = obj["text"].toString();
            if (!m_discordConnected && obj["is_error"].toBool(false)) {
                qWarning().noquote() << "Discord RPC:" << m_discordStatus;
            }
        }
        else if (type == "lastfm_status") {
            m_lastfmHasBuiltinKeys = obj["has_builtin_keys"].toBool(false);
            m_lastfmConfigured = obj["configured"].toBool(false);
            m_lastfmConnected = obj["connected"].toBool(false);
            m_lastfmAuthorizing = obj["authorizing"].toBool(false);
            m_lastfmUsername = obj["username"].toString();
            m_lastfmStatus = obj["text"].toString();
            m_lastfmIsError = obj["is_error"].toBool(false);
            m_lastfmPendingCount = obj["pending_count"].toInt(0);
            m_lastfmEnabled = obj["enabled"].toBool(true);
            m_lastfmNowPlaying = obj["now_playing"].toBool(true);
            m_lastfmLoveOnLike = obj["love_on_like"].toBool(false);
            m_lastfmSkipAi = obj["skip_ai"].toBool(true);
            m_lastfmCustomApiKey = obj["custom_api_key"].toString();
            m_lastfmHasCustomSecret = obj["has_custom_secret"].toBool(false);
            const QString authUrl = obj["auth_url"].toString();
            if (!authUrl.isEmpty()) {
                QDesktopServices::openUrl(QUrl(authUrl));
            }
        }
        emit featuresChanged();
        emit featureResult(obj.toVariantMap());
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
        m_listCover = obj["cover_url"].toString();
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
    if (m_loginBusy) return;
    m_loginCode.clear();
    m_loginUrl.clear();
    clearStatus();
    m_loginBusy = true;
    emit authChanged();
    if (m_core) ymusic_core_login_device(m_core);
}

void YMusicBackend::loginToken(const QString &token) {
    if (token.trimmed().isEmpty()) return;
    clearStatus();
    m_loginCode.clear();
    m_loginUrl.clear();
    m_loginBusy = true;
    emit authChanged();
    if (m_core) ymusic_core_login_token(m_core, token.toUtf8().constData());
}

void YMusicBackend::cancelLogin() {
    m_loginCode.clear();
    m_loginUrl.clear();
    m_loginBusy = false;
    clearStatus();
    emit authChanged();
    if (m_core) ymusic_core_cancel_login(m_core);
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

void YMusicBackend::loadDownloads() {
    if (m_core) ymusic_core_load_downloads(m_core);
}

void YMusicBackend::loadPlaylistChoices(const QString &id) {
    if (m_core && m_loggedIn) ymusic_core_playlist_choices(m_core, id.toUtf8().constData());
}

void YMusicBackend::addToPlaylist(const QString &id, const QString &kind) {
    bool ok = false;
    const auto value = kind.toULongLong(&ok);
    if (ok && m_core && m_loggedIn) ymusic_core_add_to_playlist(m_core, id.toUtf8().constData(), value);
}

void YMusicBackend::removeDownload(const QString &id) {
    if (m_core) ymusic_core_remove_download(m_core, id.toUtf8().constData());
}

bool YMusicBackend::isDownloaded(const QString &id) const {
    QString base = qEnvironmentVariable("XDG_DATA_HOME");
    if (base.isEmpty()) base = QDir::homePath() + "/.local/share";
    QString safeId = id;
    for (QChar &ch : safeId) {
        if (!ch.isLetterOrNumber() && ch != u'_' && ch != u'-') {
            ch = u'_';
        }
    }
    if (!safeId.isEmpty()) {
        const QFileInfo bundleAudio(base + "/ymusic/offline/" + safeId + "/audio.mp3");
        if (bundleAudio.isFile() && bundleAudio.size() > 1024) {
            return true;
        }
    }
    const auto hash = QCryptographicHash::hash(id.toUtf8(), QCryptographicHash::Md5).toHex();
    const QFileInfo legacyInfo(base + "/ymusic/offline/" + QString::fromLatin1(hash) + ".mp3");
    return legacyInfo.isFile() && legacyInfo.size() > 1024;
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
    case 7: loadDownloads(); break;
    case 8: feature({{"action", "search"}, {"query", m_searchQuery}, {"filter", m_searchFilter}}); break;
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

void YMusicBackend::openArtist(const QString &artistId) {
    if (m_core && !artistId.isEmpty()) {
        ymusic_core_open_artist(m_core, artistId.toUtf8().constData());
    }
}

void YMusicBackend::openNowAlbum() {
    if (m_core) ymusic_core_open_now_album(m_core);
}

void YMusicBackend::setDiscordRpcEnabled(bool enabled) {
    if (m_core) ymusic_core_set_discord_enabled(m_core, enabled);
}

void YMusicBackend::setDiscordRpcConfig(bool enabled, const QString &display, const QString &activityType,
                                        bool showWhenPaused, bool showCover, bool showAlbum,
                                        bool showTimestamps, bool showButton) {
    if (!m_core) return;
    QJsonObject obj;
    obj.insert(QStringLiteral("enabled"), enabled);
    obj.insert(QStringLiteral("status_display"), display);
    obj.insert(QStringLiteral("activity_type"), activityType);
    obj.insert(QStringLiteral("show_when_paused"), showWhenPaused);
    obj.insert(QStringLiteral("show_cover"), showCover);
    obj.insert(QStringLiteral("show_album"), showAlbum);
    obj.insert(QStringLiteral("show_timestamps"), showTimestamps);
    obj.insert(QStringLiteral("show_button"), showButton);
    const QByteArray json = QJsonDocument(obj).toJson(QJsonDocument::Compact);
    ymusic_core_set_discord_config(m_core, json.constData());
}

void YMusicBackend::play(int index) {
    if (m_core) ymusic_core_play(m_core, index);
}

void YMusicBackend::trackAction(const QString &id, int action) {
    if (m_core) ymusic_core_track_action(m_core, id.toUtf8().constData(), action);
}

void YMusicBackend::saveOffline(const QString &id) {
    if (m_core) ymusic_core_download_track(m_core, id.toUtf8().constData(), "");
}

void YMusicBackend::downloadTrack(const QString &id, const QUrl &destination) {
    if (m_core && destination.isLocalFile())
        ymusic_core_download_track(m_core, id.toUtf8().constData(), destination.toLocalFile().toUtf8().constData());
}

void YMusicBackend::copyText(const QString &text) {
    QGuiApplication::clipboard()->setText(text);
}

QString YMusicBackend::clipboardText() const {
    return QGuiApplication::clipboard()->text();
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

void YMusicBackend::saveSession() {
    if (m_core) {
        ymusic_core_save_session(m_core);
    }
}

void YMusicBackend::feature(const QVariantMap &command) {
    if (m_core) ymusic_core_feature(m_core, QJsonDocument(QJsonObject::fromVariantMap(command)).toJson(QJsonDocument::Compact).constData());
}

void YMusicBackend::setTempo(qreal speed) {
    const qreal clamped = std::clamp(speed, 0.5, 2.0);
    if (!qFuzzyCompare(clamped + 1.0, m_tempo + 1.0)) {
        m_tempo = clamped;
        emit tempoChanged();
    }
    feature({{"action", "set_speed"}, {"speed", clamped}});
}

void YMusicBackend::startSleepTimer(int seconds, const QString &fadeMode) {
    cancelSleepTimer();
    if (seconds <= 0) return;
    m_sleepTimerDeadline = QDateTime::currentDateTimeUtc().addSecs(seconds);
    m_sleepTimerTotalSecs = seconds;
    m_sleepFade = ymusic::sleepFadeFromString(fadeMode);
    m_lastSleepFadeGain = 1.0;
    m_sleepTimer.start();
    emit sleepTimerChanged();
}

void YMusicBackend::cancelSleepTimer() {
    m_sleepTimer.stop();
    const bool wasRunning = m_sleepTimerDeadline.isValid();
    if (std::abs(m_lastSleepFadeGain - 1.0) > 1e-4) {
        m_lastSleepFadeGain = 1.0;
        feature({{"action", "set_sleep_fade"}, {"gain", 1.0}});
    }
    m_sleepTimerDeadline = {};
    m_sleepTimerTotalSecs = 0;
    m_sleepFade = ymusic::SleepFade::None;
    if (wasRunning) emit sleepTimerChanged();
}

void YMusicBackend::sleepTimerTick() {
    if (!m_sleepTimerDeadline.isValid()) {
        m_sleepTimer.stop();
        return;
    }
    const double remaining = QDateTime::currentDateTimeUtc().msecsTo(m_sleepTimerDeadline) / 1000.0;
    if (remaining > 0.0) {
        if (m_sleepFade != ymusic::SleepFade::None) {
            const double gain = ymusic::sleepFadeLevel(m_sleepFade, remaining, m_sleepTimerTotalSecs);
            if (std::abs(gain - m_lastSleepFadeGain) > 0.005) {
                m_lastSleepFadeGain = gain;
                feature({{"action", "set_sleep_fade"}, {"gain", gain}});
            }
        }
        return;
    }
    m_sleepTimer.stop();
    feature({{"action", "pause_playback"}});
    m_lastSleepFadeGain = 1.0;
    feature({{"action", "set_sleep_fade"}, {"gain", 1.0}});
    m_sleepTimerDeadline = {};
    m_sleepTimerTotalSecs = 0;
    m_sleepFade = ymusic::SleepFade::None;
    emit sleepTimerChanged();
}

void YMusicBackend::hookSubscribe(const QString &point, bool enabled) {
    if (!m_core) return;
    const QByteArray utf8 = point.toUtf8();
    ymusic_hook_subscribe(m_core, utf8.constData(), enabled);
}

void YMusicBackend::hookResponse(quint64 id, const QString &json) {
    if (!m_core) return;
    const QByteArray utf8 = json.toUtf8();
    ymusic_hook_response(m_core, static_cast<uint64_t>(id), utf8.constData());
}
