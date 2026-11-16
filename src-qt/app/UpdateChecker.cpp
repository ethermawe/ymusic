#include "UpdateChecker.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>

#include <algorithm>

#ifndef YMUSIC_APP_VERSION
#define YMUSIC_APP_VERSION "0.2.4"
#endif

namespace ymusic {
namespace {

constexpr QLatin1StringView kDefaultManifestUrl(
    "https://github.com/ethermawe/ymusic/releases/latest/download/latest-windows.json");
constexpr QLatin1StringView kDefaultReleasesUrl(
    "https://github.com/ethermawe/ymusic/releases");
constexpr int kStartupCheckDelayMs = 4000;
constexpr int kPeriodicCheckIntervalMs = 12 * 60 * 60 * 1000;

QString normalizeVersionString(QString v) {
    v = v.trimmed();
    if (v.startsWith(QLatin1Char('v'), Qt::CaseInsensitive)) {
        v.remove(0, 1);
    }
    return v;
}

bool isValidSha256Hex(const QString &hex) {
    if (hex.size() != 64) {
        return false;
    }
    for (const QChar ch : hex) {
        const ushort c = ch.unicode();
        const bool isDigit = c >= '0' && c <= '9';
        const bool isLowerHex = c >= 'a' && c <= 'f';
        const bool isUpperHex = c >= 'A' && c <= 'F';
        if (!isDigit && !isLowerHex && !isUpperHex) {
            return false;
        }
    }
    return true;
}

bool isGithubHost(const QString &host) {
    const QString lower = host.toLower();
    return lower == QLatin1String("github.com")
        || lower == QLatin1String("objects.githubusercontent.com")
        || lower == QLatin1String("release-assets.githubusercontent.com")
        || lower.endsWith(QLatin1String(".githubusercontent.com"));
}

QString sanitizeVersionForFilename(const QString &version) {
    QString out = version;
    out.replace(QRegularExpression(QStringLiteral("[^0-9A-Za-z._-]")), QStringLiteral("_"));
    return out.isEmpty() ? QStringLiteral("latest") : out;
}

} // namespace

UpdateChecker::UpdateChecker(QObject *parent)
    : QObject(parent)
    , m_currentVersion(normalizeVersionString(QStringLiteral(YMUSIC_APP_VERSION)))
    , m_releaseNotesUrl(QString(kDefaultReleasesUrl))
{
#ifdef Q_OS_WIN
    const QString appDir = QCoreApplication::applicationDirPath();
    m_installedCopy = !appDir.isEmpty()
        && QFileInfo::exists(appDir + QStringLiteral("/Uninstall.exe"));
#endif
    m_statusText = QStringLiteral("Версия v%1").arg(m_currentVersion);

    m_startupTimer.setSingleShot(true);
    m_startupTimer.setInterval(kStartupCheckDelayMs);
    connect(&m_startupTimer, &QTimer::timeout, this, [this]() {
        if (m_autoCheckEnabled && supported()) {
            checkForUpdates(false);
        }
    });

    m_periodicTimer.setInterval(kPeriodicCheckIntervalMs);
    connect(&m_periodicTimer, &QTimer::timeout, this, [this]() {
        if (m_autoCheckEnabled && supported()) {
            checkForUpdates(false);
        }
    });

    cleanupOldDownloads();
}

UpdateChecker::~UpdateChecker() {
    if (m_activeReply) {
        m_activeReply->abort();
    }
    if (m_downloadFile) {
        m_downloadFile->close();
        delete m_downloadFile;
        m_downloadFile = nullptr;
    }
}

bool UpdateChecker::supported() const {
    if (qEnvironmentVariableIntValue("YMUSIC_ENABLE_UPDATER") == 1) {
        return true;
    }
#ifdef Q_OS_WIN
    return true;
#else
    return false;
#endif
}

void UpdateChecker::startAutoCheck() {
    if (!supported() || !m_autoCheckEnabled) {
        return;
    }
    m_startupTimer.start();
    m_periodicTimer.start();
}

void UpdateChecker::setAutoCheckEnabled(bool enabled) {
    m_autoCheckEnabled = enabled;
    if (!supported()) {
        return;
    }
    if (enabled) {
        if (!m_periodicTimer.isActive()) {
            m_periodicTimer.start();
        }
    } else {
        m_startupTimer.stop();
        m_periodicTimer.stop();
    }
}

void UpdateChecker::checkForUpdates(bool userInitiated) {
    if (!supported()) {
        return;
    }
    if (m_state == Checking || m_state == Downloading) {
        return;
    }
    if (userInitiated) {
        m_bannerDismissedForSession = false;
    }

    setProgress(0.0);
    setState(Checking, QStringLiteral("Проверка обновлений…"));

    const QUrl manifestUrl = effectiveManifestUrl();
    QNetworkRequest req(manifestUrl);
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    req.setHeader(QNetworkRequest::UserAgentHeader,
                  QStringLiteral("ymusic/%1").arg(m_currentVersion));
    req.setTransferTimeout(15000);

    QNetworkReply *reply = m_nam.get(req);
    m_activeReply = reply;
    connect(reply, &QNetworkReply::finished, this, [this, reply, userInitiated]() {
        handleManifestReply(reply, userInitiated);
    });
}

void UpdateChecker::handleManifestReply(QNetworkReply *reply, bool userInitiated) {
    if (m_activeReply == reply) {
        m_activeReply.clear();
    }
    reply->deleteLater();

    if (reply->error() != QNetworkReply::NoError) {
        if (userInitiated) {
            setState(Error, QStringLiteral("Не удалось проверить обновления: %1").arg(reply->errorString()));
        } else {
            setState(Idle, QStringLiteral("Версия v%1").arg(m_currentVersion));
        }
        return;
    }

    QString parseError;
    const QUrl manifestUrl = effectiveManifestUrl();
    const auto parsed = parseManifest(reply->readAll(), manifestUrl, &parseError);
    if (!parsed) {
        if (userInitiated) {
            setState(Error, parseError);
        } else {
            setState(Idle, QStringLiteral("Версия v%1").arg(m_currentVersion));
        }
        return;
    }

    const ReleaseManifest &manifest = *parsed;
    if (!isNewerVersion(manifest.version, m_currentVersion)) {
        m_latestVersion = manifest.version;
        m_releaseNotesUrl = manifest.notesUrl.isValid() ? manifest.notesUrl : QUrl(QString(kDefaultReleasesUrl));
        setState(UpToDate, QStringLiteral("Установлена актуальная версия (v%1)").arg(m_currentVersion));
        return;
    }

    m_latestVersion = manifest.version;
    m_releaseNotesUrl = manifest.notesUrl.isValid() ? manifest.notesUrl : QUrl(QString(kDefaultReleasesUrl));

    if (!m_installedCopy) {
        setState(AvailablePortable, QStringLiteral("Доступна версия v%1").arg(manifest.version));
        if (!m_bannerDismissedForSession) {
            setBannerVisible(true);
        }
        return;
    }

    const QString finalPath = targetInstallerPath(manifest.version);
    if (!finalPath.isEmpty() && QFileInfo::exists(finalPath)) {
        if (fileSha256(finalPath).compare(manifest.sha256, Qt::CaseInsensitive) == 0) {
            m_downloadedPath = finalPath;
            cleanupOldDownloads(finalPath);
            setProgress(1.0);
            setState(Ready, QStringLiteral("Обновление v%1 готово к установке").arg(manifest.version));
            if (!m_bannerDismissedForSession) {
                setBannerVisible(true);
            }
            return;
        }
        QFile::remove(finalPath);
    }

    startDownload(manifest);
}

void UpdateChecker::startDownload(const ReleaseManifest &manifest) {
    const QString finalPath = targetInstallerPath(manifest.version);
    if (finalPath.isEmpty()) {
        setState(Error, QStringLiteral("Нет временного каталога для загрузки обновления."));
        return;
    }
    const QString partPath = finalPath + QStringLiteral(".part");
    QFile::remove(partPath);

    auto *file = new QFile(partPath);
    if (!file->open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        delete file;
        setState(Error, QStringLiteral("Не удалось создать файл обновления во временной папке."));
        return;
    }
    m_downloadFile = file;

    setProgress(0.0);
    setState(Downloading, QStringLiteral("Скачивание обновления v%1…").arg(manifest.version));

    QNetworkRequest req(manifest.url);
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    req.setHeader(QNetworkRequest::UserAgentHeader,
                  QStringLiteral("ymusic/%1").arg(m_currentVersion));
    req.setTransferTimeout(120000);

    QNetworkReply *reply = m_nam.get(req);
    m_activeReply = reply;

    connect(reply, &QNetworkReply::readyRead, this, [this, reply]() {
        if (m_downloadFile && reply->bytesAvailable() > 0) {
            if (m_downloadFile->write(reply->readAll()) < 0) {
                reply->abort();
            }
        }
    });
    connect(reply, &QNetworkReply::downloadProgress, this, [this, manifest](qint64 received, qint64 total) {
        if (total > 0) {
            const double ratio = std::clamp(static_cast<double>(received) / static_cast<double>(total), 0.0, 1.0);
            setProgress(ratio);
            const int pct = static_cast<int>(ratio * 100.0);
            m_statusText = QStringLiteral("Скачивание v%1 (%2%)…").arg(manifest.version).arg(pct);
            emit stateChanged();
        }
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply, manifest, partPath, finalPath]() {
        handleDownloadFinished(reply, manifest, partPath, finalPath);
    });
}

void UpdateChecker::handleDownloadFinished(
    QNetworkReply *reply,
    const ReleaseManifest &manifest,
    const QString &partPath,
    const QString &finalPath)
{
    if (m_activeReply == reply) {
        m_activeReply.clear();
    }
    reply->deleteLater();

    bool writeOk = true;
    if (m_downloadFile) {
        if (reply->bytesAvailable() > 0) {
            if (m_downloadFile->write(reply->readAll()) < 0) {
                writeOk = false;
            }
        }
        if (!m_downloadFile->flush()) {
            writeOk = false;
        }
        m_downloadFile->close();
        delete m_downloadFile;
        m_downloadFile = nullptr;
    } else {
        writeOk = false;
    }

    if (reply->error() != QNetworkReply::NoError || !writeOk) {
        QFile::remove(partPath);
        setProgress(0.0);
        setState(Error, QStringLiteral("Не удалось скачать обновление: %1").arg(reply->errorString()));
        return;
    }

    const QString actualSha = fileSha256(partPath);
    if (actualSha.isEmpty() || actualSha.compare(manifest.sha256, Qt::CaseInsensitive) != 0) {
        QFile::remove(partPath);
        setProgress(0.0);
        setState(Error, QStringLiteral("Контрольная сумма установщика не совпала."));
        return;
    }

    QFile::remove(finalPath);
    if (!QFile::rename(partPath, finalPath)) {
        QFile::remove(partPath);
        setProgress(0.0);
        setState(Error, QStringLiteral("Не удалось подготовить файл обновления к запуску."));
        return;
    }

    m_downloadedPath = finalPath;
    cleanupOldDownloads(finalPath);
    setProgress(1.0);
    setState(Ready, QStringLiteral("Обновление v%1 готово к установке").arg(manifest.version));
    if (!m_bannerDismissedForSession) {
        setBannerVisible(true);
    }
}

void UpdateChecker::installAndRestart() {
    if (m_state == AvailablePortable) {
        openReleasePage();
        return;
    }
    if (m_state != Ready || m_downloadedPath.isEmpty() || !QFileInfo::exists(m_downloadedPath)) {
        setState(Error, QStringLiteral("Файл обновления не найден."));
        return;
    }

    const QStringList args{QStringLiteral("/S"), QStringLiteral("/RELAUNCH")};
    if (!QProcess::startDetached(m_downloadedPath, args)) {
        setState(Error, QStringLiteral("Не удалось запустить установщик обновления."));
        return;
    }
    QCoreApplication::quit();
}

void UpdateChecker::openReleasePage() {
    const QUrl url = m_releaseNotesUrl.isValid()
        ? m_releaseNotesUrl
        : QUrl(QString(kDefaultReleasesUrl));
    if (url.scheme() == QLatin1String("https") && isGithubHost(url.host())) {
        QDesktopServices::openUrl(url);
    }
}

void UpdateChecker::dismissBanner() {
    m_bannerDismissedForSession = true;
    setBannerVisible(false);
}

std::optional<QVersionNumber> UpdateChecker::parseSemver(const QString &raw, bool *isPreRelease) {
    QString s = normalizeVersionString(raw);
    if (s.isEmpty()) {
        return std::nullopt;
    }
    const qsizetype plusIdx = s.indexOf(QLatin1Char('+'));
    if (plusIdx >= 0) {
        s.truncate(plusIdx);
    }
    const qsizetype dashIdx = s.indexOf(QLatin1Char('-'));
    if (isPreRelease) {
        *isPreRelease = dashIdx >= 0;
    }
    if (dashIdx >= 0) {
        s.truncate(dashIdx);
    }

    qsizetype suffixIndex = 0;
    const QVersionNumber ver = QVersionNumber::fromString(s, &suffixIndex);
    if (ver.isNull() || suffixIndex != s.size()) {
        return std::nullopt;
    }
    return ver.normalized();
}

bool UpdateChecker::isNewerVersion(const QString &candidate, const QString &current) {
    bool candidatePre = false;
    bool currentPre = false;
    const auto candVer = parseSemver(candidate, &candidatePre);
    const auto currVer = parseSemver(current, &currentPre);
    if (!candVer || !currVer) {
        return false;
    }
    const int cmp = QVersionNumber::compare(*candVer, *currVer);
    if (cmp != 0) {
        return cmp > 0;
    }
    // Stable 0.2.3 is newer than pre-release 0.2.3-rc1, but never auto-upgrade stable to pre-release.
    return currentPre && !candidatePre;
}

bool UpdateChecker::isAllowedAssetUrl(const QUrl &assetUrl, const QUrl &manifestUrl) {
    if (!assetUrl.isValid()) {
        return false;
    }
    if (qEnvironmentVariableIsSet("YMUSIC_UPDATE_URL")
        && (manifestUrl.host() == QLatin1String("127.0.0.1")
            || manifestUrl.host() == QLatin1String("localhost")))
    {
        return assetUrl.scheme() == manifestUrl.scheme()
            && assetUrl.host() == manifestUrl.host()
            && assetUrl.port() == manifestUrl.port();
    }
    if (assetUrl.scheme() != QLatin1String("https") || !isGithubHost(assetUrl.host())) {
        return false;
    }
    if (assetUrl.host().compare(QLatin1String("github.com"), Qt::CaseInsensitive) == 0) {
        return assetUrl.path().startsWith(QLatin1String("/ethermawe/ymusic/"));
    }
    return true;
}

std::optional<ReleaseManifest> UpdateChecker::parseManifest(
    const QByteArray &json,
    const QUrl &manifestUrl,
    QString *errorOut)
{
    QJsonParseError err{};
    const QJsonDocument doc = QJsonDocument::fromJson(json, &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject()) {
        if (errorOut) *errorOut = QStringLiteral("Некорректный формат манифеста обновлений.");
        return std::nullopt;
    }
    const QJsonObject obj = doc.object();
    const QString version = normalizeVersionString(obj.value(QStringLiteral("version")).toString());
    if (!parseSemver(version)) {
        if (errorOut) *errorOut = QStringLiteral("В манифесте обновлений неверная версия.");
        return std::nullopt;
    }
    const QUrl url(obj.value(QStringLiteral("url")).toString().trimmed());
    if (!isAllowedAssetUrl(url, manifestUrl)) {
        if (errorOut) *errorOut = QStringLiteral("Недопустимый URL установщика обновления.");
        return std::nullopt;
    }
    const QString sha256 = obj.value(QStringLiteral("sha256")).toString().trimmed().toLower();
    if (!isValidSha256Hex(sha256)) {
        if (errorOut) *errorOut = QStringLiteral("В манифесте отсутствует корректный SHA-256.");
        return std::nullopt;
    }
    const QString tag = obj.value(QStringLiteral("tag")).toString().trimmed();
    const QUrl notesUrl(obj.value(QStringLiteral("notes_url")).toString().trimmed());
    return ReleaseManifest{
        version,
        tag.isEmpty() ? (QStringLiteral("v") + version) : tag,
        url,
        sha256,
        notesUrl,
    };
}

QString UpdateChecker::fileSha256(const QString &path) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return QString();
    }
    QCryptographicHash hash(QCryptographicHash::Sha256);
    if (!hash.addData(&file)) {
        return QString();
    }
    return QString::fromLatin1(hash.result().toHex());
}

void UpdateChecker::setState(State state, const QString &statusText) {
    m_state = state;
    m_statusText = statusText;
    emit stateChanged();
}

void UpdateChecker::setProgress(double progress) {
    if (!qFuzzyCompare(m_progress + 1.0, progress + 1.0)) {
        m_progress = progress;
        emit progressChanged();
    }
}

void UpdateChecker::setBannerVisible(bool visible) {
    if (m_bannerVisible != visible) {
        m_bannerVisible = visible;
        emit bannerChanged();
    }
}

QUrl UpdateChecker::effectiveManifestUrl() const {
    const QString env = qEnvironmentVariable("YMUSIC_UPDATE_URL").trimmed();
    if (!env.isEmpty()) {
        const QUrl custom(env);
        if (custom.isValid()) {
            return custom;
        }
    }
    return QUrl(QString(kDefaultManifestUrl));
}

QString UpdateChecker::targetInstallerPath(const QString &version) const {
    const QString tempDir = QStandardPaths::writableLocation(QStandardPaths::TempLocation);
    if (tempDir.isEmpty()) {
        return QString();
    }
    return QDir(tempDir).filePath(
        QStringLiteral("ymusic-update-%1.exe").arg(sanitizeVersionForFilename(version)));
}

void UpdateChecker::cleanupOldDownloads(const QString &keepPath) const {
    const QString tempDir = QStandardPaths::writableLocation(QStandardPaths::TempLocation);
    if (tempDir.isEmpty()) {
        return;
    }
    QDir dir(tempDir);
    const QStringList entries = dir.entryList(
        {QStringLiteral("ymusic-update-*.exe"), QStringLiteral("ymusic-update-*.exe.part")},
        QDir::Files);
    for (const QString &name : entries) {
        const QString fullPath = dir.filePath(name);
        if (keepPath.isEmpty() || QFileInfo(fullPath) != QFileInfo(keepPath)) {
            QFile::remove(fullPath);
        }
    }
}

} // namespace ymusic
