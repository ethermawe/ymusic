#include "mods/ModScriptHost.h"

#include "mods/ModApi.h"
#include "mods/ModManager.h"

#include <QFile>
#include <QJsonDocument>
#include <QRegularExpression>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <thread>

namespace ymusic::mods {

class ModJsBridge : public QObject {
    Q_OBJECT

public:
    ModJsBridge(ModScriptHost *host, ModManifest manifest, ModManager *manager, ModApi *api)
        : QObject(host)
        , m_host(host)
        , m_manifest(std::move(manifest))
        , m_manager(manager)
        , m_api(api)
    {
    }

    Q_INVOKABLE void log(const QString &level, const QString &msg)
    {
        if (m_manager) {
            m_manager->appendLog(m_manifest.id, level, msg);
        }
    }

    Q_INVOKABLE bool checkHookPermission(const QString &point)
    {
        if (m_manifest.hasPermission(QStringLiteral("hooks:*"))
            || m_manifest.hasPermission(QStringLiteral("hooks:") + point)) {
            return true;
        }
        // Group aliases: hooks:search -> search_results, hooks:wave -> wave_next_batch, hooks:queue -> queue_before_add, etc.
        const QString group = point.section(u'_', 0, 0);
        if (!group.isEmpty() && m_manifest.hasPermission(QStringLiteral("hooks:") + group)) {
            return true;
        }
        log(QStringLiteral("warn"),
            QStringLiteral("Отказ в доступе (ym.hooks.on): требуется разрешение 'hooks:%1'").arg(point));
        return false;
    }

    Q_INVOKABLE void onHookSubscribed(const QString &point)
    {
        if (m_host) m_host->registerHookPoint(point);
    }

    Q_INVOKABLE void onHookUnsubscribed(const QString &point)
    {
        if (m_host) m_host->unregisterHookPoint(point);
    }

    Q_INVOKABLE bool checkPermission(const QString &perm, const QString &fallbackPerm, const QString &action)
    {
        if (m_manifest.hasPermission(perm) || (!fallbackPerm.isEmpty() && m_manifest.hasPermission(fallbackPerm))) {
            return true;
        }
        log(QStringLiteral("warn"),
            QStringLiteral("Отказ в доступе (%1): требуется разрешение '%2'").arg(action, perm));
        return false;
    }

    // Storage
    Q_INVOKABLE QVariant storageGet(const QString &key, const QVariant &fallback = QVariant())
    {
        return m_api ? m_api->storageGet(key, fallback) : fallback;
    }
    Q_INVOKABLE bool storageSet(const QString &key, const QVariant &val)
    {
        return m_api && m_api->storageSet(key, val);
    }
    Q_INVOKABLE bool storageRemove(const QString &key)
    {
        return m_api && m_api->storageRemove(key);
    }
    Q_INVOKABLE QVariantMap storageAll()
    {
        return m_api ? m_api->storageAll() : QVariantMap{};
    }

    // Player
    Q_INVOKABLE bool playerToggle()
    {
        if (!checkPermission(QStringLiteral("player"), QStringLiteral("playback:control"), QStringLiteral("ym.player.toggle"))) return false;
        return m_api && m_api->toggle();
    }
    Q_INVOKABLE bool playerNext()
    {
        if (!checkPermission(QStringLiteral("player"), QStringLiteral("playback:control"), QStringLiteral("ym.player.next"))) return false;
        return m_api && m_api->next();
    }
    Q_INVOKABLE bool playerPrev()
    {
        if (!checkPermission(QStringLiteral("player"), QStringLiteral("playback:control"), QStringLiteral("ym.player.prev"))) return false;
        return m_api && m_api->prev();
    }
    Q_INVOKABLE bool playerSeek(qreal progress)
    {
        if (!checkPermission(QStringLiteral("player"), QStringLiteral("playback:control"), QStringLiteral("ym.player.seek"))) return false;
        return m_api && m_api->seek(progress);
    }
    Q_INVOKABLE QVariantList playerQueue()
    {
        if (!checkPermission(QStringLiteral("player"), QStringLiteral("library:read"), QStringLiteral("ym.player.queue"))) return {};
        return m_api ? m_api->queueTracks() : QVariantList{};
    }
    Q_INVOKABLE bool playerAddToQueue(const QString &trackId)
    {
        if (!checkPermission(QStringLiteral("player"), QStringLiteral("playback:control"), QStringLiteral("ym.player.addToQueue"))) return false;
        return m_api && m_api->addToQueue(trackId);
    }
    Q_INVOKABLE bool playerPlayNext(const QString &trackId)
    {
        if (!checkPermission(QStringLiteral("player"), QStringLiteral("playback:control"), QStringLiteral("ym.player.playNext"))) return false;
        return m_api && m_api->playNext(trackId);
    }

    // Library
    Q_INVOKABLE QVariantList libraryHistory()
    {
        if (!checkPermission(QStringLiteral("library"), QStringLiteral("library:read"), QStringLiteral("ym.library.history"))) return {};
        return m_api ? m_api->historyTracks() : QVariantList{};
    }
    Q_INVOKABLE QVariantList libraryPlaylists()
    {
        if (!checkPermission(QStringLiteral("library"), QStringLiteral("library:read"), QStringLiteral("ym.library.playlists"))) return {};
        return m_api ? m_api->pinnedPlaylists() : QVariantList{};
    }

    // Commands
    Q_INVOKABLE bool registerCommand(const QString &id, const QString &title, const QString &shortcut)
    {
        if (!m_manager || id.trimmed().isEmpty()) return false;
        if (!shortcut.trimmed().isEmpty()) {
            m_manager->registerShortcut(m_manifest.id, id.trimmed(), shortcut.trimmed(), title.trimmed());
        }
        return true;
    }

    // UI
    Q_INVOKABLE bool toast(const QString &message)
    {
        if (!m_manager || message.trimmed().isEmpty()) return false;
        emit m_manager->toastRequested(message.trimmed().left(200));
        return true;
    }

    // Pages
    Q_INVOKABLE bool registerPage(const QString &id, const QString &title, const QString &icon, const QString &qmlRelPath)
    {
        if (!checkPermission(QStringLiteral("ui:pages"), QStringLiteral("ui:slots"), QStringLiteral("ym.pages.register"))) return false;
        const QString resolved = resolveModPath(m_manifest.directory, qmlRelPath, true);
        if (resolved.isEmpty()) {
            log(QStringLiteral("warn"), QStringLiteral("ym.pages.register: некорректный путь QML: %1").arg(qmlRelPath));
            return false;
        }
        if (m_manager) {
            m_manager->registerDynamicPage(m_manifest.id, id, title, icon, resolved);
        }
        return true;
    }

    // Inter-mod require
    Q_INVOKABLE QJSValue requireMod(const QString &depModId)
    {
        return m_host ? m_host->requireDependency(depModId) : QJSValue(QJSValue::UndefinedValue);
    }

    // HTTP (returns requestId or empty on denial)
    Q_INVOKABLE bool httpRequest(const QString &method, const QString &url, const QVariantMap &headers, const QString &body, const QString &reqId)
    {
        return m_api && m_api->httpRequest(method, url, headers, body, reqId);
    }

private:
    QPointer<ModScriptHost> m_host;
    ModManifest m_manifest;
    QPointer<ModManager> m_manager;
    QPointer<ModApi> m_api;
};

namespace {

QString preprocessModuleSyntax(QString source)
{
    // Allow ES-style `export function activate(...)` / `export function deactivate()`
    static const QRegularExpression exportFnRe(QStringLiteral(R"re((^|\n)\s*export\s+(async\s+)?function\s+)re"));
    source.replace(exportFnRe, QStringLiteral(R"(\1\2function )"));
    static const QRegularExpression exportConstRe(QStringLiteral(R"re((^|\n)\s*export\s+(const|let|var)\s+)re"));
    source.replace(exportConstRe, QStringLiteral(R"(\1\2 )"));
    return source;
}

const char *kYmBootstrapJs = R"js(
(function(bridge) {
    const hookMap = Object.create(null);
    const eventMap = Object.create(null);
    const cmdMap = Object.create(null);
    const exposedMap = Object.create(null);
    const settingsListeners = [];
    const pendingHttp = Object.create(null);
    let httpSeq = 1;
    const exportsObj = Object.create(null);

    const consoleObj = {
        log: function() { bridge.log("info", Array.prototype.slice.call(arguments).map(String).join(" ")); },
        info: function() { bridge.log("info", Array.prototype.slice.call(arguments).map(String).join(" ")); },
        warn: function() { bridge.log("warn", Array.prototype.slice.call(arguments).map(String).join(" ")); },
        error: function() { bridge.log("error", Array.prototype.slice.call(arguments).map(String).join(" ")); }
    };

    const ym = {
        cancel: function(reason) {
            return { __ymCancel: true, reason: reason ? String(reason) : "" };
        },
        hooks: {
            on: function(point, fn) {
                if (typeof fn !== "function" || !point) return false;
                if (!bridge.checkHookPermission(String(point))) return false;
                if (!hookMap[point]) {
                    hookMap[point] = [];
                    bridge.onHookSubscribed(String(point));
                }
                hookMap[point].push(fn);
                return true;
            },
            off: function(point, fn) {
                const list = hookMap[point];
                if (!list) return;
                hookMap[point] = list.filter(function(f) { return f !== fn; });
                if (hookMap[point].length === 0) {
                    delete hookMap[point];
                    bridge.onHookUnsubscribed(String(point));
                }
            }
        },
        events: {
            on: function(name, fn) {
                if (typeof fn !== "function" || !name) return;
                if (!eventMap[name]) eventMap[name] = [];
                eventMap[name].push(fn);
            },
            off: function(name, fn) {
                if (!eventMap[name]) return;
                eventMap[name] = eventMap[name].filter(function(f) { return f !== fn; });
            }
        },
        player: {
            toggle: function() { return bridge.playerToggle(); },
            next: function() { return bridge.playerNext(); },
            prev: function() { return bridge.playerPrev(); },
            seek: function(p) { return bridge.playerSeek(Number(p)); },
            queue: function() { return bridge.playerQueue(); },
            addToQueue: function(id) { return bridge.playerAddToQueue(String(id)); },
            playNext: function(id) { return bridge.playerPlayNext(String(id)); }
        },
        library: {
            history: function() { return bridge.libraryHistory(); },
            playlists: function() { return bridge.libraryPlaylists(); }
        },
        commands: {
            register: function(id, title, fn, opts) {
                if (!id || typeof fn !== "function") return false;
                cmdMap[String(id)] = fn;
                const sc = (opts && opts.shortcut) ? String(opts.shortcut) : "";
                return bridge.registerCommand(String(id), String(title || id), sc);
            }
        },
        settings: {
            _schema: null,
            define: function(schema) { this._schema = schema; },
            get: function(key, fallback) { return bridge.storageGet(String(key), fallback); },
            set: function(key, val) {
                const ok = bridge.storageSet(String(key), val);
                if (ok) {
                    for (let i = 0; i < settingsListeners.length; ++i) {
                        try { settingsListeners[i](String(key), val); } catch (e) {}
                    }
                }
                return ok;
            },
            onChange: function(fn) { if (typeof fn === "function") settingsListeners.push(fn); }
        },
        pages: {
            register: function(id, opts) {
                if (!id || !opts || !opts.qml) return false;
                return bridge.registerPage(String(id), String(opts.title || id), String(opts.icon || "extension"), String(opts.qml));
            }
        },
        storage: {
            get: function(k, fb) { return bridge.storageGet(String(k), fb); },
            set: function(k, v) { return bridge.storageSet(String(k), v); },
            remove: function(k) { return bridge.storageRemove(String(k)); },
            all: function() { return bridge.storageAll(); }
        },
        http: {
            request: function(method, url, opts) {
                return new Promise(function(resolve, reject) {
                    const reqId = "js-" + (httpSeq++);
                    const headers = (opts && opts.headers) ? opts.headers : {};
                    const body = (opts && opts.body !== undefined) ? String(opts.body) : "";
                    pendingHttp[reqId] = { resolve: resolve, reject: reject };
                    const ok = bridge.httpRequest(String(method || "GET"), String(url || ""), headers, body, reqId);
                    if (!ok) {
                        delete pendingHttp[reqId];
                        reject(new Error("HTTP request denied by mod permissions"));
                    }
                });
            }
        },
        ui: {
            toast: function(msg) { return bridge.toast(String(msg || "")); },
            notify: function(title, body) { return bridge.toast(String(title || "") + (body ? (": " + String(body)) : "")); },
            expose: function(name, fn) { if (name && typeof fn === "function") exposedMap[String(name)] = fn; },
            post: function(msg) { bridge.log("info", "ui.post: " + JSON.stringify(msg)); }
        },
        exports: exportsObj,
        require: function(modId) { return bridge.requireMod(String(modId)); }
    };

    const internal = {
        invokeHook: function(point, payload) {
            const list = hookMap[point];
            if (!list || list.length === 0) return { handled: false, payload: payload };
            let current = payload;
            for (let i = 0; i < list.length; ++i) {
                const res = list[i](current);
                if (res && res.__ymCancel === true) {
                    return { handled: true, cancelled: true, reason: String(res.reason || ""), payload: current };
                }
                if (res !== undefined && res !== null) {
                    current = res;
                }
            }
            return { handled: true, cancelled: false, payload: current };
        },
        dispatchEvent: function(name, data) {
            const list = eventMap[name];
            if (!list) return;
            for (let i = 0; i < list.length; ++i) {
                list[i](data);
            }
        },
        invokeCommand: function(id) {
            const fn = cmdMap[id];
            if (typeof fn !== "function") return false;
            fn();
            return true;
        },
        callExposed: function(name, args) {
            const fn = exposedMap[name];
            if (typeof fn !== "function") throw new Error("Exposed method not found: " + name);
            return fn.apply(null, args || []);
        },
        resolveHttp: function(reqId, status, body, err) {
            const entry = pendingHttp[reqId];
            if (!entry) return;
            delete pendingHttp[reqId];
            if (err && err.length > 0 && status === 0) entry.reject(new Error(err));
            else entry.resolve({ status: status, body: body, error: err || "" });
        }
    };

    return { ym: ym, console: consoleObj, internal: internal, exportsObj: exportsObj };
})
)js";

} // namespace

ModScriptHost::ModScriptHost(ModManifest manifest, ModManager *manager, ModApi *api, QObject *parent)
    : QObject(parent)
    , m_manifest(std::move(manifest))
    , m_manager(manager)
    , m_api(api)
{
}

ModScriptHost::~ModScriptHost()
{
    deactivate();
}

QJSValue ModScriptHost::runWithWatchdog(const std::function<QJSValue()> &fn, const QString &contextLabel)
{
    if (!m_engine) {
        return QJSValue(QJSValue::UndefinedValue);
    }
    m_engine->setInterrupted(false);

    std::mutex mtx;
    std::condition_variable cv;
    bool finished = false;
    std::atomic<bool> timedOut{false};
    QJSEngine *eng = m_engine.get();
    const int timeoutMs = m_watchdogMs;

    std::thread watchdog([&]() {
        std::unique_lock<std::mutex> lock(mtx);
        if (!cv.wait_for(lock, std::chrono::milliseconds(timeoutMs), [&]() { return finished; })) {
            timedOut.store(true, std::memory_order_release);
            eng->setInterrupted(true);
        }
    });

    QJSValue result = fn();

    {
        std::lock_guard<std::mutex> lock(mtx);
        finished = true;
    }
    cv.notify_one();
    watchdog.join();

    if (timedOut.load(std::memory_order_acquire)) {
        m_engine->setInterrupted(false);
        recordError(QStringLiteral("Прерывание зависшего скрипта (%1, >%2 мс)").arg(contextLabel).arg(timeoutMs));
        return QJSValue(QJSValue::UndefinedValue);
    }
    if (result.isError()) {
        recordError(QStringLiteral("Ошибка JS (%1): %2").arg(contextLabel, result.toString()));
        return result;
    }
    recordSuccess();
    return result;
}

void ModScriptHost::recordSuccess()
{
    m_consecutiveErrors = 0;
}

void ModScriptHost::recordError(const QString &message)
{
    ++m_consecutiveErrors;
    if (m_manager) {
        m_manager->reportModError(m_manifest.id, message);
    }
    if (m_consecutiveErrors >= kMaxConsecutiveErrors && !m_autoDisabled) {
        m_autoDisabled = true;
        if (m_manager) {
            m_manager->reportModError(
                m_manifest.id,
                QStringLiteral("Мод автоматически отключён после %1 ошибок подряд").arg(kMaxConsecutiveErrors));
        }
        emit autoDisabled(m_manifest.id);
    }
}

void ModScriptHost::registerHookPoint(const QString &point)
{
    if (!m_hookPoints.contains(point)) {
        m_hookPoints.append(point);
        emit hookSubscriptionsChanged();
    }
}

void ModScriptHost::unregisterHookPoint(const QString &point)
{
    if (m_hookPoints.removeAll(point) > 0) {
        emit hookSubscriptionsChanged();
    }
}

QJSValue ModScriptHost::requireDependency(const QString &depModId)
{
    if (!m_manifest.dependencies.contains(depModId)) {
        if (m_manager) {
            m_manager->appendLog(
                m_manifest.id,
                QStringLiteral("warn"),
                QStringLiteral("ym.require('%1'): зависимость не объявлена в manifest.json").arg(depModId));
        }
        return QJSValue(QJSValue::UndefinedValue);
    }
    if (!m_manager || !m_engine) {
        return QJSValue(QJSValue::UndefinedValue);
    }
    return m_engine->toScriptValue(m_manager->modExports(depModId));
}

bool ModScriptHost::loadAndActivate()
{
    if (m_manifest.mainScript.isEmpty()) {
        return false;
    }
    deactivate();
    m_autoDisabled = false;
    m_consecutiveErrors = 0;

    QFile file(m_manifest.mainScript);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        recordError(QStringLiteral("Не удалось открыть %1: %2").arg(m_manifest.mainScript, file.errorString()));
        return false;
    }
    const QString source = preprocessModuleSyntax(QString::fromUtf8(file.readAll()));

    m_engine = std::make_unique<QJSEngine>();
    m_bridge = new ModJsBridge(this, m_manifest, m_manager, m_api);
    QJSEngine::setObjectOwnership(m_bridge, QJSEngine::CppOwnership);

    QJSValue factory = m_engine->evaluate(QString::fromUtf8(kYmBootstrapJs));
    if (factory.isError() || !factory.isCallable()) {
        recordError(QStringLiteral("Внутренняя ошибка инициализации JS-рантайма: %1").arg(factory.toString()));
        return false;
    }
    QJSValue env = factory.call({m_engine->newQObject(m_bridge)});
    m_ymObj = env.property(QStringLiteral("ym"));
    m_exportsObj = env.property(QStringLiteral("exportsObj"));
    m_engine->globalObject().setProperty(QStringLiteral("ym"), m_ymObj);
    m_engine->globalObject().setProperty(QStringLiteral("console"), env.property(QStringLiteral("console")));
    m_engine->globalObject().setProperty(QStringLiteral("__ymInternal"), env.property(QStringLiteral("internal")));

    if (m_api) {
        connect(m_api, &ModApi::httpFinished, this, [this](const QString &reqId, int status, const QString &body, const QString &err) {
            if (!m_engine || m_autoDisabled) return;
            QJSValue internal = m_engine->globalObject().property(QStringLiteral("__ymInternal"));
            QJSValue fn = internal.property(QStringLiteral("resolveHttp"));
            if (fn.isCallable()) {
                fn.call({reqId, status, body, err});
            }
        });
    }

    QJSValue evalRes = runWithWatchdog([&]() {
        return m_engine->evaluate(source, m_manifest.mainScript);
    }, QStringLiteral("evaluate"));
    if (evalRes.isError() || m_autoDisabled) {
        return false;
    }

    QJSValue activateFn = m_engine->globalObject().property(QStringLiteral("activate"));
    if (activateFn.isCallable()) {
        QJSValue actRes = runWithWatchdog([&]() {
            return activateFn.call({m_ymObj});
        }, QStringLiteral("activate"));
        if (actRes.isError() || m_autoDisabled) {
            return false;
        }
    }

    m_loaded = true;
    return true;
}

void ModScriptHost::deactivate()
{
    if (m_engine && m_loaded && !m_autoDisabled) {
        QJSValue deactivateFn = m_engine->globalObject().property(QStringLiteral("deactivate"));
        if (deactivateFn.isCallable()) {
            runWithWatchdog([&]() {
                return deactivateFn.call({});
            }, QStringLiteral("deactivate"));
        }
    }
    m_loaded = false;
    if (!m_hookPoints.isEmpty()) {
        m_hookPoints.clear();
        emit hookSubscriptionsChanged();
    }
    m_ymObj = QJSValue();
    m_exportsObj = QJSValue();
    m_engine.reset();
    if (m_bridge) {
        delete m_bridge;
        m_bridge = nullptr;
    }
}

QStringList ModScriptHost::subscribedHookPoints() const
{
    return m_hookPoints;
}

HookInvokeResult ModScriptHost::invokeHook(const QString &point, const QVariant &payload)
{
    HookInvokeResult out;
    out.payload = payload;
    if (!isLoaded() || !m_engine || !m_hookPoints.contains(point)) {
        return out;
    }

    QJSValue res = runWithWatchdog([&]() {
        QJSValue internal = m_engine->globalObject().property(QStringLiteral("__ymInternal"));
        QJSValue fn = internal.property(QStringLiteral("invokeHook"));
        return fn.call({point, m_engine->toScriptValue(payload)});
    }, QStringLiteral("hook:") + point);

    if (res.isError() || res.isUndefined() || m_autoDisabled) {
        return out;
    }
    out.handled = res.property(QStringLiteral("handled")).toBool();
    out.cancelled = res.property(QStringLiteral("cancelled")).toBool();
    out.cancelReason = res.property(QStringLiteral("reason")).toString();
    if (out.handled && !out.cancelled) {
        out.payload = res.property(QStringLiteral("payload")).toVariant();
    }
    return out;
}

void ModScriptHost::dispatchEvent(const QString &eventName, const QVariant &data)
{
    if (!isLoaded() || !m_engine) return;
    runWithWatchdog([&]() {
        QJSValue internal = m_engine->globalObject().property(QStringLiteral("__ymInternal"));
        QJSValue fn = internal.property(QStringLiteral("dispatchEvent"));
        return fn.call({eventName, m_engine->toScriptValue(data)});
    }, QStringLiteral("event:") + eventName);
}

bool ModScriptHost::invokeCommand(const QString &commandId)
{
    if (!isLoaded() || !m_engine) return false;
    QJSValue res = runWithWatchdog([&]() {
        QJSValue internal = m_engine->globalObject().property(QStringLiteral("__ymInternal"));
        QJSValue fn = internal.property(QStringLiteral("invokeCommand"));
        return fn.call({commandId});
    }, QStringLiteral("command:") + commandId);
    return !res.isError() && res.toBool();
}

QVariant ModScriptHost::callExposed(const QString &name, const QVariantList &args, QString *errorOut)
{
    if (!isLoaded() || !m_engine) {
        if (errorOut) *errorOut = QStringLiteral("JS-хост мода не активен");
        return {};
    }
    QJSValue res = runWithWatchdog([&]() {
        QJSValue internal = m_engine->globalObject().property(QStringLiteral("__ymInternal"));
        QJSValue fn = internal.property(QStringLiteral("callExposed"));
        return fn.call({name, m_engine->toScriptValue(args)});
    }, QStringLiteral("expose:") + name);
    if (res.isError()) {
        if (errorOut) *errorOut = res.toString();
        return {};
    }
    return res.toVariant();
}

QVariant ModScriptHost::exportsVariant() const
{
    return (isLoaded() && !m_exportsObj.isUndefined()) ? m_exportsObj.toVariant() : QVariant();
}

} // namespace ymusic::mods

#include "ModScriptHost.moc"
