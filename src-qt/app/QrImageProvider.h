#pragma once

#include <QImage>
#include <QQuickImageProvider>
#include <QString>

namespace ymusic {

class QrImageProvider final : public QQuickImageProvider {
public:
    QrImageProvider();
    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;

    static QImage renderQr(const QByteArray &payload, int targetPx = 256);
};

} // namespace ymusic
