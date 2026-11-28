#pragma once

#include "mods/ModManifest.h"

#include <QNetworkAccessManager>
#include <QQmlNetworkAccessManagerFactory>

#include <functional>

namespace ymusic::mods {

/// Per-mod QNetworkAccessManager that enforces `network:<host>` permissions
/// for QML XMLHttpRequest and Image loads, and blocks local file/resource escapes.
class ModNetworkAccessManager : public QNetworkAccessManager {
    Q_OBJECT

public:
    using ErrorCallback = std::function<void(const QString &modId, const QString &message)>;

    explicit ModNetworkAccessManager(ModManifest manifest,
                                     ErrorCallback onError = {},
                                     QObject *parent = nullptr);

protected:
    QNetworkReply *createRequest(Operation op,
                                 const QNetworkRequest &request,
                                 QIODevice *outgoingData = nullptr) override;

private:
    ModManifest m_manifest;
    QString m_modDirectory;
    ErrorCallback m_onError;
};

class ModNetworkAccessManagerFactory final : public QQmlNetworkAccessManagerFactory {
public:
    explicit ModNetworkAccessManagerFactory(ModManifest manifest,
                                            ModNetworkAccessManager::ErrorCallback onError = {});
    ~ModNetworkAccessManagerFactory() override = default;

    QNetworkAccessManager *create(QObject *parent) override;

private:
    ModManifest m_manifest;
    ModNetworkAccessManager::ErrorCallback m_onError;
};

} // namespace ymusic::mods
