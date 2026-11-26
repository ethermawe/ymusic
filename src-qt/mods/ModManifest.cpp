#include "mods/ModManifest.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QVersionNumber>

namespace ymusic::mods {

namespace {

bool isKnownPermission(const QString &perm)
{
    static const QStringList kSimple {
        QStringLiteral("playback:read"),
        QStringLiteral("playback:control"),
        QStringLiteral("library:read"),
        QStringLiteral("catalog:override"),
        QStringLiteral("audio:override"),
        QStringLiteral("lyrics:read"),
        QStringLiteral("lyrics:transform"),
        QStringLiteral("spectrum:read"),
        QStringLiteral("ui:slots"),
        QStringLiteral("ui:override"),
        QStringLiteral("storage"),
        QStringLiteral("clipboard"),
        QStringLiteral("external"),
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

    if (!root.contains(QStringLiteral("apiVersion")) || root.value(QStringLiteral("apiVersion")).isNull()) {
        m.apiVersion = QStringLiteral("1.0");
        m.warnings.append(QStringLiteral("В manifest.json не указано поле apiVersion (рекомендуется \"1.0\")"));
    } else {
        const QJsonValue apiVal = root.value(QStringLiteral("apiVersion"));
        if (apiVal.isDouble()) {
            const int major = apiVal.toInt(-1);
            if (major != kSupportedApiMajor) {
                m.error = QStringLiteral("Несовместимая версия API мода: %1 (поддерживается %2.x)")
                    .arg(major)
                    .arg(kSupportedApiMajor);
                return m;
            }
            m.apiVersion = QStringLiteral("%1.0").arg(major);
        } else if (apiVal.isString()) {
            const QString rawApi = apiVal.toString().trimmed();
            if (rawApi.isEmpty()) {
                m.apiVersion = QStringLiteral("1.0");
                m.warnings.append(QStringLiteral("В manifest.json пустое поле apiVersion (рекомендуется \"1.0\")"));
            } else {
                qsizetype suffixIdx = -1;
                const QVersionNumber parsedApi = QVersionNumber::fromString(rawApi, &suffixIdx);
                if (parsedApi.isNull() || suffixIdx != rawApi.size()) {
                    m.error = QStringLiteral("Некорректный формат apiVersion: '%1' (ожидается semver, например \"1.0\")").arg(rawApi);
                    return m;
                }
                if (parsedApi.majorVersion() != kSupportedApiMajor) {
                    m.error = QStringLiteral("Несовместимая версия API мода: %1 (поддерживается %2.x)")
                        .arg(rawApi)
                        .arg(kSupportedApiMajor);
                    return m;
                }
                if (parsedApi.minorVersion() > kSupportedApiMinor) {
                    m.warnings.append(QStringLiteral("Мод запрашивает apiVersion %1 (текущая: %2.%3)")
                                          .arg(rawApi)
                                          .arg(kSupportedApiMajor)
                                          .arg(kSupportedApiMinor));
                }
                m.apiVersion = rawApi;
            }
        } else {
            m.error = QStringLiteral("Некорректный тип apiVersion в manifest.json (ожидается строка semver, например \"1.0\")");
            return m;
        }
    }

    // Real minAppVersion check against running application version
    if (!m.minAppVersion.isEmpty()) {
        const QString appVerStr = QCoreApplication::applicationVersion().trimmed();
        if (!appVerStr.isEmpty()) {
            const QVersionNumber reqVer = QVersionNumber::fromString(m.minAppVersion);
            const QVersionNumber curVer = QVersionNumber::fromString(appVerStr);
            if (!reqVer.isNull() && !curVer.isNull() && curVer < reqVer) {
                m.error = QStringLiteral("Требуется ymusic версии %1 или новее (текущая: %2)")
                    .arg(m.minAppVersion, appVerStr);
                return m;
            }
        }
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

    // Legacy fallback metadata (still honored when using short string syntax in "slots")
    const QJsonObject legacySidebar = root.value(QStringLiteral("sidebar")).toObject();
    const QJsonObject legacySettingsTab = root.value(QStringLiteral("settingsTab")).toObject();
    const QJsonObject legacyImmersivePanel = root.value(QStringLiteral("immersivePanel")).toObject();

    auto parseSlotContribution = [&](const QString &slotName, const QJsonValue &val, int idx, ModSlotItem &out) -> bool {
        QString rel;
        QString itemId;
        if (val.isString()) {
            rel = val.toString().trimmed();
        } else if (val.isObject()) {
            const QJsonObject obj = val.toObject();
            rel = obj.value(QStringLiteral("file")).toString().trimmed();
            itemId = obj.value(QStringLiteral("id")).toString().trimmed();
            out.title = obj.value(QStringLiteral("title")).toString().trimmed();
            out.symbol = obj.value(QStringLiteral("symbol")).toString().trimmed();
            out.shape = obj.value(QStringLiteral("shape")).toString().trimmed();
        } else {
            return false;
        }

        const QString resolved = resolveModPath(m.directory, rel, true);
        if (resolved.isEmpty()) {
            m.error = QStringLiteral("Некорректный файл для слота '%1': %2").arg(slotName, rel);
            return false;
        }
        out.file = resolved;
        if (!itemId.isEmpty()) {
            out.entryId = m.id + u':' + itemId;
        } else if (idx > 0) {
            out.entryId = m.id + u':' + QString::number(idx);
        } else {
            out.entryId = m.id;
        }

        // Fill sensible defaults per slot type (with legacy fallback)
        if (slotName == QLatin1StringView("sidebar.page")) {
            if (out.title.isEmpty()) out.title = legacySidebar.value(QStringLiteral("title")).toString().trimmed();
            if (out.symbol.isEmpty()) out.symbol = legacySidebar.value(QStringLiteral("symbol")).toString().trimmed();
            if (out.symbol.isEmpty()) out.symbol = QStringLiteral("extension");
        } else if (slotName == QLatin1StringView("settings.tab")) {
            if (out.title.isEmpty()) out.title = legacySettingsTab.value(QStringLiteral("title")).toString().trimmed();
            if (out.symbol.isEmpty()) out.symbol = legacySettingsTab.value(QStringLiteral("symbol")).toString().trimmed();
            if (out.shape.isEmpty()) out.shape = legacySettingsTab.value(QStringLiteral("shape")).toString().trimmed();
            if (out.symbol.isEmpty()) out.symbol = QStringLiteral("widgets");
            if (out.shape.isEmpty()) out.shape = QStringLiteral("flower");
        } else if (slotName == QLatin1StringView("immersive.panel")) {
            if (out.title.isEmpty()) out.title = legacyImmersivePanel.value(QStringLiteral("title")).toString().trimmed();
            if (out.symbol.isEmpty()) out.symbol = legacyImmersivePanel.value(QStringLiteral("symbol")).toString().trimmed();
            if (out.symbol.isEmpty()) out.symbol = QStringLiteral("extension");
        }
        if (out.title.isEmpty()) out.title = m.name;
        return true;
    };

    // Parse unified "ui" block (preferred) and legacy "slots" block
    const auto parseSlotsObject = [&](const QJsonObject &slotsObj) -> bool {
        for (auto it = slotsObj.constBegin(); it != slotsObj.constEnd(); ++it) {
            const QString slotName = it.key().trimmed();
            if (slotName.isEmpty()) continue;
            if (it.value().isArray()) {
                const QJsonArray arr = it.value().toArray();
                for (int i = 0; i < arr.size(); ++i) {
                    ModSlotItem item;
                    if (!parseSlotContribution(slotName, arr.at(i), i, item)) {
                        return false;
                    }
                    m.slotsMap[slotName].append(std::move(item));
                }
            } else {
                ModSlotItem item;
                if (!parseSlotContribution(slotName, it.value(), 0, item)) {
                    return false;
                }
                m.slotsMap[slotName].append(std::move(item));
            }
        }
        return true;
    };

    if (!parseSlotsObject(root.value(QStringLiteral("slots")).toObject())) {
        return m;
    }
    if (!parseSlotsObject(root.value(QStringLiteral("ui")).toObject())) {
        return m;
    }

    // Declarative shortcuts
    const QJsonArray shortcutsArr = root.value(QStringLiteral("shortcuts")).toArray();
    for (const QJsonValue &val : shortcutsArr) {
        if (!val.isObject()) continue;
        const QJsonObject obj = val.toObject();
        const QString scId = obj.value(QStringLiteral("id")).toString().trimmed();
        const QString seq = obj.value(QStringLiteral("sequence")).toString().trimmed();
        if (scId.isEmpty() || seq.isEmpty()) continue;
        m.shortcuts.append({
            scId,
            seq,
            obj.value(QStringLiteral("description")).toString().trimmed(),
        });
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

    m.valid = true;
    return m;
}

} // namespace ymusic::mods
