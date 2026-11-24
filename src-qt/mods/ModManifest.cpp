#include "mods/ModManifest.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>

namespace ymusic::mods {

namespace {

bool isKnownPermission(const QString &perm)
{
    static const QStringList kSimple {
        QStringLiteral("playback:read"),
        QStringLiteral("playback:control"),
        QStringLiteral("spectrum:read"),
        QStringLiteral("ui:slots"),
        QStringLiteral("ui:override"),
        QStringLiteral("storage"),
        QStringLiteral("clipboard"),
    };
    if (kSimple.contains(perm)) {
        return true;
    }
    if (perm.startsWith(QLatin1StringView("network:"))) {
        const QString host = perm.mid(8).trimmed().toLower();
        static const QRegularExpression hostRe(QStringLiteral("^[a-z0-9.-]+$"));
        return !host.isEmpty() && host.length() <= 253 && hostRe.match(host).hasMatch() && !host.contains(QLatin1StringView(".."));
    }
    return false;
}

QString normalizeOverrideTarget(QString target)
{
    target = target.trimmed().replace(u'\\', u'/');
    while (target.startsWith(u'/')) target.remove(0, 1);
    if (target.startsWith(QLatin1StringView("qrc:/qt/qml/ymusic/ui/"))) {
        target = target.mid(22);
    } else if (target.startsWith(QLatin1StringView(":/qt/qml/ymusic/ui/"))) {
        target = target.mid(19);
    }
    if (target.contains(QLatin1StringView("..")) || !target.endsWith(QLatin1StringView(".qml"), Qt::CaseInsensitive)) {
        return {};
    }
    return target;
}

} // namespace

bool isValidModId(const QString &id)
{
    static const QRegularExpression idRe(QStringLiteral("^[a-z0-9][a-z0-9_-]{1,47}$"));
    return idRe.match(id).hasMatch();
}

bool ModManifest::hasPermission(const QString &perm) const
{
    return permissions.contains(perm);
}

bool ModManifest::allowsNetworkHost(const QString &host) const
{
    const QString lowered = host.trimmed().toLower();
    if (lowered.isEmpty()) return false;
    return permissions.contains(QStringLiteral("network:") + lowered);
}

QString resolveModPath(const QString &modDirectory, const QString &relativePath, bool mustExist)
{
    const QString cleanedRel = relativePath.trimmed().replace(u'\\', u'/');
    if (cleanedRel.isEmpty() || QDir::isAbsolutePath(cleanedRel) || cleanedRel.startsWith(u'/')) {
        return {};
    }
    const QStringList segments = cleanedRel.split(u'/', Qt::SkipEmptyParts);
    if (segments.isEmpty() || segments.contains(QStringLiteral(".."))) {
        return {};
    }

    const QFileInfo dirInfo(modDirectory);
    const QString baseCanonical = dirInfo.canonicalFilePath();
    if (baseCanonical.isEmpty() || !dirInfo.isDir()) {
        return {};
    }

    const QString candidate = QDir(baseCanonical).filePath(cleanedRel);
    const QFileInfo targetInfo(candidate);
    if (mustExist) {
        if (!targetInfo.exists() || !targetInfo.isFile()) {
            return {};
        }
        const QString targetCanonical = targetInfo.canonicalFilePath();
        if (targetCanonical.isEmpty() || !targetCanonical.startsWith(baseCanonical + u'/')) {
            return {};
        }
        return targetCanonical;
    }

    const QString cleanCandidate = QDir::cleanPath(candidate);
    if (!cleanCandidate.startsWith(baseCanonical + u'/')) {
        return {};
    }
    return cleanCandidate;
}

ModManifest parseManifest(const QString &modDirectory)
{
    ModManifest m;
    const QFileInfo dirInfo(modDirectory);
    m.directory = dirInfo.canonicalFilePath().isEmpty() ? dirInfo.absoluteFilePath() : dirInfo.canonicalFilePath();
    m.id = dirInfo.fileName();
    m.name = m.id;

    const QString manifestPath = QDir(m.directory).filePath(QStringLiteral("manifest.json"));
    const QFileInfo manifestInfo(manifestPath);
    if (!manifestInfo.isFile()) {
        m.error = QStringLiteral("Отсутствует файл manifest.json");
        return m;
    }
    if (manifestInfo.size() > 512 * 1024) {
        m.error = QStringLiteral("manifest.json превышает допустимый размер (512 КБ)");
        return m;
    }

    QFile file(manifestPath);
    if (!file.open(QIODevice::ReadOnly)) {
        m.error = QStringLiteral("Не удалось прочитать manifest.json: %1").arg(file.errorString());
        return m;
    }

    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
        m.error = QStringLiteral("Ошибка JSON в manifest.json: %1").arg(parseError.errorString());
        return m;
    }

    const QJsonObject root = doc.object();
    const QString id = root.value(QStringLiteral("id")).toString().trimmed();
    if (!isValidModId(id)) {
        m.error = QStringLiteral("Некорректный id мода (ожидается a-z, 0-9, -, _, длина 2..48)");
        return m;
    }
    m.id = id;
    m.name = root.value(QStringLiteral("name")).toString().trimmed();
    if (m.name.isEmpty()) m.name = m.id;
    m.version = root.value(QStringLiteral("version")).toString(QStringLiteral("1.0.0")).trimmed();
    m.author = root.value(QStringLiteral("author")).toString().trimmed();
    m.description = root.value(QStringLiteral("description")).toString().trimmed();
    m.minAppVersion = root.value(QStringLiteral("minAppVersion")).toString().trimmed();
    m.apiVersion = root.value(QStringLiteral("apiVersion")).toInt(1);

    if (m.apiVersion != kSupportedApiVersion) {
        m.error = QStringLiteral("Неподдерживаемая версия API мода: %1 (поддерживается %2)")
            .arg(m.apiVersion)
            .arg(kSupportedApiVersion);
        return m;
    }

    const QJsonArray perms = root.value(QStringLiteral("permissions")).toArray();
    for (const QJsonValue &val : perms) {
        const QString p = val.toString().trimmed();
        if (p.isEmpty()) continue;
        if (!isKnownPermission(p)) {
            m.error = QStringLiteral("Неизвестное разрешение в manifest.json: %1").arg(p);
            return m;
        }
        if (!m.permissions.contains(p)) {
            m.permissions.append(p);
        }
    }

    const QJsonObject entry = root.value(QStringLiteral("entry")).toObject();
    if (entry.contains(QStringLiteral("script"))) {
        const QString rel = entry.value(QStringLiteral("script")).toString();
        const QString resolved = resolveModPath(m.directory, rel, true);
        if (resolved.isEmpty()) {
            m.error = QStringLiteral("Некорректный или отсутствующий entry.script: %1").arg(rel);
            return m;
        }
        m.scriptEntry = resolved;
    }
    if (entry.contains(QStringLiteral("settings"))) {
        const QString rel = entry.value(QStringLiteral("settings")).toString();
        const QString resolved = resolveModPath(m.directory, rel, true);
        if (resolved.isEmpty()) {
            m.error = QStringLiteral("Некорректный или отсутствующий entry.settings: %1").arg(rel);
            return m;
        }
        m.settingsEntry = resolved;
    }

    const QJsonObject sidebar = root.value(QStringLiteral("sidebar")).toObject();
    m.sidebarTitle = sidebar.value(QStringLiteral("title")).toString().trimmed();
    m.sidebarSymbol = sidebar.value(QStringLiteral("symbol")).toString().trimmed();

    const QJsonObject settingsTab = root.value(QStringLiteral("settingsTab")).toObject();
    m.settingsTabTitle = settingsTab.value(QStringLiteral("title")).toString().trimmed();
    m.settingsTabSymbol = settingsTab.value(QStringLiteral("symbol")).toString().trimmed();
    m.settingsTabShape = settingsTab.value(QStringLiteral("shape")).toString().trimmed();

    const QJsonObject immersivePanel = root.value(QStringLiteral("immersivePanel")).toObject();
    m.immersivePanelTitle = immersivePanel.value(QStringLiteral("title")).toString().trimmed();
    m.immersivePanelSymbol = immersivePanel.value(QStringLiteral("symbol")).toString().trimmed();

    const QJsonObject slotsObj = root.value(QStringLiteral("slots")).toObject();
    for (auto it = slotsObj.constBegin(); it != slotsObj.constEnd(); ++it) {
        const QString slotName = it.key().trimmed();
        const QString rel = it.value().toString().trimmed();
        if (slotName.isEmpty() || rel.isEmpty()) continue;
        const QString resolved = resolveModPath(m.directory, rel, true);
        if (resolved.isEmpty()) {
            m.error = QStringLiteral("Некорректный файл для слота '%1': %2").arg(slotName, rel);
            return m;
        }
        m.slotsMap.insert(slotName, resolved);
    }

    const QJsonObject overridesObj = root.value(QStringLiteral("overrides")).toObject();
    for (auto it = overridesObj.constBegin(); it != overridesObj.constEnd(); ++it) {
        const QString target = normalizeOverrideTarget(it.key());
        const QString rel = it.value().toString().trimmed();
        if (target.isEmpty()) {
            m.error = QStringLiteral("Некорректная цель override: %1").arg(it.key());
            return m;
        }
        const QString resolved = resolveModPath(m.directory, rel, true);
        if (resolved.isEmpty()) {
            m.error = QStringLiteral("Некорректный файл override '%1': %2").arg(target, rel);
            return m;
        }
        m.overridesMap.insert(target, resolved);
    }

    if (!m.overridesMap.isEmpty() && !m.hasPermission(QStringLiteral("ui:override"))) {
        m.error = QStringLiteral("Для overrides требуется разрешение 'ui:override'");
        return m;
    }

    if (m.sidebarTitle.isEmpty()) {
        m.sidebarTitle = m.name;
    }
    if (m.sidebarSymbol.isEmpty()) {
        m.sidebarSymbol = QStringLiteral("extension");
    }
    if (m.settingsTabTitle.isEmpty()) {
        m.settingsTabTitle = m.name;
    }
    if (m.settingsTabSymbol.isEmpty()) {
        m.settingsTabSymbol = QStringLiteral("widgets");
    }
    if (m.settingsTabShape.isEmpty()) {
        m.settingsTabShape = QStringLiteral("flower");
    }
    if (m.immersivePanelTitle.isEmpty()) {
        m.immersivePanelTitle = m.name;
    }
    if (m.immersivePanelSymbol.isEmpty()) {
        m.immersivePanelSymbol = QStringLiteral("extension");
    }

    m.valid = true;
    return m;
}

} // namespace ymusic::mods
