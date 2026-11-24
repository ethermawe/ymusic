#include "mods/ModUrlInterceptor.h"

#include <QLoggingCategory>

namespace ymusic::mods {

Q_DECLARE_LOGGING_CATEGORY(lcMods)

namespace {

QString extractRelativeModulePath(const QUrl &url)
{
    if (url.scheme() == QLatin1StringView("qrc")) {
        const QString path = url.path();
        static constexpr QLatin1StringView kPathPrefix("/qt/qml/ymusic/ui/");
        if (path.startsWith(kPathPrefix)) {
            return path.mid(kPathPrefix.size());
        }
    }
    const QString str = url.toString();
    static constexpr QLatin1StringView kQrcPrefix("qrc:/qt/qml/ymusic/ui/");
    static constexpr QLatin1StringView kColonPrefix(":/qt/qml/ymusic/ui/");
    if (str.startsWith(kQrcPrefix)) {
        return str.mid(kQrcPrefix.size());
    }
    if (str.startsWith(kColonPrefix)) {
        return str.mid(kColonPrefix.size());
    }
    return {};
}

} // namespace

void ModUrlInterceptor::setOverrides(const QHash<QString, QUrl> &overrides)
{
    QWriteLocker lock(&m_lock);
    m_overrides = overrides;
}

void ModUrlInterceptor::clear()
{
    QWriteLocker lock(&m_lock);
    m_overrides.clear();
}

int ModUrlInterceptor::count() const
{
    QReadLocker lock(&m_lock);
    return static_cast<int>(m_overrides.size());
}

QUrl ModUrlInterceptor::intercept(const QUrl &url, DataType type)
{
    if (type != QmlFile && type != JavaScriptFile && type != UrlString) {
        return url;
    }

    QReadLocker lock(&m_lock);
    if (m_overrides.isEmpty()) {
        return url;
    }

    const QString rel = extractRelativeModulePath(url);
    if (rel.isEmpty()) {
        return url;
    }
    const auto it = m_overrides.constFind(rel);
    if (it != m_overrides.constEnd() && it.value().isValid()) {
        qCInfo(lcMods).noquote() << QStringLiteral("UI override: %1 -> %2").arg(rel, it.value().toLocalFile());
        return it.value();
    }
    return url;
}

} // namespace ymusic::mods
