#include "mods/ModManager.h"

#include "AppSettings.h"
#include "app/Paths.h"
#include "mods/ModApi.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJSEngine>
#include <QLoggingCategory>
#include <QQmlEngine>

namespace ymusic::mods {

Q_LOGGING_CATEGORY(lcMods, "ymusic.mods")

namespace {

ModManager *s_instance = nullptr;
constexpr int kMaxLogEntries = 200;

bool copyDirectoryRecursively(const QString &srcDirPath, const QString &dstDirPath)
{
    const QDir srcDir(srcDirPath);
    if (!srcDir.exists()) return false;
    if (!QDir().mkpath(dstDirPath)) return false;

    const auto entries = srcDir.entryInfoList(QDir::NoDotAndDotDot | QDir::AllEntries | QDir::NoSymLinks);
    for (const QFileInfo &entry : entries) {
        const QString dstPath = dstDirPath + u'/' + entry.fileName();
        if (entry.isDir()) {
            if (!copyDirectoryRecursively(entry.absoluteFilePath(), dstPath)) {
                return false;
            }
        } else if (entry.isFile()) {
            if (QFile::exists(dstPath)) {
                QFile::remove(dstPath);
            }
            if (!QFile::copy(entry.absoluteFilePath(), dstPath)) {
                return false;
            }
        }
    }
    return true;
}

} // namespace

ModManager::ModManager(AppSettings *settings,
                       YMusicBackend *backend,
                       ymusic::SpectrumSource *spectrum,
                       bool safeMode,
                       QObject *parent)
    : QObject(parent)
    , m_settings(settings)
    , m_backend(backend)
    , m_spectrum(spectrum)
    , m_safeMode(safeMode)
{
    if (!s_instance) {
        s_instance = this;
    }

    m_watchDebounce.setSingleShot(true);
    m_watchDebounce.setInterval(250);
    connect(&m_watchDebounce, &QTimer::timeout, this, &ModManager::reloadMods);
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this]() {
        if (m_settings && m_settings->modDevMode()) {
            m_watchDebounce.start();
        }
    });
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this]() {
        if (m_settings && m_settings->modDevMode()) {
            m_watchDebounce.start();
        }
    });

    if (m_settings) {
        connect(m_settings, &AppSettings::modsSettingsChanged, this, [this]() {
            scanAndSync(false);
        });
    }

    if (m_safeMode) {
        appendLog(QStringLiteral("system"), QStringLiteral("warn"),
                  QStringLiteral("Запущен безопасный режим (--safe-mode / Shift): все моды и оверрайды отключены."));
    }

    scanAndSync(true);
}

ModManager::~ModManager()
{
    destroyAllApis();
    m_interceptor.clear();
    if (s_instance == this) {
        s_instance = nullptr;
    }
}

ModManager *ModManager::instance()
{
    return s_instance;
}

ModManager *ModManager::create(QQmlEngine *, QJSEngine *)
{
    QJSEngine::setObjectOwnership(s_instance, QJSEngine::CppOwnership);
    return s_instance;
}

void ModManager::attachEngine(QQmlEngine *engine)
{
    m_engine = engine;
}

bool ModManager::modsEnabled() const
{
    return !m_safeMode && (!m_settings || m_settings->modsEnabled());
}

int ModManager::activeModCount() const
{
    return static_cast<int>(m_apis.size());
}

void ModManager::destroyAllApis()
{
    const auto apis = m_apis.values();
    m_apis.clear();
    for (const QPointer<ModApi> &api : apis) {
        if (api) {
            api->disconnect();
            api->deleteLater();
        }
    }
    if (!m_trackMenuActions.isEmpty()) {
        m_trackMenuActions.clear();
        emit trackMenuActionsChanged();
    }
}

void ModManager::scanAndSync(bool initialStartup)
{
    m_manifests.clear();
    m_overrideConflicts.clear();

    const QDir modsDir(ymusic::paths::modsDirectory());
    if (modsDir.exists()) {
        const auto subdirs = modsDir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::NoSymLinks, QDir::Name);
        for (const QFileInfo &dirInfo : subdirs) {
            m_manifests.append(parseManifest(dirInfo.absoluteFilePath()));
        }
    }

    const QStringList enabledIds = m_settings ? m_settings->enabledModIds() : QStringList();
    QHash<QString, QUrl> activeOverrides;
    QHash<QString, QString> overrideOwners;
    QHash<QString, QString> currentOverridesSnapshot;

    if (modsEnabled()) {
        for (const ModManifest &m : m_manifests) {
            if (!m.valid || !enabledIds.contains(m.id)) continue;
            if (!m.hasPermission(QStringLiteral("ui:override"))) continue;
            for (auto it = m.overridesMap.constBegin(); it != m.overridesMap.constEnd(); ++it) {
                const QString &target = it.key();
                const QString &localPath = it.value();
                if (overrideOwners.contains(target)) {
                    const QString prevOwner = overrideOwners.value(target);
                    m_overrideConflicts[m.id].append(target + QStringLiteral(" (конфликт с ") + prevOwner + u')');
                    m_overrideConflicts[prevOwner].append(target + QStringLiteral(" (перекрыт ") + m.id + u')');
                }
                overrideOwners.insert(target, m.id);
                activeOverrides.insert(target, QUrl::fromLocalFile(localPath));
                currentOverridesSnapshot.insert(target, localPath);
            }
        }
    }

    m_interceptor.setOverrides(activeOverrides);
    if (initialStartup) {
        m_startupOverrides = currentOverridesSnapshot;
        m_overridesNeedRestart = false;
    } else {
        m_overridesNeedRestart = (currentOverridesSnapshot != m_startupOverrides);
    }

    rebuildApis();
    rebuildWatcher();

    ++m_reloadRevision;
    emit modsChanged();
    emit reloadRevisionChanged();
}

void ModManager::rebuildApis()
{
    destroyAllApis();
    if (!modsEnabled()) return;

    const QStringList enabledIds = m_settings ? m_settings->enabledModIds() : QStringList();
    for (const ModManifest &m : m_manifests) {
        if (!m.valid || !enabledIds.contains(m.id)) continue;
        auto *api = new ModApi(m, this, m_backend, m_spectrum, this);
        QJSEngine::setObjectOwnership(api, QJSEngine::CppOwnership);
        m_apis.insert(m.id, api);
    }
}

void ModManager::rebuildWatcher()
{
    const QStringList watched = m_watcher.files() + m_watcher.directories();
    if (!watched.isEmpty()) {
        m_watcher.removePaths(watched);
    }
    if (!modsEnabled() || !m_settings || !m_settings->modDevMode()) {
        return;
    }

    const QString rootPath = ymusic::paths::modsDirectory();
    if (QDir(rootPath).exists()) {
        m_watcher.addPath(rootPath);
    }
    const QStringList enabledIds = m_settings->enabledModIds();
    for (const ModManifest &m : m_manifests) {
        if (!m.valid || !enabledIds.contains(m.id)) continue;
        m_watcher.addPath(m.directory);
        QDirIterator it(m.directory, QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
        int cap = 0;
        while (it.hasNext() && cap < 128) {
            m_watcher.addPath(it.next());
            ++cap;
        }
    }
}

void ModManager::reloadMods()
{
    if (m_engine) {
        m_engine->clearComponentCache();
        m_engine->collectGarbage();
    }
    appendLog(QStringLiteral("system"), QStringLiteral("info"), QStringLiteral("Моды перезагружены."));
    scanAndSync(false);
}

void ModManager::setModEnabled(const QString &modId, bool enabled)
{
    if (!m_settings || modId.isEmpty()) return;
    QStringList ids = m_settings->enabledModIds();
    const bool wasEnabled = ids.contains(modId);
    if (enabled) {
        if (!wasEnabled) {
            ids.append(modId);
        }
    } else {
        ids.removeAll(modId);
    }
    if (wasEnabled != enabled) {
        m_pendingRestartPrompt = true;
    }
    m_settings->setEnabledModIds(ids);
}

void ModManager::dismissRestartPrompt()
{
    if (m_pendingRestartPrompt) {
        m_pendingRestartPrompt = false;
        emit modsChanged();
    }
}

void ModManager::requestAppRestart()
{
    m_pendingRestartPrompt = false;
    m_restartRequested = true;
    QCoreApplication::quit();
}

void ModManager::quarantineOverrideMods(const QString &reason)
{
    m_interceptor.clear();
    if (m_settings) {
        QStringList ids = m_settings->enabledModIds();
        for (const ModManifest &m : m_manifests) {
            if (!m.overridesMap.isEmpty()) {
                ids.removeAll(m.id);
                appendLog(m.id, QStringLiteral("error"),
                          QStringLiteral("Мод с UI-оверрайдом отправлен в карантин после ошибки старта: %1").arg(reason));
            }
        }
        m_settings->setEnabledModIds(ids);
    }
    scanAndSync(true);
}

QVariantList ModManager::modsVariantList() const
{
    const QStringList enabledIds = m_settings ? m_settings->enabledModIds() : QStringList();
    QVariantList list;
    list.reserve(m_manifests.size());
    for (const ModManifest &m : m_manifests) {
        QVariantMap item;
        item.insert(QStringLiteral("id"), m.id);
        item.insert(QStringLiteral("name"), m.name);
        item.insert(QStringLiteral("version"), m.version);
        item.insert(QStringLiteral("author"), m.author);
        item.insert(QStringLiteral("description"), m.description);
        item.insert(QStringLiteral("directory"), m.directory);
        item.insert(QStringLiteral("valid"), m.valid);
        item.insert(QStringLiteral("error"), m.error);
        item.insert(QStringLiteral("enabled"), m.valid && enabledIds.contains(m.id));
        item.insert(QStringLiteral("permissions"), m.permissions);
        item.insert(QStringLiteral("hasOverrides"), !m.overridesMap.isEmpty());
        item.insert(QStringLiteral("overrideCount"), static_cast<int>(m.overridesMap.size()));
        item.insert(QStringLiteral("hasSettings"), !m.settingsEntry.isEmpty());
        item.insert(QStringLiteral("settingsUrl"), m.settingsEntry.isEmpty() ? QUrl() : QUrl::fromLocalFile(m.settingsEntry));
        item.insert(QStringLiteral("conflicts"), m_overrideConflicts.value(m.id));
        list.append(item);
    }
    return list;
}

QVariantList ModManager::slotEntries(const QString &slotName) const
{
    QVariantList entries;
    if (!modsEnabled() || slotName.isEmpty()) {
        return entries;
    }

    const QStringList enabledIds = m_settings ? m_settings->enabledModIds() : QStringList();
    for (const ModManifest &m : m_manifests) {
        if (!m.valid || !enabledIds.contains(m.id)) continue;
        QString filePath;
        if (slotName == QLatin1StringView("background.host")) {
            filePath = m.scriptEntry;
        } else if (slotName == QLatin1StringView("settings")) {
            filePath = m.settingsEntry;
        } else {
            if (!m.hasPermission(QStringLiteral("ui:slots"))) continue;
            filePath = m.slotsMap.value(slotName);
        }
        if (filePath.isEmpty()) continue;

        ModApi *api = m_apis.value(m.id).data();
        if (!api) continue;

        QVariantMap entry;
        entry.insert(QStringLiteral("modId"), m.id);
        entry.insert(QStringLiteral("modName"), m.name);
        entry.insert(QStringLiteral("sourceUrl"), QUrl::fromLocalFile(filePath));
        entry.insert(QStringLiteral("title"), m.sidebarTitle);
        entry.insert(QStringLiteral("symbol"), m.sidebarSymbol);
        entry.insert(QStringLiteral("settingsTabTitle"), m.settingsTabTitle);
        entry.insert(QStringLiteral("settingsTabSymbol"), m.settingsTabSymbol);
        entry.insert(QStringLiteral("settingsTabShape"), m.settingsTabShape);
        entry.insert(QStringLiteral("immersivePanelTitle"), m.immersivePanelTitle);
        entry.insert(QStringLiteral("immersivePanelSymbol"), m.immersivePanelSymbol);
        entry.insert(QStringLiteral("api"), QVariant::fromValue(static_cast<QObject *>(api)));
        entries.append(entry);
    }
    return entries;
}

bool ModManager::hasSlot(const QString &slotName) const
{
    if (!modsEnabled() || slotName.isEmpty()) return false;
    const QStringList enabledIds = m_settings ? m_settings->enabledModIds() : QStringList();
    for (const ModManifest &m : m_manifests) {
        if (!m.valid || !enabledIds.contains(m.id)) continue;
        if (slotName == QLatin1StringView("background.host")) {
            if (!m.scriptEntry.isEmpty()) return true;
        } else if (slotName == QLatin1StringView("settings")) {
            if (!m.settingsEntry.isEmpty()) return true;
        } else if (m.hasPermission(QStringLiteral("ui:slots")) && m.slotsMap.contains(slotName)) {
            return true;
        }
    }
    return false;
}

ModApi *ModManager::apiForMod(const QString &modId) const
{
    return m_apis.value(modId).data();
}

void ModManager::registerTrackMenuAction(const QString &modId,
                                         const QString &actionId,
                                         const QString &label,
                                         const QString &symbol,
                                         bool destructive)
{
    for (ModTrackMenuAction &existing : m_trackMenuActions) {
        if (existing.modId == modId && existing.actionId == actionId) {
            existing.label = label;
            existing.symbol = symbol;
            existing.destructive = destructive;
            emit trackMenuActionsChanged();
            return;
        }
    }
    m_trackMenuActions.append({modId, actionId, label, symbol, destructive});
    emit trackMenuActionsChanged();
}

void ModManager::unregisterTrackMenuAction(const QString &modId, const QString &actionId)
{
    const auto before = m_trackMenuActions.size();
    m_trackMenuActions.removeIf([&](const ModTrackMenuAction &a) {
        return a.modId == modId && a.actionId == actionId;
    });
    if (m_trackMenuActions.size() != before) {
        emit trackMenuActionsChanged();
    }
}

void ModManager::clearTrackMenuActionsForMod(const QString &modId)
{
    const auto before = m_trackMenuActions.size();
    m_trackMenuActions.removeIf([&](const ModTrackMenuAction &a) {
        return a.modId == modId;
    });
    if (m_trackMenuActions.size() != before) {
        emit trackMenuActionsChanged();
    }
}

QVariantList ModManager::trackMenuActionsVariantList() const
{
    QVariantList list;
    list.reserve(m_trackMenuActions.size());
    for (const ModTrackMenuAction &a : m_trackMenuActions) {
        QVariantMap map;
        map.insert(QStringLiteral("modId"), a.modId);
        map.insert(QStringLiteral("actionId"), a.actionId);
        map.insert(QStringLiteral("label"), a.label);
        map.insert(QStringLiteral("symbol"), a.symbol);
        map.insert(QStringLiteral("destructive"), a.destructive);
        list.append(map);
    }
    return list;
}

void ModManager::triggerTrackMenuAction(const QString &modId,
                                        const QString &actionId,
                                        const QString &trackId,
                                        const QString &trackTitle)
{
    if (ModApi *api = m_apis.value(modId).data()) {
        api->notifyTrackMenuAction(actionId, trackId, trackTitle);
    }
}

void ModManager::reportModError(const QString &modId, const QString &message)
{
    appendLog(modId, QStringLiteral("error"), message);
}

void ModManager::appendLog(const QString &modId, const QString &level, const QString &message)
{
    const QString trimmed = message.trimmed();
    if (trimmed.isEmpty()) return;

    if (level == QLatin1StringView("error")) {
        qCWarning(lcMods).noquote() << QStringLiteral("[%1] ERROR: %2").arg(modId, trimmed);
    } else if (level == QLatin1StringView("warn")) {
        qCWarning(lcMods).noquote() << QStringLiteral("[%1] WARN: %2").arg(modId, trimmed);
    } else {
        qCInfo(lcMods).noquote() << QStringLiteral("[%1] %2").arg(modId, trimmed);
    }

    m_logs.append({
        QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss")),
        modId,
        level,
        trimmed.left(400),
    });
    while (m_logs.size() > kMaxLogEntries) {
        m_logs.removeFirst();
    }
    emit logsChanged();
}

QVariantList ModManager::logsVariantList() const
{
    QVariantList list;
    list.reserve(m_logs.size());
    for (const ModLogEntry &e : m_logs) {
        QVariantMap map;
        map.insert(QStringLiteral("time"), e.time);
        map.insert(QStringLiteral("modId"), e.modId);
        map.insert(QStringLiteral("level"), e.level);
        map.insert(QStringLiteral("message"), e.message);
        list.append(map);
    }
    return list;
}

void ModManager::clearLogs()
{
    if (!m_logs.isEmpty()) {
        m_logs.clear();
        emit logsChanged();
    }
}

bool ModManager::openModsFolder() const
{
    return ymusic::paths::openDirectory(ymusic::paths::modsDirectory());
}

QVariantMap ModManager::installModFromFolder(const QUrl &folderUrl)
{
    const QString srcPath = folderUrl.isLocalFile() ? folderUrl.toLocalFile() : folderUrl.toString();
    const QFileInfo srcInfo(srcPath);
    if (!srcInfo.isDir()) {
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Выбранный путь не является папкой")}};
    }

    const ModManifest parsed = parseManifest(srcInfo.absoluteFilePath());
    if (!parsed.valid) {
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), parsed.error}};
    }

    const QString dstPath = ymusic::paths::modsDirectory() + u'/' + parsed.id;
    const QFileInfo dstInfo(dstPath);
    if (dstInfo.exists() && dstInfo.canonicalFilePath() == srcInfo.canonicalFilePath()) {
        scanAndSync(false);
        return {{QStringLiteral("ok"), true}, {QStringLiteral("id"), parsed.id}, {QStringLiteral("name"), parsed.name}};
    }

    if (dstInfo.exists()) {
        QDir(dstPath).removeRecursively();
    }
    if (!copyDirectoryRecursively(srcInfo.absoluteFilePath(), dstPath)) {
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Не удалось скопировать файлы мода")}};
    }

    appendLog(parsed.id, QStringLiteral("info"), QStringLiteral("Установлен мод «%1» v%2").arg(parsed.name, parsed.version));
    scanAndSync(false);
    return {{QStringLiteral("ok"), true}, {QStringLiteral("id"), parsed.id}, {QStringLiteral("name"), parsed.name}};
}

bool ModManager::uninstallMod(const QString &modId)
{
    if (!isValidModId(modId)) return false;
    setModEnabled(modId, false);

    const QString targetDir = ymusic::paths::modsDirectory() + u'/' + modId;
    const QFileInfo targetInfo(targetDir);
    const QString baseCanonical = QFileInfo(ymusic::paths::modsDirectory()).canonicalFilePath();
    if (!targetInfo.isDir() || baseCanonical.isEmpty()
        || !targetInfo.canonicalFilePath().startsWith(baseCanonical + u'/')) {
        return false;
    }

    if (!QDir(targetInfo.canonicalFilePath()).removeRecursively()) {
        return false;
    }
    appendLog(modId, QStringLiteral("info"), QStringLiteral("Мод удалён."));
    scanAndSync(false);
    return true;
}

} // namespace ymusic::mods
