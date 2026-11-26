#pragma once

#include "mods/ModManifest.h"
#include "mods/ModUrlInterceptor.h"

#include <QFileSystemWatcher>
#include <QHash>
#include <QList>
#include <QObject>
#include <QPointer>
#include <QStringList>
#include <QTimer>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

#include <memory>

class AppSettings;
class QJSEngine;
class QQmlEngine;
class YMusicBackend;

namespace ymusic {
class SpectrumSource;
}

namespace ymusic::mods {

class ModApi;
class ModScriptHost;

struct ModTrackMenuAction {
    QString modId;
    QString actionId;
    QString label;
    QString symbol;
    bool destructive = false;
};

struct ModShortcutEntry {
    QString modId;
    QString actionId;
    QString sequence;
    QString description;
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
    Q_PROPERTY(bool pendingRestartPrompt READ pendingRestartPrompt NOTIFY modsChanged FINAL)
    Q_PROPERTY(QVariantList mods READ modsVariantList NOTIFY modsChanged FINAL)
    Q_PROPERTY(QVariantList logs READ logsVariantList NOTIFY logsChanged FINAL)
    Q_PROPERTY(QVariantList trackMenuActions READ trackMenuActionsVariantList NOTIFY trackMenuActionsChanged FINAL)
    Q_PROPERTY(QVariantList shortcuts READ shortcutsVariantList NOTIFY shortcutsChanged FINAL)
    Q_PROPERTY(int lyricSubtitlesRevision READ lyricSubtitlesRevision NOTIFY lyricSubtitlesChanged FINAL)

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
    QQmlEngine *sandboxEngineForMod(const QString &modId);
    QString modDirectoryForMod(const QString &modId) const;
    QObject *createSandboxedObject(const QString &modId,
                                   const QUrl &sourceUrl,
                                   const QVariantMap &slotContext = {},
                                   QString *errorOut = nullptr);

    bool safeMode() const { return m_safeMode; }
    bool modsEnabled() const;
    int reloadRevision() const { return m_reloadRevision; }
    int activeModCount() const;
    int activeOverrideCount() const { return m_interceptor.count(); }
    bool overridesNeedRestart() const { return m_overridesNeedRestart; }
    bool pendingRestartPrompt() const { return m_pendingRestartPrompt; }
    bool restartRequested() const { return m_restartRequested; }
    int lyricSubtitlesRevision() const { return m_lyricSubtitlesRevision; }

    QVariantList modsVariantList() const;
    QVariantList logsVariantList() const;
    QVariantList trackMenuActionsVariantList() const;
    QVariantList shortcutsVariantList() const;

    Q_INVOKABLE QVariantList slotEntries(const QString &slotName) const;
    Q_INVOKABLE bool hasSlot(const QString &slotName) const;
    Q_INVOKABLE ymusic::mods::ModApi *apiForMod(const QString &modId) const;
    Q_INVOKABLE void setModEnabled(const QString &modId, bool enabled);
    Q_INVOKABLE void moveMod(const QString &modId, int delta);
    Q_INVOKABLE void reloadMods();
    Q_INVOKABLE void dismissRestartPrompt();
    Q_INVOKABLE void requestAppRestart();
    Q_INVOKABLE void triggerTrackMenuAction(const QString &modId,
                                            const QString &actionId,
                                            const QString &trackId,
                                            const QString &trackTitle);
    Q_INVOKABLE void triggerShortcut(const QString &modId, const QString &actionId);
    Q_INVOKABLE void syncLyricsState(const QString &trackId, bool synced, const QVariantList &lines);
    Q_INVOKABLE QString lyricSubtitleFor(const QString &trackId, int lineIndex) const;
    Q_INVOKABLE void reportModError(const QString &modId, const QString &message);
    Q_INVOKABLE void clearLogs();
    Q_INVOKABLE bool openModsFolder() const;
    Q_INVOKABLE QVariantMap installModFromFolder(const QUrl &folderUrl);
    Q_INVOKABLE QVariantMap installModFromArchive(const QUrl &archiveUrl);
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

    void registerShortcut(const QString &modId,
                          const QString &actionId,
                          const QString &sequence,
                          const QString &description);
    void unregisterShortcut(const QString &modId, const QString &actionId);
    void clearShortcutsForMod(const QString &modId);

    void registerDynamicPage(const QString &modId,
                             const QString &pageId,
                             const QString &title,
                             const QString &icon,
                             const QString &resolvedQmlPath);
    QVariant modExports(const QString &modId) const;
    QVariant callModExposed(const QString &modId, const QString &name, const QVariantList &args);
    ModScriptHost *scriptHostForMod(const QString &modId) const;
    QVariantMap runHookChain(const QString &point, const QVariant &payload);
    QStringList activationOrder() const { return m_scriptOrder; }

    QString lyricsTrackId() const { return m_lyricsTrackId; }
    bool lyricsSynced() const { return m_lyricsSynced; }
    QVariantList lyricsLines() const { return m_lyricsLines; }
    void setLyricSubtitles(const QString &modId, const QString &trackId, const QStringList &subtitles);
    void clearLyricSubtitlesForMod(const QString &modId);

signals:
    void modsChanged();
    void reloadRevisionChanged();
    void logsChanged();
    void trackMenuActionsChanged();
    void shortcutsChanged();
    void lyricSubtitlesChanged();
    void toastRequested(const QString &message);
    void immersiveRequested(bool open);
    void settingsRequested();
    void createPlaylistRequested();

private:
    struct ModSandbox {
        QPointer<QQmlEngine> engine;
        std::shared_ptr<ModSandboxUrlInterceptor> urlInterceptor;
    };

    void scanAndSync(bool initialStartup);
    void rebuildApis();
    void rebuildWatcher();
    void destroyAllApis();
    void destroyAllSandboxes();
    void destroyAllScripts();
    void syncHookSubscriptions();
    void handleHookRequest(quint64 id, const QString &point, const QVariant &payload);
    const ModManifest *manifestForMod(const QString &modId) const;

    AppSettings *m_settings = nullptr;
    YMusicBackend *m_backend = nullptr;
    ymusic::SpectrumSource *m_spectrum = nullptr;
    QPointer<QQmlEngine> m_engine;
    bool m_safeMode = false;
    int m_reloadRevision = 0;
    bool m_overridesNeedRestart = false;
    bool m_pendingRestartPrompt = false;
    bool m_restartRequested = false;

    QList<ModManifest> m_manifests;
    QHash<QString, QStringList> m_overrideConflicts;
    QHash<QString, QString> m_startupOverrides;
    QHash<QString, QPointer<ModApi>> m_apis;
    QHash<QString, QPointer<ModScriptHost>> m_scriptHosts;
    QStringList m_scriptOrder;
    QStringList m_subscribedHookPoints;
    QList<QPair<QString, ModSlotItem>> m_dynamicPages;
    QHash<QString, ModSandbox> m_sandboxes;
    QList<ModTrackMenuAction> m_trackMenuActions;
    QList<ModShortcutEntry> m_shortcuts;
    QList<ModLogEntry> m_logs;

    QString m_lyricsTrackId;
    bool m_lyricsSynced = false;
    QVariantList m_lyricsLines;
    // modId -> (trackId -> subtitle lines)
    QHash<QString, QPair<QString, QStringList>> m_lyricSubtitles;
    int m_lyricSubtitlesRevision = 0;

    ModUrlInterceptor m_interceptor;
    QFileSystemWatcher m_watcher;
    QTimer m_watchDebounce;
};

} // namespace ymusic::mods
