#pragma once

#include "mods/ModManifest.h"

#include <QJSEngine>
#include <QJSValue>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QStringList>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>

#include <memory>

namespace ymusic::mods {

class ModApi;
class ModManager;
class ModJsBridge;

struct HookInvokeResult {
    bool cancelled = false;
    QString cancelReason;
    QVariant payload;
    bool handled = false;
};

/// Isolated QJSEngine runtime for a single logic mod (`"main": "main.js"`).
/// Exposes ONLY `ym` and `console` (redirected to ModManager logs).
/// Includes a synchronous watchdog timer (`setInterrupted(true)`) and auto-disable after 5 consecutive errors.
class ModScriptHost : public QObject {
    Q_OBJECT

public:
    static constexpr int kDefaultWatchdogMs = 500;
    static constexpr int kMaxConsecutiveErrors = 5;

    explicit ModScriptHost(ModManifest manifest,
                           ModManager *manager,
                           ModApi *api,
                           QObject *parent = nullptr);
    ~ModScriptHost() override;

    const QString &modId() const { return m_manifest.id; }
    bool isLoaded() const { return m_loaded && !m_autoDisabled; }
    bool isAutoDisabled() const { return m_autoDisabled; }
    int consecutiveErrors() const { return m_consecutiveErrors; }

    void setWatchdogTimeoutMs(int ms) { m_watchdogMs = ms > 10 ? ms : 10; }

    bool loadAndActivate();
    void deactivate();

    QStringList subscribedHookPoints() const;
    HookInvokeResult invokeHook(const QString &point, const QVariant &payload);
    void dispatchEvent(const QString &eventName, const QVariant &data);
    bool invokeCommand(const QString &commandId);
    QVariant callExposed(const QString &name, const QVariantList &args, QString *errorOut = nullptr);
    QVariant exportsVariant() const;

    // Called by ModJsBridge
    void recordError(const QString &message);
    void recordSuccess();
    void registerHookPoint(const QString &point);
    void unregisterHookPoint(const QString &point);
    QJSValue requireDependency(const QString &depModId);

signals:
    void hookSubscriptionsChanged();
    void autoDisabled(const QString &modId);

private:
    QJSValue runWithWatchdog(const std::function<QJSValue()> &fn, const QString &contextLabel);
    bool hasHookPermission(const QString &point) const;

    ModManifest m_manifest;
    QPointer<ModManager> m_manager;
    QPointer<ModApi> m_api;
    std::unique_ptr<QJSEngine> m_engine;
    ModJsBridge *m_bridge = nullptr;
    QJSValue m_ymObj;
    QJSValue m_exportsObj;
    QStringList m_hookPoints;
    int m_watchdogMs = kDefaultWatchdogMs;
    int m_consecutiveErrors = 0;
    bool m_loaded = false;
    bool m_autoDisabled = false;
};

} // namespace ymusic::mods
