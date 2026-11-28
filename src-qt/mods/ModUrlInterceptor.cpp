#include "mods/ModUrlInterceptor.h"

#include "mods/ModManifest.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QLibraryInfo>
#include <QLoggingCategory>
#include <QRegularExpression>
#include <QSet>

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

QString stripQmlComments(const QString &source)
{
    QString out;
    out.reserve(source.size());
    bool inSingle = false;
    bool inDouble = false;
    bool inLineComment = false;
    bool inBlockComment = false;
    const qsizetype n = source.size();
    for (qsizetype i = 0; i < n; ++i) {
        const QChar c = source.at(i);
        const QChar next = (i + 1 < n) ? source.at(i + 1) : QChar();
        if (inLineComment) {
            if (c == u'\n') {
                inLineComment = false;
                out.append(c);
            }
            continue;
        }
        if (inBlockComment) {
            if (c == u'*' && next == u'/') {
                inBlockComment = false;
                ++i;
            } else if (c == u'\n') {
                out.append(c);
            }
            continue;
        }
        if (inSingle) {
            out.append(c);
            if (c == u'\\' && i + 1 < n) {
                out.append(next);
                ++i;
            } else if (c == u'\'') {
                inSingle = false;
            }
            continue;
        }
        if (inDouble) {
            out.append(c);
            if (c == u'\\' && i + 1 < n) {
                out.append(next);
                ++i;
            } else if (c == u'"') {
                inDouble = false;
            }
            continue;
        }
        if (c == u'/' && next == u'/') {
            inLineComment = true;
            ++i;
            continue;
        }
        if (c == u'/' && next == u'*') {
            inBlockComment = true;
            ++i;
            continue;
        }
        if (c == u'\'') {
            inSingle = true;
            out.append(c);
            continue;
        }
        if (c == u'"') {
            inDouble = true;
            out.append(c);
            continue;
        }
        out.append(c);
    }
    return out;
}

bool validateFileRecursive(const QString &filePath,
                           const QString &modCanonicalDir,
                           QSet<QString> &visited,
                           QString *errorOut)
{
    const QFileInfo fi(filePath);
    const QString canonical = fi.canonicalFilePath();
    if (canonical.isEmpty() || !fi.isFile() || !canonical.startsWith(modCanonicalDir + u'/')) {
        if (errorOut) {
            *errorOut = QStringLiteral("Файл мода выходит за пределы каталога мода: %1").arg(filePath);
        }
        return false;
    }
    if (visited.contains(canonical)) {
        return true;
    }
    visited.insert(canonical);

    QFile f(canonical);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        if (errorOut) {
            *errorOut = QStringLiteral("Не удалось прочитать файл мода: %1").arg(canonical);
        }
        return false;
    }
    const QString cleaned = stripQmlComments(QString::fromUtf8(f.readAll()));
    const QStringList lines = cleaned.split(u'\n');

    // Matches: import "path" [as Alias]  OR  import Module.Name [1.0] [as Alias]
    static const QRegularExpression importRe(
        QStringLiteral(R"re(^\s*import\s+(?:"([^"]+)"|'([^']+)'|([A-Za-z_][A-Za-z0-9_.]*)))re"));

    const QDir fileDir = fi.dir();
    for (const QString &rawLine : lines) {
        const QString line = rawLine.trimmed();
        if (line.isEmpty() || !line.startsWith(QLatin1StringView("import"))) {
            continue;
        }
        const QRegularExpressionMatch m = importRe.match(line);
        if (!m.hasMatch()) {
            continue;
        }
        const QString quotedTarget = !m.captured(1).isEmpty() ? m.captured(1) : m.captured(2);
        const QString moduleUri = m.captured(3);

        if (!quotedTarget.isEmpty()) {
            if (quotedTarget.contains(QLatin1StringView("://")) || QDir::isAbsolutePath(quotedTarget)) {
                if (errorOut) {
                    *errorOut = QStringLiteral("Запрещённый абсолютный/внешний импорт в моде: \"%1\"").arg(quotedTarget);
                }
                return false;
            }
            const QString candidate = fileDir.filePath(quotedTarget);
            const QFileInfo targetInfo(candidate);
            const QString targetCanonical = targetInfo.canonicalFilePath();
            if (targetCanonical.isEmpty()
                || (targetCanonical != modCanonicalDir && !targetCanonical.startsWith(modCanonicalDir + u'/'))) {
                if (errorOut) {
                    *errorOut = QStringLiteral("Запрещённый импорт за пределы папки мода: \"%1\"").arg(quotedTarget);
                }
                return false;
            }
            if (targetInfo.isFile()) {
                if (!validateFileRecursive(targetCanonical, modCanonicalDir, visited, errorOut)) {
                    return false;
                }
            } else if (targetInfo.isDir()) {
                const auto qmlFiles = QDir(targetCanonical).entryInfoList(
                    {QStringLiteral("*.qml"), QStringLiteral("*.js"), QStringLiteral("*.mjs")},
                    QDir::Files | QDir::NoSymLinks);
                for (const QFileInfo &child : qmlFiles) {
                    if (!validateFileRecursive(child.absoluteFilePath(), modCanonicalDir, visited, errorOut)) {
                        return false;
                    }
                }
            }
            continue;
        }

        if (!moduleUri.isEmpty()) {
            if (!ModSandboxUrlInterceptor::isAllowedImportModule(moduleUri)) {
                if (errorOut) {
                    *errorOut = QStringLiteral("Запрещённый импорт модуля '%1' (разрешены QtQuick, QtQuick.Controls, QtQuick.Layouts, ymusic.sdk)")
                                    .arg(moduleUri);
                }
                return false;
            }
        }
    }

    return true;
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

// --- ModSandboxUrlInterceptor ------------------------------------------------

ModSandboxUrlInterceptor::ModSandboxUrlInterceptor(QString modId,
                                                   QString modDirectory,
                                                   QStringList qtImportPaths,
                                                   ErrorCallback onError)
    : m_modId(std::move(modId))
    , m_onError(std::move(onError))
{
    const QFileInfo dirInfo(modDirectory);
    m_modDirectory = dirInfo.canonicalFilePath().isEmpty()
        ? QDir::cleanPath(dirInfo.absoluteFilePath())
        : dirInfo.canonicalFilePath();
    while (m_modDirectory.endsWith(u'/') && m_modDirectory.size() > 1) {
        m_modDirectory.chop(1);
    }

    auto addImportRoot = [&](const QString &raw) {
        if (raw.isEmpty() || raw.startsWith(QLatin1StringView("qrc:")) || raw.startsWith(QLatin1StringView(":/"))) {
            return;
        }
        const QFileInfo info(raw);
        QString p = info.canonicalFilePath().isEmpty()
            ? QDir::cleanPath(info.absoluteFilePath())
            : info.canonicalFilePath();
        while (p.endsWith(u'/') && p.size() > 1) {
            p.chop(1);
        }
        if (!p.isEmpty() && !m_qtQmlImportPaths.contains(p)) {
            m_qtQmlImportPaths.append(p);
        }
    };

    for (const QString &p : qtImportPaths) {
        addImportRoot(p);
    }
    addImportRoot(QLibraryInfo::path(QLibraryInfo::QmlImportsPath));
}

bool ModSandboxUrlInterceptor::isAllowedImportModule(const QString &moduleUri)
{
    static const QStringList kAllowed {
        QStringLiteral("QtQuick"),
        QStringLiteral("QtQuick.Controls"),
        QStringLiteral("QtQuick.Controls.Basic"),
        QStringLiteral("QtQuick.Controls.impl"),
        QStringLiteral("QtQuick.Templates"),
        QStringLiteral("QtQuick.Layouts"),
        QStringLiteral("QtQuick.Window"),
        QStringLiteral("QtQuick.Shapes"),
        QStringLiteral("QtQuick.Effects"),
        QStringLiteral("QtQml"),
        QStringLiteral("QtQml.Models"),
        QStringLiteral("ymusic.sdk"),
    };
    return kAllowed.contains(moduleUri);
}

bool ModSandboxUrlInterceptor::isAllowedQtModulePath(const QString &relativeModulePath)
{
    const QString cleaned = QDir::cleanPath(relativeModulePath);
    if (cleaned.startsWith(QLatin1StringView("..")) || cleaned.startsWith(u'/')) {
        return false;
    }
    static const QStringList kAllowedBases {
        QStringLiteral("QtQuick/Controls"),
        QStringLiteral("QtQuick/Templates"),
        QStringLiteral("QtQuick/Layouts"),
        QStringLiteral("QtQuick/Window"),
        QStringLiteral("QtQuick/Shapes"),
        QStringLiteral("QtQuick/Effects"),
        QStringLiteral("QtQuick/tooling"),
        QStringLiteral("QtQuick/NativeStyle"),
        QStringLiteral("QtQml/Base"),
        QStringLiteral("QtQml/Models"),
        QStringLiteral("QtQml/WorkerScript"),
    };
    if (cleaned == QLatin1StringView("QtQuick")
        || cleaned == QLatin1StringView("QtQuick/qmldir")
        || cleaned == QLatin1StringView("QtQml")
        || cleaned == QLatin1StringView("QtQml/qmldir")) {
        return true;
    }
    for (const QString &base : kAllowedBases) {
        if (cleaned == base || cleaned.startsWith(base + u'/')) {
            return true;
        }
    }
    // Allow direct plugin/qmldir files inside QtQuick/ or QtQml/ (e.g. libqtquick2plugin.so)
    if (cleaned.startsWith(QLatin1StringView("QtQuick/")) && !cleaned.mid(8).contains(u'/')) {
        return true;
    }
    if (cleaned.startsWith(QLatin1StringView("QtQml/")) && !cleaned.mid(6).contains(u'/')) {
        return true;
    }
    return false;
}

void ModSandboxUrlInterceptor::reportBlocked(const QUrl &url, const QString &reason) const
{
    const QString msg = QStringLiteral("Заблокирован ресурс (%1): %2").arg(reason, url.toString());
    qCWarning(lcMods).noquote() << QStringLiteral("[%1] %2").arg(m_modId, msg);
    if (m_onError) {
        m_onError(m_modId, msg);
    }
}

QUrl ModSandboxUrlInterceptor::intercept(const QUrl &url, DataType type)
{
    if (!url.isValid() || url.isEmpty()) {
        return url;
    }

    const auto isAllowedImportProbe = [&]() -> bool {
        if (type != QmldirFile) return false;
        const QString s = url.toString();
        return s.contains(QLatin1StringView("/ymusic/sdk"))
            || s.contains(QLatin1StringView("/ymusic.1"))
            || s.contains(QLatin1StringView("/QtQuick"))
            || s.contains(QLatin1StringView("/QtQml"));
    };

    const auto deny = [&](const QString &reason) -> QUrl {
        if (!isAllowedImportProbe()) {
            reportBlocked(url, reason);
        }
        return QUrl(QStringLiteral("qrc:/ymusic-sandbox-blocked/denied"));
    };

    const QString scheme = url.scheme().toLower();

    // Network & data URLs are validated by ModNetworkAccessManager
    if (scheme == QLatin1StringView("http")
        || scheme == QLatin1StringView("https")
        || scheme == QLatin1StringView("data")) {
        return url;
    }

    // Internal image provider (album artwork)
    if (scheme == QLatin1StringView("image")) {
        if (url.host().toLower() == QLatin1StringView("art")) {
            return url;
        }
        return deny(QStringLiteral("неразрешённый image provider"));
    }

    // qrc resources: allow ymusic.sdk and allowed Qt built-in imports, block ymusic.ui & everything else
    if (scheme == QLatin1StringView("qrc") || url.toString().startsWith(QLatin1StringView(":/"))) {
        QString path = url.path();
        if (path.startsWith(QLatin1StringView(":/"))) {
            path = path.mid(1);
        }
        if (path.startsWith(QLatin1StringView("/qt/qml/ymusic/sdk/"))
            || path == QLatin1StringView("/qt/qml/ymusic/sdk")) {
            return url;
        }
        if (path.startsWith(QLatin1StringView("/qt-project.org/imports/"))) {
            const QString rel = path.mid(24);
            if (isAllowedQtModulePath(rel)) {
                return url;
            }
        }
        if (path.startsWith(QLatin1StringView("/qt/qml/QtQuick/"))
            || path.startsWith(QLatin1StringView("/qt/qml/QtQml/"))) {
            const QString rel = path.mid(8);
            if (isAllowedQtModulePath(rel)) {
                return url;
            }
        }
        return deny(QStringLiteral("запрещённый внутренний ресурс/модуль"));
    }

    // Local files: allow strictly inside modDirectory OR allowed Qt QML system modules
    if (scheme == QLatin1StringView("file") || scheme.isEmpty()) {
        const QString local = url.isLocalFile() ? url.toLocalFile() : url.path();
        const QFileInfo fi(local);
        const QString resolved = fi.canonicalFilePath().isEmpty()
            ? QDir::cleanPath(fi.absoluteFilePath())
            : fi.canonicalFilePath();

        if (!m_modDirectory.isEmpty()
            && (resolved == m_modDirectory || resolved.startsWith(m_modDirectory + u'/'))) {
            return url;
        }
        for (const QString &importRoot : m_qtQmlImportPaths) {
            if (resolved.startsWith(importRoot + u'/')) {
                const QString rel = resolved.mid(importRoot.size() + 1);
                if (isAllowedQtModulePath(rel)) {
                    return url;
                }
            }
        }
        return deny(QStringLiteral("доступ к файлу вне папки мода"));
    }

    return deny(QStringLiteral("запрещённая схема URL"));
}

bool validateModQmlImports(const QString &filePath, const QString &modDirectory, QString *errorOut)
{
    const QFileInfo dirInfo(modDirectory);
    QString modCanonical = dirInfo.canonicalFilePath();
    if (modCanonical.isEmpty() || !dirInfo.isDir()) {
        if (errorOut) {
            *errorOut = QStringLiteral("Каталог мода не найден: %1").arg(modDirectory);
        }
        return false;
    }
    while (modCanonical.endsWith(u'/') && modCanonical.size() > 1) {
        modCanonical.chop(1);
    }
    QSet<QString> visited;
    return validateFileRecursive(filePath, modCanonical, visited, errorOut);
}

} // namespace ymusic::mods
