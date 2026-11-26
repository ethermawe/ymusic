#include "mods/ModManager.h"

#include "AppSettings.h"
#include "app/Paths.h"
#include "mods/ModApi.h"
#include "mods/ModNetworkAccessManager.h"
#include "mods/ModScriptHost.h"
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
#include "YMusicBackend.h"
#include "artwork/ArtworkCache.h"
#endif

#include <QCoreApplication>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJSEngine>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLoggingCategory>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlError>
#include <QSet>
#include <QTemporaryDir>
#include <QVersionNumber>

#if __has_include(<QtCore/private/qzipreader_p.h>)
#include <QtCore/private/qzipreader_p.h>
#elif __has_include(<QtGui/private/qzipreader_p.h>)
#include <QtGui/private/qzipreader_p.h>
#else
#error "QZipReader private header not found"
#endif

#include <algorithm>
#include <limits>

namespace ymusic::mods {

Q_LOGGING_CATEGORY(lcMods, "ymusic.mods")

namespace {

ModManager *s_instance = nullptr;
constexpr int kMaxLogEntries = 200;
constexpr int kMaxArchiveFiles = 2000;
constexpr qint64 kMaxArchiveBytes = 50LL * 1024 * 1024;

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

#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    if (m_backend) {
        connect(m_backend, &YMusicBackend::hookRequestReceived, this, &ModManager::handleHookRequest);
        connect(m_backend, &YMusicBackend::modWarningReceived, this, [this](const QString &msg) {
            appendLog(QStringLiteral("hooks"), QStringLiteral("warn"), msg);
        });
        connect(m_backend, &YMusicBackend::nowPlayingChanged, this, [this]() {
            QVariantMap data{
                {QStringLiteral("id"), m_backend->nowId()},
                {QStringLiteral("title"), m_backend->nowTitle()},
                {QStringLiteral("artists"), m_backend->nowArtists()},
                {QStringLiteral("album"), m_backend->nowAlbum()},
            };
            for (const QString &id : m_scriptOrder) {
                if (auto *host = m_scriptHosts.value(id).data()) {
                    host->dispatchEvent(QStringLiteral("trackChanged"), data);
                }
            }
        });
        connect(m_backend, &YMusicBackend::playbackStateChanged, this, [this]() {
            QVariantMap data{{QStringLiteral("playing"), m_backend->playing()}};
            for (const QString &id : m_scriptOrder) {
                if (auto *host = m_scriptHosts.value(id).data()) {
                    host->dispatchEvent(QStringLiteral("playbackChanged"), data);
                }
            }
        });
    }
#endif

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

void ModManager::destroyAllSandboxes()
{
    for (auto it = m_sandboxes.begin(); it != m_sandboxes.end(); ++it) {
        if (it.value().engine) {
            it.value().engine->removeUrlInterceptor(it.value().urlInterceptor.get());
            delete it.value().engine.data();
        }
    }
    m_sandboxes.clear();
}

const ModManifest *ModManager::manifestForMod(const QString &modId) const
{
    for (const ModManifest &m : m_manifests) {
        if (m.id == modId) {
            return &m;
        }
    }
    return nullptr;
}

QString ModManager::modDirectoryForMod(const QString &modId) const
{
    if (const ModManifest *m = manifestForMod(modId)) {
        return m->directory;
    }
    return {};
}

QQmlEngine *ModManager::sandboxEngineForMod(const QString &modId)
{
    if (!modsEnabled() || modId.isEmpty() || !m_apis.contains(modId)) {
        return nullptr;
    }
    auto existing = m_sandboxes.find(modId);
    if (existing != m_sandboxes.end() && existing.value().engine) {
        return existing.value().engine.data();
    }

    const ModManifest *manifest = manifestForMod(modId);
    if (!manifest || !manifest->valid) {
        return nullptr;
    }

    auto *eng = new QQmlEngine(this);
    QPointer<ModManager> self(this);
    auto onError = [self](const QString &id, const QString &msg) {
        if (self) {
            self->reportModError(id, msg);
        }
    };

    auto interceptor = std::make_shared<ModSandboxUrlInterceptor>(manifest->id, manifest->directory, onError);
    eng->addUrlInterceptor(interceptor.get());
    eng->setNetworkAccessManagerFactory(new ModNetworkAccessManagerFactory(*manifest, onError));
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    eng->addImageProvider(QStringLiteral("art"), new ymusic::ArtworkImageProvider);
#endif

    // Best-effort JS hardening inside the mod engine (Qt object methods are C++ Q_INVOKABLE and may be non-writable).
    eng->evaluate(QStringLiteral(
        "(function(){"
        "  try { Object.defineProperty(Qt, 'openUrlExternally', { value: function(){ return false; }, writable: false, configurable: false }); } catch(e) {}"
        "  try { Object.defineProperty(Qt, 'createQmlObject', { value: function(){ throw new Error('Qt.createQmlObject is disabled in mod sandbox'); }, writable: false, configurable: false }); } catch(e) {}"
        "})();"));

    ModSandbox sb;
    sb.engine = eng;
    sb.urlInterceptor = std::move(interceptor);
    m_sandboxes.insert(modId, std::move(sb));
    return eng;
}

QObject *ModManager::createSandboxedObject(const QString &modId,
                                           const QUrl &sourceUrl,
                                           const QVariantMap &slotContext,
                                           QString *errorOut)
{
    ModApi *api = apiForMod(modId);
    QQmlEngine *modEngine = sandboxEngineForMod(modId);
    const QString modDir = modDirectoryForMod(modId);
    if (!api || !modEngine || modDir.isEmpty()) {
        if (errorOut) *errorOut = QStringLiteral("Мод не активен: %1").arg(modId);
        return nullptr;
    }

    if (sourceUrl.isLocalFile()) {
        QString importErr;
        if (!validateModQmlImports(sourceUrl.toLocalFile(), modDir, &importErr)) {
            reportModError(modId, importErr);
            if (errorOut) *errorOut = importErr;
            return nullptr;
        }
    }

    auto *modCtx = new QQmlContext(modEngine->rootContext(), modEngine);
    modCtx->setContextProperty(QStringLiteral("modApi"), api);
    modCtx->setContextProperty(QStringLiteral("slotContext"), slotContext);

    QQmlComponent component(modEngine, sourceUrl, QQmlComponent::PreferSynchronous);
    if (component.isError()) {
        QStringList errs;
        for (const QQmlError &e : component.errors()) {
            errs.append(e.toString());
        }
        const QString msg = errs.join(QStringLiteral(" | "));
        delete modCtx;
        reportModError(modId, msg);
        if (errorOut) *errorOut = msg;
        return nullptr;
    }

    QObject *obj = component.beginCreate(modCtx);
    if (!obj) {
        QStringList errs;
        for (const QQmlError &e : component.errors()) {
            errs.append(e.toString());
        }
        const QString msg = errs.isEmpty() ? sourceUrl.toString() : errs.join(QStringLiteral(" | "));
        delete modCtx;
        reportModError(modId, msg);
        if (errorOut) *errorOut = msg;
        return nullptr;
    }

    if (obj->metaObject()->indexOfProperty("modApi") >= 0) {
        obj->setProperty("modApi", QVariant::fromValue(static_cast<QObject *>(api)));
    }
    if (obj->metaObject()->indexOfProperty("slotContext") >= 0) {
        obj->setProperty("slotContext", slotContext);
    }

    component.completeCreate();
    if (component.isError()) {
        QStringList errs;
        for (const QQmlError &e : component.errors()) {
            errs.append(e.toString());
        }
        const QString msg = errs.join(QStringLiteral(" | "));
        delete obj;
        delete modCtx;
        reportModError(modId, msg);
        if (errorOut) *errorOut = msg;
        return nullptr;
    }

    modCtx->setParent(obj);
    return obj;
}

void ModManager::destroyAllScripts()
{
    const QStringList order = m_scriptOrder;
    m_scriptOrder.clear();
    for (int i = order.size() - 1; i >= 0; --i) {
        if (ModScriptHost *host = m_scriptHosts.take(order.at(i)).data()) {
            host->disconnect(this);
            host->deactivate();
            delete host;
        }
    }
    for (const QPointer<ModScriptHost> &host : m_scriptHosts) {
        if (host) {
            host->disconnect(this);
            host->deactivate();
            delete host.data();
        }
    }
    m_scriptHosts.clear();
    m_dynamicPages.clear();
    syncHookSubscriptions();
}

void ModManager::syncHookSubscriptions()
{
    QStringList nextPoints;
    for (const QString &id : m_scriptOrder) {
        if (const ModScriptHost *host = m_scriptHosts.value(id).data()) {
            for (const QString &pt : host->subscribedHookPoints()) {
                if (!nextPoints.contains(pt)) {
                    nextPoints.append(pt);
                }
            }
        }
    }
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    if (m_backend) {
        for (const QString &oldPt : m_subscribedHookPoints) {
            if (!nextPoints.contains(oldPt)) {
                m_backend->hookSubscribe(oldPt, false);
            }
        }
        for (const QString &newPt : nextPoints) {
            if (!m_subscribedHookPoints.contains(newPt)) {
                m_backend->hookSubscribe(newPt, true);
            }
        }
    }
#endif
    m_subscribedHookPoints = nextPoints;
}

QVariantMap ModManager::runHookChain(const QString &point, const QVariant &payload)
{
    QVariant current = payload;
    for (const QString &id : m_scriptOrder) {
        ModScriptHost *host = m_scriptHosts.value(id).data();
        if (!host || !host->isLoaded()) continue;
        const HookInvokeResult res = host->invokeHook(point, current);
        if (res.cancelled) {
            return {
                {QStringLiteral("action"), QStringLiteral("cancel")},
                {QStringLiteral("reason"), res.cancelReason},
            };
        }
        if (res.handled) {
            current = res.payload;
        }
    }
    return {
        {QStringLiteral("action"), QStringLiteral("continue")},
        {QStringLiteral("payload"), current},
    };
}

void ModManager::handleHookRequest(quint64 id, const QString &point, const QVariant &payload)
{
    const QVariantMap result = runHookChain(point, payload);
#ifndef YMUSIC_MOD_TEST_NO_BACKEND
    if (m_backend) {
        const QByteArray json = QJsonDocument::fromVariant(result).toJson(QJsonDocument::Compact);
        m_backend->hookResponse(id, QString::fromUtf8(json));
    }
#else
    Q_UNUSED(id);
    Q_UNUSED(result);
#endif
}

void ModManager::registerDynamicPage(const QString &modId,
                                     const QString &pageId,
                                     const QString &title,
                                     const QString &icon,
                                     const QString &resolvedQmlPath)
{
    ModSlotItem item;
    item.entryId = modId + u':' + pageId;
    item.file = resolvedQmlPath;
    item.title = title;
    item.symbol = icon.isEmpty() ? QStringLiteral("extension") : icon;
    m_dynamicPages.append(qMakePair(modId, item));
    ++m_reloadRevision;
    emit reloadRevisionChanged();
}

QVariant ModManager::modExports(const QString &modId) const
{
    if (const ModScriptHost *host = m_scriptHosts.value(modId).data()) {
        return host->exportsVariant();
    }
    return {};
}

QVariant ModManager::callModExposed(const QString &modId, const QString &name, const QVariantList &args)
{
    if (ModScriptHost *host = m_scriptHosts.value(modId).data()) {
        return host->callExposed(name, args);
    }
    return {};
}

ModScriptHost *ModManager::scriptHostForMod(const QString &modId) const
{
    return m_scriptHosts.value(modId).data();
}

void ModManager::destroyAllApis()
{
    destroyAllScripts();
    destroyAllSandboxes();
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
    if (!m_shortcuts.isEmpty()) {
        m_shortcuts.clear();
        emit shortcutsChanged();
    }
    if (!m_lyricSubtitles.isEmpty()) {
        m_lyricSubtitles.clear();
        ++m_lyricSubtitlesRevision;
        emit lyricSubtitlesChanged();
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
            ModManifest parsed = parseManifest(dirInfo.absoluteFilePath());
            for (const QString &w : parsed.warnings) {
                appendLog(parsed.id, QStringLiteral("warn"), w);
            }
            m_manifests.append(std::move(parsed));
        }
    }

    // Validate manifest dependencies (modId -> ">=x.y")
    QHash<QString, QVersionNumber> validVersions;
    for (const ModManifest &m : m_manifests) {
        if (m.valid) {
            validVersions.insert(m.id, QVersionNumber::fromString(m.version));
        }
    }
    for (ModManifest &m : m_manifests) {
        if (!m.valid || m.dependencies.isEmpty()) continue;
        for (auto it = m.dependencies.constBegin(); it != m.dependencies.constEnd(); ++it) {
            const QString &depId = it.key();
            const QString &constraint = it.value();
            if (!validVersions.contains(depId)) {
                m.valid = false;
                m.error = QStringLiteral("Отсутствует обязательная зависимость: %1 (%2)").arg(depId, constraint);
                break;
            }
            if (constraint.startsWith(QLatin1StringView(">="))) {
                const QVersionNumber req = QVersionNumber::fromString(constraint.mid(2).trimmed());
                const QVersionNumber actual = validVersions.value(depId);
                if (!req.isNull() && !actual.isNull() && actual < req) {
                    m.valid = false;
                    m.error = QStringLiteral("Зависимость '%1' версии %2 не удовлетворяет %3")
                                  .arg(depId, actual.toString(), constraint);
                    break;
                }
            }
        }
    }

    // Apply persisted load order (earlier in list = higher priority for overrides and slots)
    const QStringList order = m_settings ? m_settings->modOrder() : QStringList();
    if (!order.isEmpty() && m_manifests.size() > 1) {
        QHash<QString, int> rank;
        rank.reserve(order.size());
        for (int i = 0; i < order.size(); ++i) {
            rank.insert(order.at(i), i);
        }
        std::stable_sort(m_manifests.begin(), m_manifests.end(), [&](const ModManifest &a, const ModManifest &b) {
            const int ra = rank.value(a.id, std::numeric_limits<int>::max());
            const int rb = rank.value(b.id, std::numeric_limits<int>::max());
            if (ra != rb) return ra < rb;
            return a.id < b.id;
        });
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
                    const QString winner = overrideOwners.value(target);
                    m_overrideConflicts[m.id].append(target + QStringLiteral(" (перекрыт приоритетным ") + winner + u')');
                    m_overrideConflicts[winner].append(target + QStringLiteral(" (приоритет над ") + m.id + u')');
                    continue;
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
    QList<const ModManifest *> activeManifests;
    QHash<QString, const ModManifest *> activeById;
    for (const ModManifest &m : m_manifests) {
        if (!m.valid || !enabledIds.contains(m.id)) continue;
        auto *api = new ModApi(m, this, m_backend, m_spectrum, this);
        QJSEngine::setObjectOwnership(api, QJSEngine::CppOwnership);
        m_apis.insert(m.id, api);
        activeManifests.append(&m);
        activeById.insert(m.id, &m);
    }

    // Topological sort for JS script activation (dependencies activate before dependents)
    QList<const ModManifest *> ordered;
    QSet<QString> visited;
    QSet<QString> visiting;
    std::function<void(const ModManifest *)> visit = [&](const ModManifest *m) {
        if (!m || visited.contains(m->id) || visiting.contains(m->id)) return;
        visiting.insert(m->id);
        for (auto it = m->dependencies.constBegin(); it != m->dependencies.constEnd(); ++it) {
            if (const ModManifest *dep = activeById.value(it.key(), nullptr)) {
                visit(dep);
            }
        }
        visiting.remove(m->id);
        visited.insert(m->id);
        ordered.append(m);
    };
    for (const ModManifest *m : activeManifests) {
        visit(m);
    }

    for (const ModManifest *m : ordered) {
        if (m->mainScript.isEmpty()) continue;
        ModApi *api = m_apis.value(m->id).data();
        auto *host = new ModScriptHost(*m, this, api, this);
        connect(host, &ModScriptHost::hookSubscriptionsChanged, this, &ModManager::syncHookSubscriptions);
        connect(host, &ModScriptHost::autoDisabled, this, [this](const QString &id) {
            QTimer::singleShot(0, this, [this, id]() {
                setModEnabled(id, false);
            });
        });
        m_scriptHosts.insert(m->id, host);
        m_scriptOrder.append(m->id);
        host->loadAndActivate();
    }
    syncHookSubscriptions();
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

void ModManager::moveMod(const QString &modId, int delta)
{
    if (!m_settings || modId.isEmpty() || delta == 0 || m_manifests.size() < 2) return;
    QStringList order;
    order.reserve(m_manifests.size());
    for (const ModManifest &m : m_manifests) {
        order.append(m.id);
    }
    const int idx = order.indexOf(modId);
    const int nextIdx = idx + delta;
    if (idx < 0 || nextIdx < 0 || nextIdx >= order.size()) return;

    const bool affectsOverrides = !m_manifests.at(idx).overridesMap.isEmpty()
        || !m_manifests.at(nextIdx).overridesMap.isEmpty();
    order.swapItemsAt(idx, nextIdx);
    if (affectsOverrides) {
        m_pendingRestartPrompt = true;
    }
    m_settings->setModOrder(order);
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
        item.insert(QStringLiteral("warnings"), m.warnings);
        item.insert(QStringLiteral("apiVersion"), m.apiVersion);
        item.insert(QStringLiteral("enabled"), m.valid && enabledIds.contains(m.id));
        item.insert(QStringLiteral("permissions"), m.permissions);
        item.insert(QStringLiteral("hasOverrides"), !m.overridesMap.isEmpty());
        item.insert(QStringLiteral("overrideCount"), static_cast<int>(m.overridesMap.size()));
        item.insert(QStringLiteral("overrideTargets"), QStringList(m.overridesMap.keys()));
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
        ModApi *api = m_apis.value(m.id).data();
        if (!api) continue;

        if (slotName == QLatin1StringView("background.host")) {
            if (m.scriptEntry.isEmpty()) continue;
            QVariantMap entry;
            entry.insert(QStringLiteral("entryId"), m.id);
            entry.insert(QStringLiteral("modId"), m.id);
            entry.insert(QStringLiteral("modName"), m.name);
            entry.insert(QStringLiteral("sourceUrl"), QUrl::fromLocalFile(m.scriptEntry));
            entry.insert(QStringLiteral("api"), QVariant::fromValue(static_cast<QObject *>(api)));
            entries.append(entry);
            continue;
        }
        if (slotName == QLatin1StringView("settings")) {
            if (m.settingsEntry.isEmpty()) continue;
            QVariantMap entry;
            entry.insert(QStringLiteral("entryId"), m.id);
            entry.insert(QStringLiteral("modId"), m.id);
            entry.insert(QStringLiteral("modName"), m.name);
            entry.insert(QStringLiteral("sourceUrl"), QUrl::fromLocalFile(m.settingsEntry));
            entry.insert(QStringLiteral("api"), QVariant::fromValue(static_cast<QObject *>(api)));
            entries.append(entry);
            continue;
        }

        if (!m.hasPermission(QStringLiteral("ui:slots"))) continue;
        const auto items = m.slotsMap.value(slotName);
        for (const ModSlotItem &s : items) {
            QVariantMap entry;
            entry.insert(QStringLiteral("entryId"), s.entryId);
            entry.insert(QStringLiteral("modId"), m.id);
            entry.insert(QStringLiteral("modName"), m.name);
            entry.insert(QStringLiteral("sourceUrl"), QUrl::fromLocalFile(s.file));
            entry.insert(QStringLiteral("title"), s.title);
            entry.insert(QStringLiteral("symbol"), s.symbol);
            entry.insert(QStringLiteral("shape"), s.shape);
            // Legacy alias keys kept for compatibility
            entry.insert(QStringLiteral("settingsTabTitle"), s.title);
            entry.insert(QStringLiteral("settingsTabSymbol"), s.symbol);
            entry.insert(QStringLiteral("settingsTabShape"), s.shape);
            entry.insert(QStringLiteral("immersivePanelTitle"), s.title);
            entry.insert(QStringLiteral("immersivePanelSymbol"), s.symbol);
            entry.insert(QStringLiteral("api"), QVariant::fromValue(static_cast<QObject *>(api)));
            entries.append(entry);
        }
    }

    if (slotName == QLatin1StringView("sidebar.page")) {
        for (const auto &pair : m_dynamicPages) {
            ModApi *api = m_apis.value(pair.first).data();
            if (!api) continue;
            const ModSlotItem &s = pair.second;
            QVariantMap entry;
            entry.insert(QStringLiteral("entryId"), s.entryId);
            entry.insert(QStringLiteral("modId"), pair.first);
            entry.insert(QStringLiteral("modName"), api->modName());
            entry.insert(QStringLiteral("sourceUrl"), QUrl::fromLocalFile(s.file));
            entry.insert(QStringLiteral("title"), s.title);
            entry.insert(QStringLiteral("symbol"), s.symbol);
            entry.insert(QStringLiteral("api"), QVariant::fromValue(static_cast<QObject *>(api)));
            entries.append(entry);
        }
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
        } else if (m.hasPermission(QStringLiteral("ui:slots")) && !m.slotsMap.value(slotName).isEmpty()) {
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

void ModManager::registerShortcut(const QString &modId,
                                  const QString &actionId,
                                  const QString &sequence,
                                  const QString &description)
{
    for (ModShortcutEntry &existing : m_shortcuts) {
        if (existing.modId == modId && existing.actionId == actionId) {
            existing.sequence = sequence;
            existing.description = description;
            emit shortcutsChanged();
            return;
        }
    }
    m_shortcuts.append({modId, actionId, sequence, description});
    emit shortcutsChanged();
}

void ModManager::unregisterShortcut(const QString &modId, const QString &actionId)
{
    const auto before = m_shortcuts.size();
    m_shortcuts.removeIf([&](const ModShortcutEntry &s) {
        return s.modId == modId && s.actionId == actionId;
    });
    if (m_shortcuts.size() != before) {
        emit shortcutsChanged();
    }
}

void ModManager::clearShortcutsForMod(const QString &modId)
{
    const auto before = m_shortcuts.size();
    m_shortcuts.removeIf([&](const ModShortcutEntry &s) {
        return s.modId == modId;
    });
    if (m_shortcuts.size() != before) {
        emit shortcutsChanged();
    }
}

QVariantList ModManager::shortcutsVariantList() const
{
    QVariantList list;
    list.reserve(m_shortcuts.size());
    for (const ModShortcutEntry &s : m_shortcuts) {
        QVariantMap map;
        map.insert(QStringLiteral("modId"), s.modId);
        map.insert(QStringLiteral("actionId"), s.actionId);
        map.insert(QStringLiteral("sequence"), s.sequence);
        map.insert(QStringLiteral("description"), s.description);
        list.append(map);
    }
    return list;
}

void ModManager::triggerShortcut(const QString &modId, const QString &actionId)
{
    if (ModScriptHost *host = m_scriptHosts.value(modId).data()) {
        if (host->invokeCommand(actionId)) {
            return;
        }
    }
    if (ModApi *api = m_apis.value(modId).data()) {
        api->notifyShortcut(actionId);
    }
}

void ModManager::syncLyricsState(const QString &trackId, bool synced, const QVariantList &lines)
{
    m_lyricsTrackId = trackId;
    m_lyricsSynced = synced;
    m_lyricsLines = lines;
    for (const QPointer<ModApi> &api : m_apis) {
        if (api) {
            api->notifyLyricsChanged();
        }
    }
}

void ModManager::setLyricSubtitles(const QString &modId, const QString &trackId, const QStringList &subtitles)
{
    m_lyricSubtitles.insert(modId, qMakePair(trackId, subtitles));
    ++m_lyricSubtitlesRevision;
    emit lyricSubtitlesChanged();
}

void ModManager::clearLyricSubtitlesForMod(const QString &modId)
{
    if (m_lyricSubtitles.remove(modId)) {
        ++m_lyricSubtitlesRevision;
        emit lyricSubtitlesChanged();
    }
}

QString ModManager::lyricSubtitleFor(const QString &trackId, int lineIndex) const
{
    if (trackId.isEmpty() || lineIndex < 0 || m_lyricSubtitles.isEmpty()) {
        return {};
    }
    for (auto it = m_lyricSubtitles.constBegin(); it != m_lyricSubtitles.constEnd(); ++it) {
        if (it.value().first == trackId && lineIndex < it.value().second.size()) {
            const QString &text = it.value().second.at(lineIndex);
            if (!text.isEmpty()) return text;
        }
    }
    return {};
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

    const bool hasOverrides = !parsed.overridesMap.isEmpty();
    const QStringList overrideTargets(parsed.overridesMap.keys());

    const QString dstPath = ymusic::paths::modsDirectory() + u'/' + parsed.id;
    const QFileInfo dstInfo(dstPath);
    if (dstInfo.exists() && dstInfo.canonicalFilePath() == srcInfo.canonicalFilePath()) {
        scanAndSync(false);
        return {
            {QStringLiteral("ok"), true},
            {QStringLiteral("id"), parsed.id},
            {QStringLiteral("name"), parsed.name},
            {QStringLiteral("hasOverrides"), hasOverrides},
            {QStringLiteral("overrideTargets"), overrideTargets},
        };
    }

    if (dstInfo.exists()) {
        QDir(dstPath).removeRecursively();
    }
    if (!copyDirectoryRecursively(srcInfo.absoluteFilePath(), dstPath)) {
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Не удалось скопировать файлы мода")}};
    }

    appendLog(parsed.id, QStringLiteral("info"), QStringLiteral("Установлен мод «%1» v%2").arg(parsed.name, parsed.version));
    scanAndSync(false);
    return {
        {QStringLiteral("ok"), true},
        {QStringLiteral("id"), parsed.id},
        {QStringLiteral("name"), parsed.name},
        {QStringLiteral("hasOverrides"), hasOverrides},
        {QStringLiteral("overrideTargets"), overrideTargets},
    };
}

QVariantMap ModManager::installModFromArchive(const QUrl &archiveUrl)
{
    const QString archivePath = archiveUrl.isLocalFile() ? archiveUrl.toLocalFile() : archiveUrl.toString();
    const QFileInfo archiveInfo(archivePath);
    if (!archiveInfo.isFile()) {
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Выбранный файл архива не найден")}};
    }
    const QString lower = archiveInfo.fileName().toLower();
    if (!lower.endsWith(QLatin1StringView(".ymmod")) && !lower.endsWith(QLatin1StringView(".zip"))) {
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Поддерживаются только архивы .ymmod и .zip")}};
    }

    QTemporaryDir tempDir;
    if (!tempDir.isValid()) {
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Не удалось создать временную папку для распаковки")}};
    }

    QZipReader zip(archiveInfo.absoluteFilePath(), QIODevice::ReadOnly);
    if (!zip.isReadable() || zip.status() != QZipReader::NoError) {
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Не удалось открыть архив (проверьте формат ZIP/ymmod)")}};
    }

    const int entryCount = zip.count();
    if (entryCount <= 0) {
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Архив пуст или повреждён")}};
    }
    if (entryCount > kMaxArchiveFiles) {
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Архив превышает лимит файлов (максимум %1)").arg(kMaxArchiveFiles)}};
    }

    const QString tempCanonical = QFileInfo(tempDir.path()).canonicalFilePath();
    qint64 declaredBytes = 0;
    qint64 actualBytes = 0;

    for (int i = 0; i < entryCount; ++i) {
        const QZipReader::FileInfo info = zip.entryInfoAt(i);
        if (!info.isValid()) {
            continue;
        }
        if (info.isSymLink) {
            return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Архив содержит симлинки, установка отклонена")}};
        }

        const QString rawPath = info.filePath;
        const QString normalized = rawPath.trimmed().replace(u'\\', u'/');
        if (normalized.isEmpty() || normalized.startsWith(u'/') || QDir::isAbsolutePath(normalized)
            || (normalized.size() >= 2 && normalized.at(1) == u':')) {
            return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Небезопасный путь внутри архива")}};
        }
        const QStringList segments = normalized.split(u'/', Qt::SkipEmptyParts);
        if (segments.isEmpty() || segments.contains(QStringLiteral(".."))) {
            return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Небезопасный путь внутри архива")}};
        }

        if (info.size < 0 || declaredBytes + info.size > kMaxArchiveBytes) {
            return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Распакованный размер архива превышает лимит 50 МБ")}};
        }
        declaredBytes += info.size;

        const QString destPath = QDir::cleanPath(tempCanonical + u'/' + segments.join(u'/'));
        if (!destPath.startsWith(tempCanonical + u'/')) {
            return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Небезопасный путь внутри архива")}};
        }

        if (info.isDir) {
            if (!QDir().mkpath(destPath)) {
                return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Не удалось создать каталог при распаковке архива")}};
            }
        } else if (info.isFile) {
            const QByteArray data = zip.fileData(rawPath);
            actualBytes += data.size();
            if (actualBytes > kMaxArchiveBytes) {
                return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Распакованный размер архива превышает лимит 50 МБ")}};
            }
            const QFileInfo destInfo(destPath);
            if (!QDir().mkpath(destInfo.absolutePath())) {
                return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Не удалось создать каталог при распаковке архива")}};
            }
            QFile outFile(destPath);
            if (!outFile.open(QIODevice::WriteOnly | QIODevice::Truncate) || outFile.write(data) != data.size()) {
                return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Не удалось записать файл при распаковке архива")}};
            }
        }
    }
    zip.close();

    // Verify no symlink / zip-slip escaped tempDir
    QDirIterator checkIt(tempDir.path(), QDir::AllEntries | QDir::NoDotAndDotDot | QDir::System, QDirIterator::Subdirectories);
    while (checkIt.hasNext()) {
        checkIt.next();
        const QFileInfo fi = checkIt.fileInfo();
        if (fi.isSymLink()) {
            return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Архив содержит симлинки, установка отклонена")}};
        }
        const QString c = fi.canonicalFilePath();
        if (c.isEmpty() || !c.startsWith(tempCanonical + u'/')) {
            return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("Небезопасный путь внутри архива")}};
        }
    }

    // Locate manifest.json either at archive root or inside a single top-level directory
    QString modRoot;
    if (QFileInfo::exists(tempDir.path() + QStringLiteral("/manifest.json"))) {
        modRoot = tempDir.path();
    } else {
        const QDir rootDir(tempDir.path());
        const auto topDirs = rootDir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (const QFileInfo &sub : topDirs) {
            if (sub.fileName() == QLatin1StringView("__MACOSX")) continue;
            if (QFileInfo::exists(sub.absoluteFilePath() + QStringLiteral("/manifest.json"))) {
                modRoot = sub.absoluteFilePath();
                break;
            }
        }
    }

    if (modRoot.isEmpty()) {
        return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("В архиве не найден manifest.json")}};
    }

    return installModFromFolder(QUrl::fromLocalFile(modRoot));
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
