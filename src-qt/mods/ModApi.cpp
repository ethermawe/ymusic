#include "mods/ModApi.h"

#include "app/Paths.h"
#include "mods/ModManager.h"
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
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
#include <QTimer>
#include <QUrl>

#include <algorithm>

namespace ymusic::mods {

namespace {
constexpr qint64 kMaxHttpBytes = 4 * 1024 * 1024;
constexpr int kHttpTimeoutMs = 15000;
}

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

#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    if (m_backend && hasPermission(QStringLiteral("playback:read"))) {
        connect(m_backend, &YMusicBackend::nowPlayingChanged, this, &ModApi::trackChanged);
        connect(m_backend, &YMusicBackend::playbackStateChanged, this, &ModApi::playbackChanged);
        connect(m_backend, &YMusicBackend::volumeChanged, this, &ModApi::playbackChanged);
        connect(m_backend, &YMusicBackend::tempoChanged, this, &ModApi::playbackChanged);
        connect(m_backend, &YMusicBackend::progressChanged, this, &ModApi::positionChanged);
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
    const QUrl parsed(url.trimmed());
    const QString scheme = parsed.scheme().toLower();
    const QString host = parsed.host().toLower();
    const bool localHttp = (scheme == QLatin1StringView("http"))
        && (host == QLatin1StringView("127.0.0.1") || host == QLatin1StringView("localhost"));
    if (!parsed.isValid() || (scheme != QLatin1StringView("https") && !localHttp)) {
        warn(QStringLiteral("httpGet поддерживает только HTTPS (или localhost HTTP): %1").arg(url));
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

    QNetworkReply *reply = m_network->get(req);
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

} // namespace ymusic::mods
