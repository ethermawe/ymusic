#pragma once

#include <QHash>
#include <QQmlAbstractUrlInterceptor>
#include <QReadWriteLock>
#include <QString>
#include <QUrl>

namespace ymusic::mods {

/// Intercepts qrc:/qt/qml/ymusic/ui/<path> URLs when an enabled mod with ui:override
/// overrides that QML file. Thread-safe and zero-cost when empty.
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

} // namespace ymusic::mods
