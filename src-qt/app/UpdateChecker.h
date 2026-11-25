#pragma once

#include <QNetworkAccessManager>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QTimer>
#include <QUrl>
#include <QVersionNumber>

#include <optional>

class QFile;
class QNetworkReply;

namespace ymusic {

struct ReleaseManifest {
    QString version;
    QString tag;
    QUrl url;
    QString sha256;
    QUrl notesUrl;
};

/**
 * Checks GitHub Releases (latest-windows.json) for newer Windows builds,
 * streams and SHA-256 verifies the NSIS setup executable, and triggers a silent
 * /S /RELAUNCH update for installed copies.
 */
class UpdateChecker : public QObject {
    Q_OBJECT

    Q_PROPERTY(bool supported READ supported CONSTANT)
    Q_PROPERTY(bool installedCopy READ installedCopy CONSTANT)
    Q_PROPERTY(QString currentVersion READ currentVersion CONSTANT)
    Q_PROPERTY(QString latestVersion READ latestVersion NOTIFY stateChanged)
    Q_PROPERTY(QString releaseNotesUrl READ releaseNotesUrl NOTIFY stateChanged)
    Q_PROPERTY(int state READ state NOTIFY stateChanged)
    Q_PROPERTY(double progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY stateChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY stateChanged)
    Q_PROPERTY(bool hasError READ hasError NOTIFY stateChanged)
    Q_PROPERTY(bool portableUpdateAvailable READ portableUpdateAvailable NOTIFY stateChanged)
    Q_PROPERTY(bool readyToInstall READ readyToInstall NOTIFY stateChanged)
    Q_PROPERTY(bool updateBannerVisible READ updateBannerVisible NOTIFY bannerChanged)

public:
    enum State {
        Idle = 0,
        Checking,
        Downloading,
        Ready,
        AvailablePortable,
        UpToDate,
        Error,
    };
    Q_ENUM(State)

    explicit UpdateChecker(QObject *parent = nullptr);
    ~UpdateChecker() override;

    bool supported() const;
    bool installedCopy() const { return m_installedCopy; }
    QString currentVersion() const { return m_currentVersion; }
    QString latestVersion() const { return m_latestVersion; }
    QString releaseNotesUrl() const { return m_releaseNotesUrl.toString(); }
    int state() const { return m_state; }
    double progress() const { return m_progress; }
    QString statusText() const { return m_statusText; }
    bool busy() const { return m_state == Checking || m_state == Downloading; }
    bool hasError() const { return m_state == Error; }
    bool portableUpdateAvailable() const { return m_state == AvailablePortable; }
    bool readyToInstall() const { return m_state == Ready; }
    bool updateBannerVisible() const { return m_bannerVisible; }

    Q_INVOKABLE void startAutoCheck();
    Q_INVOKABLE void setAutoCheckEnabled(bool enabled);
    Q_INVOKABLE void checkForUpdates(bool userInitiated = true);
    Q_INVOKABLE void installAndRestart();
    Q_INVOKABLE void openReleasePage();
    Q_INVOKABLE void dismissBanner();

    static std::optional<QVersionNumber> parseSemver(const QString &raw, bool *isPreRelease = nullptr);
    static bool isNewerVersion(const QString &candidate, const QString &current);
    static bool isAllowedAssetUrl(const QUrl &assetUrl, const QUrl &manifestUrl);
    static std::optional<ReleaseManifest> parseManifest(
        const QByteArray &json,
        const QUrl &manifestUrl,
        QString *errorOut = nullptr);
    static QString fileSha256(const QString &path);

signals:
    void stateChanged();
    void progressChanged();
    void bannerChanged();

private:
    void setState(State state, const QString &statusText);
    void setProgress(double progress);
    void setBannerVisible(bool visible);
    void startDownload(const ReleaseManifest &manifest);
    void handleManifestReply(QNetworkReply *reply, bool userInitiated);
    void handleDownloadFinished(QNetworkReply *reply, const ReleaseManifest &manifest,
                                const QString &partPath, const QString &finalPath);
    void cleanupOldDownloads(const QString &keepPath = QString()) const;
    QUrl effectiveManifestUrl() const;
    QString targetInstallerPath(const QString &version) const;

    QNetworkAccessManager m_nam;
    QTimer m_startupTimer;
    QTimer m_periodicTimer;
    QPointer<QNetworkReply> m_activeReply;
    QFile *m_downloadFile = nullptr;

    QString m_currentVersion;
    bool m_installedCopy = false;
    bool m_autoCheckEnabled = true;

    State m_state = Idle;
    double m_progress = 0.0;
    QString m_statusText;
    QString m_latestVersion;
    QUrl m_releaseNotesUrl;
    QString m_downloadedPath;
    bool m_bannerVisible = false;
    bool m_bannerDismissedForSession = false;
};

} // namespace ymusic
