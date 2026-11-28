#include "mods/ModNetworkAccessManager.h"

#include <QDir>
#include <QFileInfo>
#include <QLoggingCategory>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QTimer>

namespace ymusic::mods {

Q_DECLARE_LOGGING_CATEGORY(lcMods)

namespace {

class BlockedNetworkReply final : public QNetworkReply {
public:
    BlockedNetworkReply(QNetworkAccessManager::Operation op,
                        const QNetworkRequest &req,
                        const QString &reason,
                        QObject *parent = nullptr)
        : QNetworkReply(parent)
    {
        setOperation(op);
        setRequest(req);
        setUrl(req.url());
        setError(QNetworkReply::ContentAccessDenied, reason);
        open(QIODevice::ReadOnly);
        setFinished(true);
        QTimer::singleShot(0, this, [this]() {
            emit errorOccurred(QNetworkReply::ContentAccessDenied);
            emit finished();
        });
    }

    void abort() override {}
    qint64 bytesAvailable() const override { return 0; }

protected:
    qint64 readData(char *, qint64) override { return -1; }
};

} // namespace

ModNetworkAccessManager::ModNetworkAccessManager(ModManifest manifest,
                                                 ErrorCallback onError,
                                                 QObject *parent)
    : QNetworkAccessManager(parent)
    , m_manifest(std::move(manifest))
    , m_onError(std::move(onError))
{
    const QFileInfo dirInfo(m_manifest.directory);
    m_modDirectory = dirInfo.canonicalFilePath().isEmpty()
        ? QDir::cleanPath(dirInfo.absoluteFilePath())
        : dirInfo.canonicalFilePath();
    while (m_modDirectory.endsWith(u'/') && m_modDirectory.size() > 1) {
        m_modDirectory.chop(1);
    }
}

QNetworkReply *ModNetworkAccessManager::createRequest(Operation op,
                                                      const QNetworkRequest &request,
                                                      QIODevice *outgoingData)
{
    const QUrl url = request.url();
    const QString scheme = url.scheme().toLower();

    auto deny = [&](const QString &reason) -> QNetworkReply * {
        qCWarning(lcMods).noquote() << QStringLiteral("[%1] %2").arg(m_manifest.id, reason);
        if (m_onError) {
            m_onError(m_manifest.id, reason);
        }
        return new BlockedNetworkReply(op, request, reason, this);
    };

    if (scheme == QLatin1StringView("http") || scheme == QLatin1StringView("https")) {
        const QString host = url.host().trimmed().toLower();
        if (!m_manifest.allowsNetworkHost(host)) {
            return deny(QStringLiteral("Сетевой запрос заблокирован (требуется разрешение 'network:%1'): %2")
                            .arg(host, url.toString()));
        }
        QNetworkRequest safeReq = request;
        safeReq.setAttribute(QNetworkRequest::CookieLoadControlAttribute, QNetworkRequest::Manual);
        safeReq.setAttribute(QNetworkRequest::CookieSaveControlAttribute, QNetworkRequest::Manual);
        safeReq.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("ymusic-mod/%1").arg(m_manifest.id));
        return QNetworkAccessManager::createRequest(op, safeReq, outgoingData);
    }

    if (scheme == QLatin1StringView("file")) {
        const QFileInfo fi(url.toLocalFile());
        const QString canonical = fi.canonicalFilePath();
        if (!m_modDirectory.isEmpty() && !canonical.isEmpty() && canonical.startsWith(m_modDirectory + u'/')) {
            return QNetworkAccessManager::createRequest(op, request, outgoingData);
        }
        return deny(QStringLiteral("Заблокировано чтение файла вне папки мода: %1").arg(url.toString()));
    }

    if (scheme == QLatin1StringView("qrc")) {
        const QString path = url.path();
        if (path.startsWith(QLatin1StringView("/qt/qml/ymusic/sdk/"))) {
            return QNetworkAccessManager::createRequest(op, request, outgoingData);
        }
        return deny(QStringLiteral("Заблокирован доступ к внутреннему ресурсу: %1").arg(url.toString()));
    }

    if (scheme == QLatin1StringView("data")) {
        return QNetworkAccessManager::createRequest(op, request, outgoingData);
    }

    return deny(QStringLiteral("Заблокирован запрос с запрещённой схемой URL: %1").arg(url.toString()));
}

ModNetworkAccessManagerFactory::ModNetworkAccessManagerFactory(
    ModManifest manifest,
    ModNetworkAccessManager::ErrorCallback onError)
    : m_manifest(std::move(manifest))
    , m_onError(std::move(onError))
{
}

QNetworkAccessManager *ModNetworkAccessManagerFactory::create(QObject *parent)
{
    return new ModNetworkAccessManager(m_manifest, m_onError, parent);
}

} // namespace ymusic::mods
