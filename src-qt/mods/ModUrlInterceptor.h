#pragma once

#include <QHash>
#include <QQmlAbstractUrlInterceptor>
#include <QReadWriteLock>
#include <QString>
#include <QUrl>

#include <functional>

namespace ymusic::mods {

/// Intercepts qrc:/qt/qml/ymusic/ui/<path> URLs on the main app engine when an enabled mod
/// with ui:override overrides that QML file. Thread-safe and zero-cost when empty.
class ModUrlInterceptor final : public QQmlAbstractUrlInterceptor {
public:
    ModUrlInterceptor() = default;
    ~ModUrlInterceptor() override = default;

    void setOverrides(const QHash<QString, QUrl> &overrides);
    void clear();
    int count() const;

    QUrl intercept(const QUrl &url, DataType type) override;

private:
    mutable QReadWriteLock m_lock;
    QHash<QString, QUrl> m_overrides;
};

/// Strict URL interceptor installed on each mod's isolated QQmlEngine.
/// Allows only QtQuick/Controls/Layouts, ymusic.sdk, and files strictly inside the mod's directory.
class ModSandboxUrlInterceptor final : public QQmlAbstractUrlInterceptor {
public:
    using ErrorCallback = std::function<void(const QString &modId, const QString &message)>;

    ModSandboxUrlInterceptor(QString modId, QString modDirectory, ErrorCallback onError = {});
    ~ModSandboxUrlInterceptor() override = default;

    QUrl intercept(const QUrl &url, DataType type) override;

    static bool isAllowedQtModulePath(const QString &relativeModulePath);
    static bool isAllowedImportModule(const QString &moduleUri);

private:
    void reportBlocked(const QUrl &url, const QString &reason) const;

    QString m_modId;
    QString m_modDirectory; // canonical path without trailing slash
    QString m_qtQmlImportPath;
    ErrorCallback m_onError;
};

/// Pre-load static validator for mod QML/JS files.
/// Rejects any `import` outside the allowlist (QtQuick*, QtQml*, ymusic.sdk, or local files inside modDirectory).
bool validateModQmlImports(const QString &filePath, const QString &modDirectory, QString *errorOut = nullptr);

} // namespace ymusic::mods
