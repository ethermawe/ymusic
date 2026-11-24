#pragma once

#include "mods/ModManifest.h"

#include <QJsonObject>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QStringList>
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
/// signals, aborts pending HTTP requests, and cleans up registered menu actions.
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
    Q_PROPERTY(bool shuffle READ shuffle NOTIFY playbackChanged FINAL)
    Q_PROPERTY(int repeatMode READ repeatMode NOTIFY playbackChanged FINAL)
    Q_PROPERTY(qreal tempo READ tempo NOTIFY playbackChanged FINAL)

    Q_PROPERTY(qreal positionSecs READ positionSecs NOTIFY positionChanged FINAL)
    Q_PROPERTY(qreal durationSecs READ durationSecs NOTIFY positionChanged FINAL)
    Q_PROPERTY(qreal progress READ progress NOTIFY positionChanged FINAL)

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
    bool shuffle() const;
    int repeatMode() const;
    qreal tempo() const;

    qreal positionSecs() const;
    qreal durationSecs() const;
    qreal progress() const;

    // Playback control (requires "playback:control")
    Q_INVOKABLE bool toggle();
    Q_INVOKABLE bool next();
    Q_INVOKABLE bool prev();
    Q_INVOKABLE bool seek(qreal normalizedProgress);
    Q_INVOKABLE bool setVolume(qreal value);
    Q_INVOKABLE bool toggleLike();
    Q_INVOKABLE bool playNext(const QString &trackId);
    Q_INVOKABLE bool addToQueue(const QString &trackId);

    // Spectrum data (requires "spectrum:read")
    Q_INVOKABLE QVariantList spectrumLevels() const;
    Q_INVOKABLE QVariantList spectrumEnergies() const;

    // Persistent per-mod storage (requires "storage")
    Q_INVOKABLE QVariant storageGet(const QString &key, const QVariant &fallback = QVariant()) const;
    Q_INVOKABLE bool storageSet(const QString &key, const QVariant &value);
    Q_INVOKABLE bool storageRemove(const QString &key);
    Q_INVOKABLE QVariantMap storageAll() const;

    // UI helpers (requires "ui:slots")
    Q_INVOKABLE bool showToast(const QString &message);
    Q_INVOKABLE bool openImmersive();
    Q_INVOKABLE bool closeImmersive();
    Q_INVOKABLE bool openSettings();
    Q_INVOKABLE bool registerTrackMenuAction(const QString &actionId,
                                             const QString &label,
                                             const QString &symbol = QStringLiteral("extension"),
                                             bool destructive = false);
    Q_INVOKABLE void unregisterTrackMenuAction(const QString &actionId);

    // Clipboard & external web URLs
    Q_INVOKABLE bool copyText(const QString &text);
    Q_INVOKABLE bool openExternalUrl(const QString &url);

    // Allowlisted async HTTP (requires "network:<host>")
    Q_INVOKABLE bool httpGet(const QString &url, const QString &requestId);

    // Logging to Mod Console
    Q_INVOKABLE void log(const QString &message);
    Q_INVOKABLE void warn(const QString &message);

    void notifyTrackMenuAction(const QString &actionId, const QString &trackId, const QString &trackTitle);

signals:
    void trackChanged();
    void playbackChanged();
    void positionChanged();
    void spectrumUpdated();
    void trackMenuActionTriggered(const QString &actionId, const QString &trackId, const QString &trackTitle);
    void httpFinished(const QString &requestId, int statusCode, const QString &body, const QString &error);

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
};

} // namespace ymusic::mods
