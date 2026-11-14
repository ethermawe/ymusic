#pragma once

#include <QCache>
#include <QHash>
#include <QImage>
#include <QObject>
#include <QQuickAsyncImageProvider>
#include <QUrl>

#include <functional>

class QNetworkAccessManager;

namespace ymusic {

/// Cover art repository with disk cache, encoded byte deduplication, and bucketed off-thread decode.
class ArtworkCache : public QObject {
    Q_OBJECT

public:
    using BytesCallback = std::function<void(const QByteArray &)>;
    using ImageCallback = std::function<void(const QImage &)>;

    explicit ArtworkCache(QNetworkAccessManager *network, QObject *parent = nullptr);
    ~ArtworkCache() override;

    static ArtworkCache *instance();
    static int bucket(int pixels);

    void bytes(const QUrl &url, BytesCallback callback);
    void image(const QUrl &url, int pixels, ImageCallback callback);
    void invalidate(const QUrl &url);

private:
    void finishDownload(const QUrl &url, const QByteArray &data);

    QNetworkAccessManager *m_network;
    QCache<QUrl, QByteArray> m_encoded;
    QCache<QString, QImage> m_decoded;
    QHash<QUrl, QList<BytesCallback>> m_downloads;
    QHash<QString, QList<ImageCallback>> m_decodes;
};

/// Async image provider exposed to QML under `image://art/<encoded-url>`.
class ArtworkImageProvider : public QQuickAsyncImageProvider {
public:
    QQuickImageResponse *requestImageResponse(const QString &id, const QSize &requestedSize) override;
};

} // namespace ymusic
