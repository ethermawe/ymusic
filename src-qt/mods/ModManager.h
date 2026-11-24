#pragma once

#include "mods/ModManifest.h"
#include "mods/ModUrlInterceptor.h"

#include <QFileSystemWatcher>
#include <QHash>
#include <QList>
#include <QObject>
#include <QPointer>
#include <QTimer>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class AppSettings;
class QJSEngine;
class QQmlEngine;
class YMusicBackend;

namespace ymusic {
class SpectrumSource;
}

namespace ymusic::mods {

class ModApi;

struct ModTrackMenuAction {
    QString modId;
    QString actionId;
    QString label;
    QString symbol;
    bool destructive = false;
};

struct ModLogEntry {
    QString time;
    QString modId;
    QString level;
    QString message;
};

class ModManager : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool safeMode READ safeMode CONSTANT FINAL)
    Q_PROPERTY(bool modsEnabled READ modsEnabled NOTIFY modsChanged FINAL)
    Q_PROPERTY(int reloadRevision READ reloadRevision NOTIFY reloadRevisionChanged FINAL)
    Q_PROPERTY(int activeModCount READ activeModCount NOTIFY modsChanged FINAL)
    Q_PROPERTY(int activeOverrideCount READ activeOverrideCount NOTIFY modsChanged FINAL)
    Q_PROPERTY(bool overridesNeedRestart READ overridesNeedRestart NOTIFY modsChanged FINAL)
    Q_PROPERTY(QVariantList mods READ modsVariantList NOTIFY modsChanged FINAL)
    Q_PROPERTY(QVariantList logs READ logsVariantList NOTIFY logsChanged FINAL)
    Q_PROPERTY(QVariantList trackMenuActions READ trackMenuActionsVariantList NOTIFY trackMenuActionsChanged FINAL)

public:
    explicit ModManager(AppSettings *settings,
                        YMusicBackend *backend,
                        ymusic::SpectrumSource *spectrum,
                        bool safeMode = false,
                        QObject *parent = nullptr);
    ~ModManager() override;

    static ModManager *instance();
    static ModManager *create(QQmlEngine *, QJSEngine *);

    void attachEngine(QQmlEngine *engine);
    ModUrlInterceptor *urlInterceptor() { return &m_interceptor; }

    bool safeMode() const { return m_safeMode; }
    bool modsEnabled() const;
    int reloadRevision() const { return m_reloadRevision; }
    int activeModCount() const;
    int activeOverrideCount() const { return m_interceptor.count(); }
    bool overridesNeedRestart() const { return m_overridesNeedRestart; }

    QVariantList modsVariantList() const;
    QVariantList logsVariantList() const;
    QVariantList trackMenuActionsVariantList() const;

    Q_INVOKABLE QVariantList slotEntries(const QString &slotName) const;
    Q_INVOKABLE ymusic::mods::ModApi *apiForMod(const QString &modId) const;
    Q_INVOKABLE void setModEnabled(const QString &modId, bool enabled);
    Q_INVOKABLE void reloadMods();
    Q_INVOKABLE void triggerTrackMenuAction(const QString &modId,
                                            const QString &actionId,
                                            const QString &trackId,
                                            const QString &trackTitle);
    Q_INVOKABLE void reportModError(const QString &modId, const QString &message);
    Q_INVOKABLE void clearLogs();
    Q_INVOKABLE bool openModsFolder() const;
    Q_INVOKABLE QVariantMap installModFromFolder(const QUrl &folderUrl);
    Q_INVOKABLE bool uninstallMod(const QString &modId);

    /// Disables all mods with UI overrides and clears the URL interceptor (used for startup crash recovery).
    void quarantineOverrideMods(const QString &reason);

    // Internal hooks for ModApi
    void appendLog(const QString &modId, const QString &level, const QString &message);
    void registerTrackMenuAction(const QString &modId,
                                 const QString &actionId,
                                 const QString &label,
                                 const QString &symbol,
                                 bool destructive);
    void unregisterTrackMenuAction(const QString &modId, const QString &actionId);
    void clearTrackMenuActionsForMod(const QString &modId);

signals:
    void modsChanged();
    void reloadRevisionChanged();
    void logsChanged();
    void trackMenuActionsChanged();
    void toastRequested(const QString &message);
    void immersiveRequested(bool open);
    void settingsRequested();

private:
    void scanAndSync(bool initialStartup);
    void rebuildApis();
    void rebuildWatcher();
    void destroyAllApis();

    AppSettings *m_settings = nullptr;
    YMusicBackend *m_backend = nullptr;
    ymusic::SpectrumSource *m_spectrum = nullptr;
    QPointer<QQmlEngine> m_engine;
    bool m_safeMode = false;
    int m_reloadRevision = 0;
    bool m_overridesNeedRestart = false;

    QList<ModManifest> m_manifests;
    QHash<QString, QStringList> m_overrideConflicts;
    QHash<QString, QString> m_startupOverrides;
    QHash<QString, QPointer<ModApi>> m_apis;
    QList<ModTrackMenuAction> m_trackMenuActions;
    QList<ModLogEntry> m_logs;

    ModUrlInterceptor m_interceptor;
    QFileSystemWatcher m_watcher;
    QTimer m_watchDebounce;
};

} // namespace ymusic::mods
