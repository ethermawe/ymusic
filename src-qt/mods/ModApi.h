#pragma once

#include "mods/ModManifest.h"

#include <QJsonObject>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class QNetworkAccessManager;
class YMusicBackend;

namespace ymusic {
class SpectrumSource;
}

namespace ymusic::mods {

class ModManager;

/// Per-mod isolated API proxy. Destroying this object cleanly disconnects all
/// signals, aborts pending HTTP requests, and cleans up registered menu actions,
/// shortcuts, and lyric subtitles.
class ModApi : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Provided per mod by ModManager.")

    Q_PROPERTY(QString modId READ modId CONSTANT FINAL)
    Q_PROPERTY(QString modName READ modName CONSTANT FINAL)
    Q_PROPERTY(QStringList permissions READ permissions CONSTANT FINAL)

    // Read-only playback state (requires "playback:read")
    Q_PROPERTY(bool hasTrack READ hasTrack NOTIFY trackChanged FINAL)
    Q_PROPERTY(QString trackId READ trackId NOTIFY trackChanged FINAL)
    Q_PROPERTY(QString trackTitle READ trackTitle NOTIFY trackChanged FINAL)
    Q_PROPERTY(QString trackArtists READ trackArtists NOTIFY trackChanged FINAL)
    Q_PROPERTY(QString trackAlbum READ trackAlbum NOTIFY trackChanged FINAL)
    Q_PROPERTY(QString trackCover READ trackCover NOTIFY trackChanged FINAL)
    Q_PROPERTY(bool trackLiked READ trackLiked NOTIFY trackChanged FINAL)
    Q_PROPERTY(bool trackIsAi READ trackIsAi NOTIFY trackChanged FINAL)

    Q_PROPERTY(bool playing READ playing NOTIFY playbackChanged FINAL)
    Q_PROPERTY(bool buffering READ buffering NOTIFY playbackChanged FINAL)
    Q_PROPERTY(qreal volume READ volume NOTIFY playbackChanged FINAL)
    Q_PROPERTY(bool muted READ muted NOTIFY playbackChanged FINAL)
    Q_PROPERTY(bool shuffle READ shuffle NOTIFY playbackChanged FINAL)
    Q_PROPERTY(int repeatMode READ repeatMode NOTIFY playbackChanged FINAL)
    Q_PROPERTY(qreal tempo READ tempo NOTIFY playbackChanged FINAL)
    Q_PROPERTY(bool sleepTimerActive READ sleepTimerActive NOTIFY playbackChanged FINAL)
    Q_PROPERTY(int sleepTimerRemainingSecs READ sleepTimerRemainingSecs NOTIFY playbackChanged FINAL)

    Q_PROPERTY(qreal positionSecs READ positionSecs NOTIFY positionChanged FINAL)
    Q_PROPERTY(qreal durationSecs READ durationSecs NOTIFY positionChanged FINAL)
    Q_PROPERTY(qreal progress READ progress NOTIFY positionChanged FINAL)

    // UI panel state (requires "ui:slots")
    Q_PROPERTY(bool showingLyrics READ showingLyrics NOTIFY uiPanelChanged FINAL)
    Q_PROPERTY(bool showingQueue READ showingQueue NOTIFY uiPanelChanged FINAL)
    Q_PROPERTY(bool floatingWindowOpen READ floatingWindowOpen NOTIFY floatingWindowChanged FINAL)

    // Navigation & profile (requires "ui:slots" or "playback:read")
    Q_PROPERTY(int currentPage READ currentPage NOTIFY navigationChanged FINAL)
    Q_PROPERTY(bool canGoBack READ canGoBack NOTIFY navigationChanged FINAL)
    Q_PROPERTY(bool loggedIn READ loggedIn NOTIFY navigationChanged FINAL)
    Q_PROPERTY(QString userName READ userName NOTIFY navigationChanged FINAL)
    Q_PROPERTY(QString userAvatar READ userAvatar NOTIFY navigationChanged FINAL)
    Q_PROPERTY(QVariantList pinnedPlaylists READ pinnedPlaylists NOTIFY libraryChanged FINAL)

    // Lyrics state (requires "lyrics:read")
    Q_PROPERTY(QString lyricsTrackId READ lyricsTrackId NOTIFY lyricsChanged FINAL)
    Q_PROPERTY(bool lyricsSynced READ lyricsSynced NOTIFY lyricsChanged FINAL)
    Q_PROPERTY(QVariantList lyricsLines READ lyricsLines NOTIFY lyricsChanged FINAL)

public:
    explicit ModApi(ModManifest manifest,
                    ModManager *manager,
                    YMusicBackend *backend,
                    ymusic::SpectrumSource *spectrum,
                    QObject *parent = nullptr);
    ~ModApi() override;

    QString modId() const { return m_manifest.id; }
    QString modName() const { return m_manifest.name; }
    QStringList permissions() const { return m_manifest.permissions; }

    Q_INVOKABLE bool hasPermission(const QString &perm) const;

    bool hasTrack() const;
    QString trackId() const;
    QString trackTitle() const;
    QString trackArtists() const;
    QString trackAlbum() const;
    QString trackCover() const;
    bool trackLiked() const;
    bool trackIsAi() const;

    bool playing() const;
    bool buffering() const;
    qreal volume() const;
    bool muted() const;
    bool shuffle() const;
    int repeatMode() const;
    qreal tempo() const;
    bool sleepTimerActive() const;
    int sleepTimerRemainingSecs() const;

    qreal positionSecs() const;
    qreal durationSecs() const;
    qreal progress() const;

    bool showingLyrics() const;
    bool showingQueue() const;
    bool floatingWindowOpen() const;

    int currentPage() const;
    bool canGoBack() const;
    bool loggedIn() const;
    QString userName() const;
    QString userAvatar() const;
    QVariantList pinnedPlaylists() const;

    QString lyricsTrackId() const;
    bool lyricsSynced() const;
    QVariantList lyricsLines() const;

    // Playback control (requires "playback:control")
    Q_INVOKABLE bool toggle();
    Q_INVOKABLE bool next();
    Q_INVOKABLE bool prev();
    Q_INVOKABLE bool seek(qreal normalizedProgress);
    Q_INVOKABLE bool setVolume(qreal value);
    Q_INVOKABLE bool toggleMute();
    Q_INVOKABLE bool setTempo(qreal speed);
    Q_INVOKABLE bool toggleLike();
    Q_INVOKABLE bool dislikeNow();
    Q_INVOKABLE bool toggleShuffle();
    Q_INVOKABLE bool toggleRepeat();
    Q_INVOKABLE bool startSleepTimer(int seconds, const QString &fadeMode = QStringLiteral("finalSeconds"));
    Q_INVOKABLE bool cancelSleepTimer();
    Q_INVOKABLE bool playNext(const QString &trackId);
    Q_INVOKABLE bool addToQueue(const QString &trackId);
    Q_INVOKABLE bool playQueueIndex(int index);
    Q_INVOKABLE bool removeFromQueue(int index);
    Q_INVOKABLE bool clearQueue();

    // Navigation & UI panels (requires "ui:slots")
    Q_INVOKABLE bool openHome();
    Q_INVOKABLE bool openWave();
    Q_INVOKABLE bool openLikes();
    Q_INVOKABLE bool openDownloads();
    Q_INVOKABLE bool openPlaylists();
    Q_INVOKABLE bool openAlbums();
    Q_INVOKABLE bool openArtists();
    Q_INVOKABLE bool openSearch(const QString &query);
    Q_INVOKABLE bool openPlaylist(const QString &uid, const QString &kind, const QString &title = QString());
    Q_INVOKABLE bool openNowArtist();
    Q_INVOKABLE bool openNowAlbum();
    Q_INVOKABLE bool startArtistWave();
    Q_INVOKABLE bool toggleLyrics();
    Q_INVOKABLE bool toggleQueue();
    Q_INVOKABLE bool goBack();
    Q_INVOKABLE bool openCreatePlaylist();

    // Layout control (requires "ui:layout")
    Q_INVOKABLE bool setPlayerBarHidden(bool hidden);

    // Floating desktop window control (requires "ui:window")
    Q_INVOKABLE bool setFloatingWindowOpen(bool open);
    Q_INVOKABLE bool toggleFloatingWindow();

    // Library & queue snapshots (requires "library:read")
    Q_INVOKABLE QVariantList queueTracks() const;
    Q_INVOKABLE QVariantList currentTracks() const;
    Q_INVOKABLE QVariantList historyTracks() const;
    Q_INVOKABLE bool isDownloaded(const QString &trackId) const;

    // Library write actions (requires "library:write")
    Q_INVOKABLE bool addToPlaylist(const QString &trackId, const QString &kind);
    Q_INVOKABLE bool saveOffline(const QString &trackId);

    // Lyrics transformation (requires "lyrics:transform")
    Q_INVOKABLE bool setLyricSubtitles(const QString &trackId, const QVariantList &subtitles);
    Q_INVOKABLE void clearLyricSubtitles();

    // Track metadata / audio overrides and album injections
    // (requires "catalog:override" for metadata/injections, "audio:override" for audio replacement)
    Q_INVOKABLE bool setTrackOverrides(const QVariantMap &overrides);
    Q_INVOKABLE bool setAlbumInjections(const QString &albumId, const QVariantList &tracks);
    Q_INVOKABLE void clearTrackOverrides();

    // Spectrum data (requires "spectrum:read")
    Q_INVOKABLE QVariantList spectrumLevels() const;
    Q_INVOKABLE QVariantList spectrumEnergies() const;

    // Persistent per-mod storage (requires "storage")
    Q_INVOKABLE QVariant storageGet(const QString &key, const QVariant &fallback = QVariant()) const;
    Q_INVOKABLE bool storageSet(const QString &key, const QVariant &value);
    Q_INVOKABLE bool storageRemove(const QString &key);
    Q_INVOKABLE QVariantMap storageAll() const;

    // UI helpers & shortcuts (requires "ui:slots")
    Q_INVOKABLE bool showToast(const QString &message);
    Q_INVOKABLE bool openImmersive();
    Q_INVOKABLE bool closeImmersive();
    Q_INVOKABLE bool openSettings();
    Q_INVOKABLE bool registerTrackMenuAction(const QString &actionId,
                                             const QString &label,
                                             const QString &symbol = QStringLiteral("extension"),
                                             bool destructive = false);
    Q_INVOKABLE void unregisterTrackMenuAction(const QString &actionId);
    Q_INVOKABLE bool registerShortcut(const QString &actionId,
                                      const QString &sequence,
                                      const QString &description = QString());
    Q_INVOKABLE void unregisterShortcut(const QString &actionId);
    Q_INVOKABLE bool setTrackBadges(const QVariantMap &badges);
    Q_INVOKABLE void clearTrackBadges();

    // Clipboard & external web URLs
    Q_INVOKABLE bool copyText(const QString &text);
    Q_INVOKABLE bool openExternalUrl(const QString &url);

    // Allowlisted async HTTP (requires "network:<host>")
    Q_INVOKABLE bool httpGet(const QString &url, const QString &requestId);
    Q_INVOKABLE bool httpRequest(const QString &method,
                                 const QString &url,
                                 const QVariantMap &headers,
                                 const QString &body,
                                 const QString &requestId);

    // Logging to Mod Console
    Q_INVOKABLE void log(const QString &message);
    Q_INVOKABLE void warn(const QString &message);

    // Bridge to mod's JS main.js (`ym.ui.expose`)
    Q_INVOKABLE QVariant call(const QString &name, const QVariantList &args = {});

    void notifyTrackMenuAction(const QString &actionId, const QString &trackId, const QString &trackTitle);
    void notifyShortcut(const QString &actionId);
    void notifyLyricsChanged();
    void flushStorage();

signals:
    void trackChanged();
    void playbackChanged();
    void positionChanged();
    void navigationChanged();
    void uiPanelChanged();
    void floatingWindowChanged();
    void libraryChanged();
    void lyricsChanged();
    void spectrumUpdated();
    void trackMenuActionTriggered(const QString &actionId, const QString &trackId, const QString &trackTitle);
    void shortcutTriggered(const QString &actionId);
    void httpFinished(const QString &requestId, int statusCode, const QString &body, const QString &error);
    void storageChanged(const QString &key);

private:
    bool requirePermission(const QString &perm, const char *actionName);
    QString storageFilePath() const;
    void loadStorage();
    bool saveStorage() const;

    ModManifest m_manifest;
    QPointer<ModManager> m_manager;
    YMusicBackend *m_backend = nullptr;
    ymusic::SpectrumSource *m_spectrum = nullptr;
    QPointer<QNetworkAccessManager> m_network;
    QJsonObject m_storage;
    QTimer m_storageFlushTimer;
    bool m_storageDirty = false;
};

} // namespace ymusic::mods
