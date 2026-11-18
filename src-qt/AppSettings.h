#pragma once

#include <QDesktopServices>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QObject>
#include <QSettings>
#include <QStandardPaths>
#include <QUrl>
#include <algorithm>

#include "app/Paths.h"

// UI preferences are separate from the Rust playback/session settings.
class AppSettings : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool motionEnabled READ motionEnabled WRITE setMotionEnabled NOTIFY changed)
    Q_PROPERTY(bool reduceMotion READ reduceMotion WRITE setReduceMotion NOTIFY reduceMotionChanged)
    Q_PROPERTY(bool performanceMode READ performanceMode WRITE setPerformanceMode NOTIFY performanceModeChanged)
    Q_PROPERTY(bool fastImmersiveTransition READ fastImmersiveTransition WRITE setFastImmersiveTransition NOTIFY fastImmersiveTransitionChanged)
    Q_PROPERTY(bool noShapes READ noShapes WRITE setNoShapes NOTIFY noShapesChanged)
    Q_PROPERTY(bool iconAntialiasing READ iconAntialiasing WRITE setIconAntialiasing NOTIFY changed)
    Q_PROPERTY(bool coversEnabled READ coversEnabled WRITE setCoversEnabled NOTIFY changed)
    Q_PROPERTY(bool discordRpcEnabled READ discordRpcEnabled WRITE setDiscordRpcEnabled NOTIFY changed)
    Q_PROPERTY(QString themePreset READ themePreset WRITE setThemePreset NOTIFY themeChanged)
    Q_PROPERTY(QString themeMode READ themeMode WRITE setThemeMode NOTIFY themeChanged)
    Q_PROPERTY(QString matugenColorsPath READ matugenColorsPath WRITE setMatugenColorsPath NOTIFY themeChanged)
    Q_PROPERTY(QString graphicsBackend READ graphicsBackend WRITE setGraphicsBackend NOTIFY changed)

    Q_PROPERTY(bool visualizersEnabled READ visualizersEnabled WRITE setVisualizersEnabled NOTIFY visualizersEnabledChanged)
    Q_PROPERTY(bool playerBarVisualizer READ playerBarVisualizer WRITE setPlayerBarVisualizer NOTIFY visualizerTogglesChanged)
    Q_PROPERTY(bool immersiveVisualizer READ immersiveVisualizer WRITE setImmersiveVisualizer NOTIFY visualizerTogglesChanged)
    Q_PROPERTY(bool circularVisualizer READ circularVisualizer WRITE setCircularVisualizer NOTIFY visualizerTogglesChanged)
    Q_PROPERTY(bool continuousVisualizer READ continuousVisualizer WRITE setContinuousVisualizer NOTIFY visualizerTogglesChanged)
    Q_PROPERTY(bool roundArtwork READ roundArtwork WRITE setRoundArtwork NOTIFY roundArtworkChanged)
    Q_PROPERTY(QString visualizerShape READ visualizerShape WRITE setVisualizerShape NOTIFY visualizerShapeChanged)
    Q_PROPERTY(double visualizerSensitivity READ visualizerSensitivity WRITE setVisualizerSensitivity NOTIFY visualizerSensitivityChanged)

    Q_PROPERTY(bool livingBackdrop READ livingBackdrop WRITE setLivingBackdrop NOTIFY livingBackdropChanged)
    Q_PROPERTY(double backdropBlur READ backdropBlur WRITE setBackdropBlur NOTIFY backdropBlurChanged)
    Q_PROPERTY(double backdropReactivity READ backdropReactivity WRITE setBackdropReactivity NOTIFY backdropReactivityChanged)

    Q_PROPERTY(bool waveVisualizer READ waveVisualizer WRITE setWaveVisualizer NOTIFY waveSettingsChanged)
    Q_PROPERTY(QString waveVisualizerShape READ waveVisualizerShape WRITE setWaveVisualizerShape NOTIFY waveSettingsChanged)
    Q_PROPERTY(double waveVisualizerSensitivity READ waveVisualizerSensitivity WRITE setWaveVisualizerSensitivity NOTIFY waveSettingsChanged)
    Q_PROPERTY(bool waveOrbArtwork READ waveOrbArtwork WRITE setWaveOrbArtwork NOTIFY waveSettingsChanged)
    Q_PROPERTY(bool waveOrbSquiggle READ waveOrbSquiggle WRITE setWaveOrbSquiggle NOTIFY waveSettingsChanged)
    Q_PROPERTY(double waveReactivity READ waveReactivity WRITE setWaveReactivity NOTIFY waveSettingsChanged)

    Q_PROPERTY(double zoom READ zoom WRITE setZoom NOTIFY zoomChanged)
    Q_PROPERTY(double scrollSpeed READ scrollSpeed WRITE setScrollSpeed NOTIFY scrollSpeedChanged)
    Q_PROPERTY(bool pinnedPlaylistsExpanded READ pinnedPlaylistsExpanded WRITE setPinnedPlaylistsExpanded NOTIFY changed)
    Q_PROPERTY(bool allPlaylistsExpanded READ allPlaylistsExpanded WRITE setAllPlaylistsExpanded NOTIFY changed)
    Q_PROPERTY(QString immersivePlayerPanel READ immersivePlayerPanel WRITE setImmersivePlayerPanel NOTIFY changed)
    Q_PROPERTY(QString sleepTimerFade READ sleepTimerFade WRITE setSleepTimerFade NOTIFY changed)
    Q_PROPERTY(double playbackSpeed READ playbackSpeed WRITE setPlaybackSpeed NOTIFY changed)
    Q_PROPERTY(bool debuggingEnabled READ debuggingEnabled WRITE setDebuggingEnabled NOTIFY debuggingEnabledChanged)
    Q_PROPERTY(bool showWindowControls READ showWindowControls WRITE setShowWindowControls NOTIFY windowControlsChanged)
    Q_PROPERTY(bool windowControlsOnRight READ windowControlsOnRight WRITE setWindowControlsOnRight NOTIFY windowControlsChanged)
    Q_PROPERTY(bool nativeTitleBar READ nativeTitleBar WRITE setNativeTitleBar NOTIFY windowControlsChanged)
    Q_PROPERTY(bool minimizeToTray READ minimizeToTray WRITE setMinimizeToTray NOTIFY minimizeToTrayChanged)
    Q_PROPERTY(bool burstsEnabled READ burstsEnabled WRITE setBurstsEnabled NOTIFY burstsEnabledChanged)
    Q_PROPERTY(double volumeStep READ volumeStep WRITE setVolumeStep NOTIFY volumeStepChanged)
    Q_PROPERTY(bool autoUpdateEnabled READ autoUpdateEnabled WRITE setAutoUpdateEnabled NOTIFY autoUpdateEnabledChanged)

public:
    explicit AppSettings(QObject *parent = nullptr) : QObject(parent), m_store("finrixx", "ymusic") {
        s_instance = this;
    }

    static AppSettings *instance() { return s_instance; }

    bool motionEnabled() const { return m_store.value("ui/motionEnabled", true).toBool(); }
    bool reduceMotion() const { return !motionEnabled(); }
    bool performanceMode() const { return m_store.value("ui/performanceMode", false).toBool(); }
    bool fastImmersiveTransition() const { return m_store.value("ui/fastImmersiveTransition", false).toBool(); }
    bool noShapes() const { return m_store.value("ui/noShapes", false).toBool(); }
    bool iconAntialiasing() const { return m_store.value("ui/iconAntialiasing", true).toBool(); }
    bool coversEnabled() const { return m_store.value("ui/coversEnabled", true).toBool(); }
    bool discordRpcEnabled() const { return m_store.value("ui/discordRpcEnabled", true).toBool(); }
    QString themePreset() const { return m_store.value("ui/themePreset", "auto").toString(); }
    QString themeMode() const { return m_store.value("ui/themeMode", "auto").toString(); }
    QString matugenColorsPath() const { return m_store.value("ui/matugenColorsPath", "").toString(); }
    QString graphicsBackend() const {
        const QString backend = m_store.value("ui/graphicsBackend", "auto").toString();
        return backend == "vulkan" || backend == "opengl" ? backend : "auto";
    }

    bool visualizersEnabled() const { return m_store.value("ui/visualizersEnabled", true).toBool(); }
    bool playerBarVisualizer() const { return m_store.value("ui/playerBarVisualizer", true).toBool(); }
    bool immersiveVisualizer() const { return m_store.value("ui/immersiveVisualizer", true).toBool(); }
    bool circularVisualizer() const { return m_store.value("ui/circularVisualizer", false).toBool(); }
    bool continuousVisualizer() const { return m_store.value("ui/continuousVisualizer", false).toBool(); }
    bool roundArtwork() const { return m_store.value("ui/roundArtwork", false).toBool(); }
    QString visualizerShape() const { return m_store.value("ui/visualizerShape", "bars").toString(); }
    double visualizerSensitivity() const { return std::clamp(m_store.value("ui/visualizerSensitivity", 1.0).toDouble(), 0.2, 2.5); }

    bool livingBackdrop() const { return m_store.value("ui/livingBackdrop", true).toBool(); }
    double backdropBlur() const { return std::clamp(m_store.value("ui/backdropBlur", 40.0).toDouble(), 0.0, 100.0); }
    double backdropReactivity() const { return std::clamp(m_store.value("ui/backdropReactivity", 1.0).toDouble(), 0.0, 2.0); }

    bool waveVisualizer() const { return m_store.value("ui/waveVisualizer", true).toBool(); }
    QString waveVisualizerShape() const {
        const QString shape = m_store.value("ui/waveVisualizerShape", "bars").toString();
        return shape == "wave" ? "wave" : "bars";
    }
    double waveVisualizerSensitivity() const { return std::clamp(m_store.value("ui/waveVisualizerSensitivity", 1.0).toDouble(), 0.2, 2.5); }
    bool waveOrbArtwork() const { return m_store.value("ui/waveOrbArtwork", true).toBool(); }
    bool waveOrbSquiggle() const { return m_store.value("ui/waveOrbSquiggle", true).toBool(); }
    double waveReactivity() const { return std::clamp(m_store.value("ui/waveReactivity", 1.0).toDouble(), 0.0, 3.0); }

    double zoom() const { return std::clamp(m_store.value("ui/zoom", 1.0).toDouble(), 0.75, 1.4); }
    double scrollSpeed() const { return std::clamp(m_store.value("ui/scrollSpeed", 1.8).toDouble(), 0.5, 6.0); }
    bool pinnedPlaylistsExpanded() const { return m_store.value("ui/pinnedPlaylistsExpanded", true).toBool(); }
    bool allPlaylistsExpanded() const { return m_store.value("ui/allPlaylistsExpanded", true).toBool(); }
    QString immersivePlayerPanel() const { return m_store.value("ui/immersivePlayerPanel", "lyrics").toString(); }
    QString sleepTimerFade() const { return m_store.value("ui/sleepTimerFade", "finalSeconds").toString(); }
    double playbackSpeed() const { return std::clamp(m_store.value("ui/playbackSpeed", 1.0).toDouble(), 0.5, 2.0); }
    bool debuggingEnabled() const { return m_store.value("ui/debuggingEnabled", false).toBool(); }
    bool showWindowControls() const { return m_store.value("ui/showWindowControls", true).toBool(); }
    bool windowControlsOnRight() const { return m_store.value("ui/windowControlsOnRight", false).toBool(); }
    bool nativeTitleBar() const { return m_store.value("ui/nativeTitleBar", false).toBool(); }
    bool minimizeToTray() const { return m_store.value("ui/minimizeToTray", true).toBool(); }
    bool burstsEnabled() const { return m_store.value("ui/burstsEnabled", true).toBool(); }
    double volumeStep() const { return std::clamp(m_store.value("ui/volumeStep", 0.05).toDouble(), 0.01, 0.2); }
    bool autoUpdateEnabled() const { return m_store.value("app/autoUpdateEnabled", true).toBool(); }

    void setMotionEnabled(bool value) {
        if (value != motionEnabled()) {
            save("ui/motionEnabled", value);
            emit reduceMotionChanged();
        }
    }
    void setReduceMotion(bool value) { setMotionEnabled(!value); }
    void setPerformanceMode(bool value) {
        if (value != performanceMode()) {
            save("ui/performanceMode", value);
            emit performanceModeChanged();
        }
    }
    void setFastImmersiveTransition(bool value) {
        if (value != fastImmersiveTransition()) {
            save("ui/fastImmersiveTransition", value);
            emit fastImmersiveTransitionChanged();
        }
    }
    void setNoShapes(bool value) {
        if (value != noShapes()) {
            save("ui/noShapes", value);
            emit noShapesChanged();
        }
    }
    void setIconAntialiasing(bool value) { if (value != iconAntialiasing()) save("ui/iconAntialiasing", value); }
    void setCoversEnabled(bool value) { if (value != coversEnabled()) save("ui/coversEnabled", value); }
    void setDiscordRpcEnabled(bool value) { if (value != discordRpcEnabled()) save("ui/discordRpcEnabled", value); }
    void setThemePreset(const QString &value) {
        if (value != themePreset()) {
            save("ui/themePreset", value);
            emit themeChanged();
        }
    }
    void setThemeMode(const QString &value) {
        if (value != themeMode()) {
            save("ui/themeMode", value);
            emit themeChanged();
        }
    }
    void setMatugenColorsPath(const QString &value) {
        if (value != matugenColorsPath()) {
            save("ui/matugenColorsPath", value);
            emit themeChanged();
        }
    }
    void setGraphicsBackend(const QString &value) {
        if (value != "auto" && value != "opengl" && value != "vulkan") return;
        if (value != graphicsBackend()) save("ui/graphicsBackend", value);
    }

    void setVisualizersEnabled(bool value) {
        if (value != visualizersEnabled()) {
            save("ui/visualizersEnabled", value);
            emit visualizersEnabledChanged();
            emit visualizerTogglesChanged();
        }
    }
    void setPlayerBarVisualizer(bool value) {
        if (value != playerBarVisualizer()) {
            save("ui/playerBarVisualizer", value);
            emit visualizerTogglesChanged();
        }
    }
    void setImmersiveVisualizer(bool value) {
        if (value != immersiveVisualizer()) {
            save("ui/immersiveVisualizer", value);
            emit visualizerTogglesChanged();
        }
    }
    void setCircularVisualizer(bool value) {
        if (value != circularVisualizer()) {
            save("ui/circularVisualizer", value);
            emit visualizerTogglesChanged();
        }
    }
    void setContinuousVisualizer(bool value) {
        if (value != continuousVisualizer()) {
            save("ui/continuousVisualizer", value);
            emit visualizerTogglesChanged();
        }
    }
    void setRoundArtwork(bool value) {
        if (value != roundArtwork()) {
            save("ui/roundArtwork", value);
            emit roundArtworkChanged();
        }
    }
    void setVisualizerShape(const QString &value) {
        if (value != visualizerShape()) {
            save("ui/visualizerShape", value);
            emit visualizerShapeChanged();
        }
    }
    void setVisualizerSensitivity(double value) {
        const double clamped = std::clamp(value, 0.2, 2.5);
        if (!qFuzzyCompare(clamped, visualizerSensitivity())) {
            save("ui/visualizerSensitivity", clamped);
            emit visualizerSensitivityChanged();
        }
    }

    void setLivingBackdrop(bool value) {
        if (value != livingBackdrop()) {
            save("ui/livingBackdrop", value);
            emit livingBackdropChanged();
        }
    }
    void setBackdropBlur(double value) {
        const double clamped = std::clamp(value, 0.0, 100.0);
        if (!qFuzzyCompare(clamped, backdropBlur())) {
            save("ui/backdropBlur", clamped);
            emit backdropBlurChanged();
        }
    }
    void setBackdropReactivity(double value) {
        const double clamped = std::clamp(value, 0.0, 2.0);
        if (!qFuzzyCompare(clamped, backdropReactivity())) {
            save("ui/backdropReactivity", clamped);
            emit backdropReactivityChanged();
        }
    }

    void setWaveVisualizer(bool value) {
        if (value != waveVisualizer()) {
            save("ui/waveVisualizer", value);
            emit waveSettingsChanged();
        }
    }
    void setWaveVisualizerShape(const QString &value) {
        const QString normalized = value == "wave" ? "wave" : "bars";
        if (normalized != waveVisualizerShape()) {
            save("ui/waveVisualizerShape", normalized);
            emit waveSettingsChanged();
        }
    }
    void setWaveVisualizerSensitivity(double value) {
        const double clamped = std::clamp(value, 0.2, 2.5);
        if (!qFuzzyCompare(clamped, waveVisualizerSensitivity())) {
            save("ui/waveVisualizerSensitivity", clamped);
            emit waveSettingsChanged();
        }
    }
    void setWaveOrbArtwork(bool value) {
        if (value != waveOrbArtwork()) {
            save("ui/waveOrbArtwork", value);
            emit waveSettingsChanged();
        }
    }
    void setWaveOrbSquiggle(bool value) {
        if (value != waveOrbSquiggle()) {
            save("ui/waveOrbSquiggle", value);
            emit waveSettingsChanged();
        }
    }
    void setWaveReactivity(double value) {
        const double clamped = std::clamp(value, 0.0, 3.0);
        if (!qFuzzyCompare(clamped, waveReactivity())) {
            save("ui/waveReactivity", clamped);
            emit waveSettingsChanged();
        }
    }

    void setZoom(double value) {
        const double clamped = std::clamp(value, 0.75, 1.4);
        if (!qFuzzyCompare(clamped, zoom())) {
            save("ui/zoom", clamped);
            emit zoomChanged();
        }
    }
    void setScrollSpeed(double value) {
        const double clamped = std::clamp(value, 0.5, 6.0);
        if (!qFuzzyCompare(clamped, scrollSpeed())) {
            save("ui/scrollSpeed", clamped);
            emit scrollSpeedChanged();
        }
    }
    void setPinnedPlaylistsExpanded(bool value) { if (value != pinnedPlaylistsExpanded()) save("ui/pinnedPlaylistsExpanded", value); }
    void setAllPlaylistsExpanded(bool value) { if (value != allPlaylistsExpanded()) save("ui/allPlaylistsExpanded", value); }
    void setImmersivePlayerPanel(const QString &value) { if (value != immersivePlayerPanel()) save("ui/immersivePlayerPanel", value); }
    void setSleepTimerFade(const QString &value) { if (value != sleepTimerFade()) save("ui/sleepTimerFade", value); }
    void setPlaybackSpeed(double value) {
        const double clamped = std::clamp(value, 0.5, 2.0);
        if (!qFuzzyCompare(clamped, playbackSpeed())) save("ui/playbackSpeed", clamped);
    }
    void setDebuggingEnabled(bool value) {
        if (value != debuggingEnabled()) {
            save("ui/debuggingEnabled", value);
            emit debuggingEnabledChanged();
        }
    }
    void setShowWindowControls(bool value) {
        if (value != showWindowControls()) {
            save("ui/showWindowControls", value);
            emit windowControlsChanged();
        }
    }
    void setWindowControlsOnRight(bool value) {
        if (value != windowControlsOnRight()) {
            save("ui/windowControlsOnRight", value);
            emit windowControlsChanged();
        }
    }
    void setNativeTitleBar(bool value) {
        if (value != nativeTitleBar()) {
            save("ui/nativeTitleBar", value);
            emit windowControlsChanged();
        }
    }
    void setMinimizeToTray(bool value) {
        if (value != minimizeToTray()) {
            save("ui/minimizeToTray", value);
            emit minimizeToTrayChanged();
        }
    }
    void setBurstsEnabled(bool value) {
        if (value != burstsEnabled()) {
            save("ui/burstsEnabled", value);
            emit burstsEnabledChanged();
        }
    }
    void setVolumeStep(double value) {
        const double clamped = std::clamp(value, 0.01, 0.2);
        if (!qFuzzyCompare(clamped, volumeStep())) {
            save("ui/volumeStep", clamped);
            emit volumeStepChanged();
        }
    }
    void setAutoUpdateEnabled(bool value) {
        if (value != autoUpdateEnabled()) {
            save("app/autoUpdateEnabled", value);
            emit autoUpdateEnabledChanged();
        }
    }

    Q_INVOKABLE bool openOfflineFolder() {
        QString base = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation);
        if (base.isEmpty()) base = QDir::homePath() + "/.local/share";
        const QString path = base + "/ymusic/offline";
        return QDir().mkpath(path) && QDesktopServices::openUrl(QUrl::fromLocalFile(path));
    }

    Q_INVOKABLE bool openLogsFolder() {
        const QString path = ymusic::paths::logDirectory();
        return QDir().mkpath(path) && QDesktopServices::openUrl(QUrl::fromLocalFile(path));
    }

    Q_INVOKABLE QString cacheSizeText() const {
        const QString root = ymusic::paths::cacheDirectory();
        qint64 bytes = 0;
        QDirIterator it(root, QDir::Files | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            it.next();
            bytes += it.fileInfo().size();
        }
        if (bytes < 1024) return QStringLiteral("0 КБ");
        if (bytes < 1024 * 1024) return QString::number(qMax(1LL, bytes / 1024)) + QStringLiteral(" КБ");
        if (bytes < 1024LL * 1024 * 1024) {
            return QString::number(static_cast<double>(bytes) / (1024.0 * 1024.0), 'f', 1) + QStringLiteral(" МБ");
        }
        return QString::number(static_cast<double>(bytes) / (1024.0 * 1024.0 * 1024.0), 'f', 2) + QStringLiteral(" ГБ");
    }

    Q_INVOKABLE bool clearCoverCache() {
        const QString root = ymusic::paths::cacheDirectory();
        QDir dir(root);
        if (!dir.exists()) return true;
        bool ok = true;
        const QFileInfoList entries = dir.entryInfoList(QDir::NoDotAndDotDot | QDir::AllEntries);
        for (const QFileInfo &entry : entries) {
            if (entry.isDir()) {
                QDir sub(entry.absoluteFilePath());
                if (!sub.removeRecursively()) ok = false;
            } else {
                if (!QFile::remove(entry.absoluteFilePath())) ok = false;
            }
        }
        return ok;
    }

    Q_INVOKABLE void resetUiSettings() {
        m_store.beginGroup("ui");
        m_store.remove("");
        m_store.endGroup();
        m_store.sync();
        emit changed();
        emit reduceMotionChanged();
        emit performanceModeChanged();
        emit fastImmersiveTransitionChanged();
        emit noShapesChanged();
        emit visualizersEnabledChanged();
        emit visualizerTogglesChanged();
        emit roundArtworkChanged();
        emit visualizerShapeChanged();
        emit visualizerSensitivityChanged();
        emit livingBackdropChanged();
        emit backdropBlurChanged();
        emit backdropReactivityChanged();
        emit waveSettingsChanged();
        emit zoomChanged();
        emit scrollSpeedChanged();
        emit debuggingEnabledChanged();
        emit windowControlsChanged();
        emit minimizeToTrayChanged();
        emit burstsEnabledChanged();
        emit volumeStepChanged();
        emit themeChanged();
    }

signals:
    void changed();
    void saveFailed();
    void reduceMotionChanged();
    void performanceModeChanged();
    void fastImmersiveTransitionChanged();
    void noShapesChanged();
    void visualizersEnabledChanged();
    void visualizerTogglesChanged();
    void roundArtworkChanged();
    void visualizerShapeChanged();
    void visualizerSensitivityChanged();
    void livingBackdropChanged();
    void backdropBlurChanged();
    void backdropReactivityChanged();
    void waveSettingsChanged();
    void zoomChanged();
    void scrollSpeedChanged();
    void debuggingEnabledChanged();
    void windowControlsChanged();
    void minimizeToTrayChanged();
    void burstsEnabledChanged();
    void volumeStepChanged();
    void themeChanged();
    void autoUpdateEnabledChanged();

private:
    void save(const QString &key, const QVariant &value) {
        m_store.setValue(key, value);
        m_store.sync();
        emit changed();
        if (m_store.status() != QSettings::NoError) emit saveFailed();
    }
    QSettings m_store;
    inline static AppSettings *s_instance = nullptr;
};
