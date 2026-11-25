#include "mods/ModApi.h"

#include "app/Paths.h"
#include "mods/ModManager.h"
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
#include "TrackModel.h"
#include "YMusicBackend.h"
#include "render/SpectrumSource.h"
#endif

#include <QClipboard>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonValue>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSaveFile>
#include <QUrl>

#include <algorithm>

namespace ymusic::mods {

namespace {
constexpr qint64 kMaxHttpBytes = 4 * 1024 * 1024;
constexpr int kHttpTimeoutMs = 15000;

#ifndef YMUSIC_MOD_TEST_NO_BACKEND
QVariantList snapshotTrackModel(TrackModel *model)
{
    QVariantList out;
    if (!model) return out;
    const int n = model->rowCount();
    out.reserve(n);
    for (int i = 0; i < n; ++i) {
        const QModelIndex idx = model->index(i, 0);
        QVariantMap row;
        row.insert(QStringLiteral("id"), model->data(idx, TrackModel::IdRole));
        row.insert(QStringLiteral("title"), model->data(idx, TrackModel::TitleRole));
        row.insert(QStringLiteral("artists"), model->data(idx, TrackModel::ArtistsRole));
        row.insert(QStringLiteral("album"), model->data(idx, TrackModel::AlbumRole));
        row.insert(QStringLiteral("duration"), model->data(idx, TrackModel::DurationRole));
        row.insert(QStringLiteral("durationMs"), model->data(idx, TrackModel::DurationMsRole));
        row.insert(QStringLiteral("available"), model->data(idx, TrackModel::AvailableRole));
        row.insert(QStringLiteral("liked"), model->data(idx, TrackModel::LikedRole));
        row.insert(QStringLiteral("downloaded"), model->data(idx, TrackModel::DownloadedRole));
        row.insert(QStringLiteral("coverUrl"), model->data(idx, TrackModel::CoverUrlRole));
        row.insert(QStringLiteral("isAi"), model->data(idx, TrackModel::IsAiRole));
        out.append(row);
    }
    return out;
}
#endif

} // namespace

ModApi::ModApi(ModManifest manifest,
               ModManager *manager,
               YMusicBackend *backend,
               ymusic::SpectrumSource *spectrum,
               QObject *parent)
    : QObject(parent)
    , m_manifest(std::move(manifest))
    , m_manager(manager)
    , m_backend(backend)
    , m_spectrum(spectrum)
{
    if (hasPermission(QStringLiteral("storage"))) {
        loadStorage();
    }

    if (m_manager && hasPermission(QStringLiteral("ui:slots"))) {
        for (const ModShortcutDef &sc : m_manifest.shortcuts) {
            m_manager->registerShortcut(m_manifest.id, sc.id, sc.sequence, sc.description);
        }
    }

#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    if (m_backend && hasPermission(QStringLiteral("playback:read"))) {
        connect(m_backend, &YMusicBackend::nowPlayingChanged, this, &ModApi::trackChanged);
        connect(m_backend, &YMusicBackend::playbackStateChanged, this, &ModApi::playbackChanged);
        connect(m_backend, &YMusicBackend::volumeChanged, this, &ModApi::playbackChanged);
        connect(m_backend, &YMusicBackend::tempoChanged, this, &ModApi::playbackChanged);
        connect(m_backend, &YMusicBackend::progressChanged, this, &ModApi::positionChanged);
    }

    if (m_backend && (hasPermission(QStringLiteral("ui:slots")) || hasPermission(QStringLiteral("playback:read")))) {
        connect(m_backend, &YMusicBackend::viewHeaderChanged, this, &ModApi::navigationChanged);
        connect(m_backend, &YMusicBackend::authChanged, this, &ModApi::navigationChanged);
    }

    if (m_backend && (hasPermission(QStringLiteral("library:read")) || hasPermission(QStringLiteral("ui:slots")))) {
        connect(m_backend, &YMusicBackend::featuresChanged, this, &ModApi::libraryChanged);
        if (m_backend->queue()) {
            connect(m_backend->queue(), &TrackModel::countChanged, this, &ModApi::libraryChanged);
        }
        if (m_backend->tracks()) {
            connect(m_backend->tracks(), &TrackModel::countChanged, this, &ModApi::libraryChanged);
        }
    }

    if (m_spectrum && hasPermission(QStringLiteral("spectrum:read"))) {
        connect(m_spectrum, &ymusic::SpectrumSource::levelsChanged, this, &ModApi::spectrumUpdated);
    }
#endif
}

ModApi::~ModApi()
{
    if (m_manager) {
        m_manager->clearTrackMenuActionsForMod(m_manifest.id);
        m_manager->clearShortcutsForMod(m_manifest.id);
        m_manager->clearLyricSubtitlesForMod(m_manifest.id);
    }
}

bool ModApi::hasPermission(const QString &perm) const
{
    return m_manifest.hasPermission(perm);
}

bool ModApi::requirePermission(const QString &perm, const char *actionName)
{
    if (hasPermission(perm)) {
        return true;
    }
    warn(QStringLiteral("Отказ в доступе (%1): требуется разрешение '%2'")
             .arg(QLatin1StringView(actionName), perm));
    return false;
}

bool ModApi::hasTrack() const
{
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    return m_backend && hasPermission(QStringLiteral("playback:read")) && m_backend->hasTrack();
#else
    return false;
#endif
}

QString ModApi::trackId() const
{
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    return hasTrack() ? m_backend->nowId() : QString();
#else
    return {};
#endif
}

QString ModApi::trackTitle() const
{
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    return hasTrack() ? m_backend->nowTitle() : QString();
#else
    return {};
#endif
}

QString ModApi::trackArtists() const
{
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    return hasTrack() ? m_backend->nowArtists() : QString();
#else
    return {};
#endif
}

QString ModApi::trackAlbum() const
{
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    return hasTrack() ? m_backend->nowAlbum() : QString();
#else
    return {};
#endif
}

QString ModApi::trackCover() const
{
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    return hasTrack() ? m_backend->nowCover() : QString();
#else
    return {};
#endif
}

bool ModApi::trackLiked() const
{
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    return hasTrack() && m_backend->nowLiked();
#else
    return false;
#endif
}

bool ModApi::trackIsAi() const
{
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    return hasTrack() && m_backend->nowIsAi();
#else
    return false;
#endif
}

bool ModApi::playing() const
{
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    return m_backend && hasPermission(QStringLiteral("playback:read")) && m_backend->playing();
#else
    return false;
#endif
}

bool ModApi::buffering() const
{
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    return m_backend && hasPermission(QStringLiteral("playback:read")) && m_backend->buffering();
#else
    return false;
#endif
}

qreal ModApi::volume() const
{
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    return (m_backend && hasPermission(QStringLiteral("playback:read"))) ? m_backend->volume() : 0.0;
#else
    return 0.0;
#endif
}

bool ModApi::shuffle() const
{
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    return m_backend && hasPermission(QStringLiteral("playback:read")) && m_backend->shuffle();
#else
    return false;
#endif
}

int ModApi::repeatMode() const
{
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    return (m_backend && hasPermission(QStringLiteral("playback:read"))) ? m_backend->repeatMode() : 0;
#else
    return 0;
#endif
}

qreal ModApi::tempo() const
{
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    return (m_backend && hasPermission(QStringLiteral("playback:read"))) ? m_backend->tempo() : 1.0;
#else
    return 1.0;
#endif
}

qreal ModApi::positionSecs() const
{
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    return (m_backend && hasPermission(QStringLiteral("playback:read"))) ? m_backend->positionSecs() : 0.0;
#else
    return 0.0;
#endif
}

qreal ModApi::durationSecs() const
{
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    return (m_backend && hasPermission(QStringLiteral("playback:read"))) ? m_backend->durationSecs() : 0.0;
#else
    return 0.0;
#endif
}

qreal ModApi::progress() const
{
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    return (m_backend && hasPermission(QStringLiteral("playback:read"))) ? m_backend->progress() : 0.0;
#else
    return 0.0;
#endif
}

int ModApi::currentPage() const
{
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    return (m_backend && (hasPermission(QStringLiteral("ui:slots")) || hasPermission(QStringLiteral("playback:read"))))
        ? m_backend->page() : 0;
#else
    return 0;
#endif
}

bool ModApi::canGoBack() const
{
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    return m_backend && (hasPermission(QStringLiteral("ui:slots")) || hasPermission(QStringLiteral("playback:read")))
        && m_backend->canGoBack();
#else
    return false;
#endif
}

bool ModApi::loggedIn() const
{
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    return m_backend && (hasPermission(QStringLiteral("ui:slots")) || hasPermission(QStringLiteral("playback:read")))
        && m_backend->loggedIn();
#else
    return false;
#endif
}

QString ModApi::userName() const
{
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    return loggedIn() ? m_backend->userName() : QString();
#else
    return {};
#endif
}

QString ModApi::userAvatar() const
{
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    return (loggedIn() && m_backend->userHasAvatar()) ? m_backend->userAvatar() : QString();
#else
    return {};
#endif
}

QVariantList ModApi::pinnedPlaylists() const
{
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    if (m_backend && (hasPermission(QStringLiteral("library:read")) || hasPermission(QStringLiteral("ui:slots")))) {
        return m_backend->pinnedPlaylists();
    }
#endif
    return {};
}

QString ModApi::lyricsTrackId() const
{
    return (m_manager && hasPermission(QStringLiteral("lyrics:read"))) ? m_manager->lyricsTrackId() : QString();
}

bool ModApi::lyricsSynced() const
{
    return m_manager && hasPermission(QStringLiteral("lyrics:read")) && m_manager->lyricsSynced();
}

QVariantList ModApi::lyricsLines() const
{
    return (m_manager && hasPermission(QStringLiteral("lyrics:read"))) ? m_manager->lyricsLines() : QVariantList();
}

bool ModApi::toggle()
{
    if (!requirePermission(QStringLiteral("playback:control"), "toggle") || !m_backend) return false;
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    m_backend->toggle();
#endif
    return true;
}

bool ModApi::next()
{
    if (!requirePermission(QStringLiteral("playback:control"), "next") || !m_backend) return false;
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    m_backend->next();
#endif
    return true;
}

bool ModApi::prev()
{
    if (!requirePermission(QStringLiteral("playback:control"), "prev") || !m_backend) return false;
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    m_backend->prev();
#endif
    return true;
}

bool ModApi::seek(qreal normalizedProgress)
{
    if (!requirePermission(QStringLiteral("playback:control"), "seek") || !m_backend) return false;
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    m_backend->seek(std::clamp(normalizedProgress, 0.0, 1.0));
#else
    Q_UNUSED(normalizedProgress);
#endif
    return true;
}

bool ModApi::setVolume(qreal value)
{
    if (!requirePermission(QStringLiteral("playback:control"), "setVolume") || !m_backend) return false;
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    m_backend->setVolume(std::clamp(value, 0.0, 1.0));
#else
    Q_UNUSED(value);
#endif
    return true;
}

bool ModApi::toggleLike()
{
    if (!requirePermission(QStringLiteral("playback:control"), "toggleLike") || !m_backend) return false;
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    m_backend->toggleNowLike();
#endif
    return true;
}

bool ModApi::playNext(const QString &trackId)
{
    if (!requirePermission(QStringLiteral("playback:control"), "playNext") || !m_backend || trackId.isEmpty()) return false;
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    m_backend->trackAction(trackId, 0);
#endif
    return true;
}

bool ModApi::addToQueue(const QString &trackId)
{
    if (!requirePermission(QStringLiteral("playback:control"), "addToQueue") || !m_backend || trackId.isEmpty()) return false;
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    m_backend->trackAction(trackId, 1);
#endif
    return true;
}

bool ModApi::openHome()
{
    if (!requirePermission(QStringLiteral("ui:slots"), "openHome") || !m_backend) return false;
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    m_backend->loadHome();
#endif
    return true;
}

bool ModApi::openWave()
{
    if (!requirePermission(QStringLiteral("ui:slots"), "openWave") || !m_backend) return false;
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    m_backend->startWave();
#endif
    return true;
}

bool ModApi::openLikes()
{
    if (!requirePermission(QStringLiteral("ui:slots"), "openLikes") || !m_backend) return false;
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    m_backend->loadLikes();
#endif
    return true;
}

bool ModApi::openDownloads()
{
    if (!requirePermission(QStringLiteral("ui:slots"), "openDownloads") || !m_backend) return false;
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    m_backend->loadDownloads();
#endif
    return true;
}

bool ModApi::openPlaylists()
{
    if (!requirePermission(QStringLiteral("ui:slots"), "openPlaylists") || !m_backend) return false;
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    m_backend->loadPlaylists();
#endif
    return true;
}

bool ModApi::openAlbums()
{
    if (!requirePermission(QStringLiteral("ui:slots"), "openAlbums") || !m_backend) return false;
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    m_backend->loadAlbums();
#endif
    return true;
}

bool ModApi::openArtists()
{
    if (!requirePermission(QStringLiteral("ui:slots"), "openArtists") || !m_backend) return false;
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    m_backend->loadArtists();
#endif
    return true;
}

bool ModApi::openSearch(const QString &query)
{
    if (!requirePermission(QStringLiteral("ui:slots"), "openSearch") || !m_backend || query.trimmed().isEmpty()) return false;
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    m_backend->search(query.trimmed());
#endif
    return true;
}

bool ModApi::openPlaylist(const QString &uid, const QString &kind, const QString &title)
{
    if (!requirePermission(QStringLiteral("ui:slots"), "openPlaylist") || !m_backend || kind.isEmpty()) return false;
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    m_backend->feature({
        {QStringLiteral("action"), QStringLiteral("open_playlist")},
        {QStringLiteral("uid"), uid},
        {QStringLiteral("kind"), kind},
        {QStringLiteral("title"), title.isEmpty() ? QStringLiteral("Плейлист") : title},
    });
#else
    Q_UNUSED(uid);
    Q_UNUSED(title);
#endif
    return true;
}

bool ModApi::goBack()
{
    if (!requirePermission(QStringLiteral("ui:slots"), "goBack") || !m_backend) return false;
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    m_backend->goBack();
#endif
    return true;
}

bool ModApi::openCreatePlaylist()
{
    if (!requirePermission(QStringLiteral("ui:slots"), "openCreatePlaylist") || !m_manager) return false;
    emit m_manager->createPlaylistRequested();
    return true;
}

QVariantList ModApi::queueTracks() const
{
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    if (m_backend && hasPermission(QStringLiteral("library:read"))) {
        return snapshotTrackModel(m_backend->queue());
    }
#endif
    return {};
}

QVariantList ModApi::currentTracks() const
{
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    if (m_backend && hasPermission(QStringLiteral("library:read"))) {
        return snapshotTrackModel(m_backend->tracks());
    }
#endif
    return {};
}

QVariantList ModApi::historyTracks() const
{
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    if (m_backend && hasPermission(QStringLiteral("library:read"))) {
        return snapshotTrackModel(m_backend->history());
    }
#endif
    return {};
}

bool ModApi::setLyricSubtitles(const QString &trackId, const QVariantList &subtitles)
{
    if (!requirePermission(QStringLiteral("lyrics:transform"), "setLyricSubtitles") || !m_manager || trackId.isEmpty()) {
        return false;
    }
    QStringList lines;
    lines.reserve(subtitles.size());
    for (const QVariant &v : subtitles) {
        lines.append(v.toString());
    }
    m_manager->setLyricSubtitles(m_manifest.id, trackId, lines);
    return true;
}

void ModApi::clearLyricSubtitles()
{
    if (m_manager) {
        m_manager->clearLyricSubtitlesForMod(m_manifest.id);
    }
}

QVariantList ModApi::spectrumLevels() const
{
    QVariantList out;
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    if (!m_spectrum || !hasPermission(QStringLiteral("spectrum:read"))) {
        return out;
    }
    const QList<float> &levels = m_spectrum->levels();
    out.reserve(levels.size());
    for (float v : levels) {
        out.append(static_cast<double>(v));
    }
#endif
    return out;
}

QVariantList ModApi::spectrumEnergies() const
{
    QVariantList out;
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    if (!m_spectrum || !hasPermission(QStringLiteral("spectrum:read"))) {
        return out;
    }
    const auto energies = m_spectrum->energies();
    out.reserve(static_cast<qsizetype>(energies.size()));
    for (float v : energies) {
        out.append(static_cast<double>(v));
    }
#endif
    return out;
}

QString ModApi::storageFilePath() const
{
    return ymusic::paths::modDataDirectory() + u'/' + m_manifest.id + QStringLiteral(".json");
}

void ModApi::loadStorage()
{
    QFile file(storageFilePath());
    if (!file.open(QIODevice::ReadOnly)) return;
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (doc.isObject()) {
        m_storage = doc.object();
    }
}

bool ModApi::saveStorage() const
{
    QDir().mkpath(ymusic::paths::modDataDirectory());
    QSaveFile file(storageFilePath());
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return false;
    }
    file.write(QJsonDocument(m_storage).toJson(QJsonDocument::Indented));
    return file.commit();
}

QVariant ModApi::storageGet(const QString &key, const QVariant &fallback) const
{
    if (!hasPermission(QStringLiteral("storage")) || !m_storage.contains(key)) {
        return fallback;
    }
    return m_storage.value(key).toVariant();
}

bool ModApi::storageSet(const QString &key, const QVariant &value)
{
    if (!requirePermission(QStringLiteral("storage"), "storageSet") || key.isEmpty()) {
        return false;
    }
    m_storage.insert(key, QJsonValue::fromVariant(value));
    return saveStorage();
}

bool ModApi::storageRemove(const QString &key)
{
    if (!requirePermission(QStringLiteral("storage"), "storageRemove") || key.isEmpty()) {
        return false;
    }
    m_storage.remove(key);
    return saveStorage();
}

QVariantMap ModApi::storageAll() const
{
    if (!hasPermission(QStringLiteral("storage"))) {
        return {};
    }
    return m_storage.toVariantMap();
}

bool ModApi::showToast(const QString &message)
{
    if (!requirePermission(QStringLiteral("ui:slots"), "showToast") || !m_manager) {
        return false;
    }
    const QString trimmed = message.trimmed();
    if (trimmed.isEmpty()) return false;
    emit m_manager->toastRequested(trimmed.left(200));
    return true;
}

bool ModApi::openImmersive()
{
    if (!requirePermission(QStringLiteral("ui:slots"), "openImmersive") || !m_manager) {
        return false;
    }
    emit m_manager->immersiveRequested(true);
    return true;
}

bool ModApi::closeImmersive()
{
    if (!requirePermission(QStringLiteral("ui:slots"), "closeImmersive") || !m_manager) {
        return false;
    }
    emit m_manager->immersiveRequested(false);
    return true;
}

bool ModApi::openSettings()
{
    if (!requirePermission(QStringLiteral("ui:slots"), "openSettings") || !m_manager) {
        return false;
    }
    emit m_manager->settingsRequested();
    return true;
}

bool ModApi::registerTrackMenuAction(const QString &actionId,
                                     const QString &label,
                                     const QString &symbol,
                                     bool destructive)
{
    if (!requirePermission(QStringLiteral("ui:slots"), "registerTrackMenuAction") || !m_manager) {
        return false;
    }
    if (actionId.trimmed().isEmpty() || label.trimmed().isEmpty()) {
        return false;
    }
    m_manager->registerTrackMenuAction(m_manifest.id, actionId.trimmed(), label.trimmed(),
                                       symbol.trimmed().isEmpty() ? QStringLiteral("extension") : symbol.trimmed(),
                                       destructive);
    return true;
}

void ModApi::unregisterTrackMenuAction(const QString &actionId)
{
    if (m_manager) {
        m_manager->unregisterTrackMenuAction(m_manifest.id, actionId.trimmed());
    }
}

bool ModApi::registerShortcut(const QString &actionId, const QString &sequence, const QString &description)
{
    if (!requirePermission(QStringLiteral("ui:slots"), "registerShortcut") || !m_manager) {
        return false;
    }
    if (actionId.trimmed().isEmpty() || sequence.trimmed().isEmpty()) {
        return false;
    }
    m_manager->registerShortcut(m_manifest.id, actionId.trimmed(), sequence.trimmed(), description.trimmed());
    return true;
}

void ModApi::unregisterShortcut(const QString &actionId)
{
    if (m_manager) {
        m_manager->unregisterShortcut(m_manifest.id, actionId.trimmed());
    }
}

bool ModApi::copyText(const QString &text)
{
    if (!requirePermission(QStringLiteral("clipboard"), "copyText")) {
        return false;
    }
    if (QClipboard *cb = QGuiApplication::clipboard()) {
        cb->setText(text);
        return true;
    }
    return false;
}

bool ModApi::openExternalUrl(const QString &url)
{
    if (!requirePermission(QStringLiteral("ui:slots"), "openExternalUrl")) {
        return false;
    }
    const QUrl parsed(url.trimmed());
    const QString scheme = parsed.scheme().toLower();
    if (!parsed.isValid() || (scheme != QLatin1StringView("https") && scheme != QLatin1StringView("http"))) {
        warn(QStringLiteral("Заблокировано открытие небезопасного URL: %1").arg(url));
        return false;
    }
    return QDesktopServices::openUrl(parsed);
}

bool ModApi::httpGet(const QString &url, const QString &requestId)
{
    return httpRequest(QStringLiteral("GET"), url, {}, {}, requestId);
}

bool ModApi::httpRequest(const QString &method,
                         const QString &url,
                         const QVariantMap &headers,
                         const QString &body,
                         const QString &requestId)
{
    const QString upperMethod = method.trimmed().toUpper();
    if (upperMethod != QLatin1StringView("GET") && upperMethod != QLatin1StringView("POST")
        && upperMethod != QLatin1StringView("PUT") && upperMethod != QLatin1StringView("PATCH")
        && upperMethod != QLatin1StringView("DELETE")) {
        warn(QStringLiteral("Неподдерживаемый HTTP-метод: %1").arg(method));
        return false;
    }

    const QUrl parsed(url.trimmed());
    const QString scheme = parsed.scheme().toLower();
    const QString host = parsed.host().toLower();
    const bool localHttp = (scheme == QLatin1StringView("http"))
        && (host == QLatin1StringView("127.0.0.1") || host == QLatin1StringView("localhost"));
    if (!parsed.isValid() || (scheme != QLatin1StringView("https") && !localHttp)) {
        warn(QStringLiteral("httpRequest поддерживает только HTTPS (или localhost HTTP): %1").arg(url));
        return false;
    }
    if (!m_manifest.allowsNetworkHost(host)) {
        warn(QStringLiteral("Отказ в сети: требуется разрешение 'network:%1'").arg(host));
        return false;
    }

    if (!m_network) {
        m_network = new QNetworkAccessManager(this);
    }

    QNetworkRequest req(parsed);
    req.setTransferTimeout(kHttpTimeoutMs);
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("ymusic-mod/%1").arg(m_manifest.id));
    req.setAttribute(QNetworkRequest::CookieLoadControlAttribute, QNetworkRequest::Manual);
    req.setAttribute(QNetworkRequest::CookieSaveControlAttribute, QNetworkRequest::Manual);

    for (auto it = headers.constBegin(); it != headers.constEnd(); ++it) {
        const QString keyLower = it.key().trimmed().toLower();
        if (keyLower.isEmpty() || keyLower == QLatin1StringView("host")
            || keyLower == QLatin1StringView("cookie") || keyLower == QLatin1StringView("content-length")) {
            continue;
        }
        req.setRawHeader(it.key().trimmed().toUtf8(), it.value().toString().toUtf8());
    }

    QNetworkReply *reply = nullptr;
    const QByteArray payload = body.toUtf8();
    if (upperMethod == QLatin1StringView("GET")) {
        reply = m_network->get(req);
    } else if (upperMethod == QLatin1StringView("POST")) {
        reply = m_network->post(req, payload);
    } else if (upperMethod == QLatin1StringView("PUT")) {
        reply = m_network->put(req, payload);
    } else if (upperMethod == QLatin1StringView("DELETE")) {
        reply = m_network->deleteResource(req);
    } else {
        reply = m_network->sendCustomRequest(req, upperMethod.toUtf8(), payload);
    }

    reply->setParent(this);
    connect(reply, &QNetworkReply::finished, this, [this, reply, requestId]() {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray data = reply->read(kMaxHttpBytes);
        const QString err = reply->error() == QNetworkReply::NoError ? QString() : reply->errorString();
        reply->deleteLater();
        emit httpFinished(requestId, status, QString::fromUtf8(data), err);
    });
    return true;
}

void ModApi::log(const QString &message)
{
    if (m_manager) {
        m_manager->appendLog(m_manifest.id, QStringLiteral("info"), message);
    }
}

void ModApi::warn(const QString &message)
{
    if (m_manager) {
        m_manager->appendLog(m_manifest.id, QStringLiteral("warn"), message);
    }
}

void ModApi::notifyTrackMenuAction(const QString &actionId, const QString &trackId, const QString &trackTitle)
{
    emit trackMenuActionTriggered(actionId, trackId, trackTitle);
}

void ModApi::notifyShortcut(const QString &actionId)
{
    emit shortcutTriggered(actionId);
}

void ModApi::notifyLyricsChanged()
{
    if (hasPermission(QStringLiteral("lyrics:read"))) {
        emit lyricsChanged();
    }
}

} // namespace ymusic::mods
