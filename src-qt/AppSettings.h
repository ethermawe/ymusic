#pragma once

#include <QObject>
#include <QSettings>
#include <QDesktopServices>
#include <QDir>
#include <QStandardPaths>
#include <QUrl>

// UI preferences are separate from the Rust playback/session settings.
class AppSettings : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool motionEnabled READ motionEnabled WRITE setMotionEnabled NOTIFY changed)
    Q_PROPERTY(bool iconAntialiasing READ iconAntialiasing WRITE setIconAntialiasing NOTIFY changed)
    Q_PROPERTY(bool coversEnabled READ coversEnabled WRITE setCoversEnabled NOTIFY changed)
    Q_PROPERTY(QString graphicsBackend READ graphicsBackend WRITE setGraphicsBackend NOTIFY changed)

public:
    explicit AppSettings(QObject *parent = nullptr) : QObject(parent), m_store("finrixx", "ymusic") {}

    bool motionEnabled() const { return m_store.value("ui/motionEnabled", true).toBool(); }
    bool iconAntialiasing() const { return m_store.value("ui/iconAntialiasing", true).toBool(); }
    bool coversEnabled() const { return m_store.value("ui/coversEnabled", true).toBool(); }
    QString graphicsBackend() const {
        const QString backend = m_store.value("ui/graphicsBackend", "auto").toString();
        return backend == "vulkan" || backend == "opengl" ? backend : "auto";
    }

    void setMotionEnabled(bool value) { if (value != motionEnabled()) save("ui/motionEnabled", value); }
    void setIconAntialiasing(bool value) { if (value != iconAntialiasing()) save("ui/iconAntialiasing", value); }
    void setCoversEnabled(bool value) { if (value != coversEnabled()) save("ui/coversEnabled", value); }
    void setGraphicsBackend(const QString &value) {
        if (value != "auto" && value != "opengl" && value != "vulkan") return;
        if (value != graphicsBackend()) save("ui/graphicsBackend", value);
    }

    Q_INVOKABLE bool openOfflineFolder() {
        // Rust dirs::data_local_dir() uses XDG_DATA_HOME/ymusic/offline on Linux.
        QString base = qEnvironmentVariable("XDG_DATA_HOME");
        if (base.isEmpty()) base = QDir::homePath() + "/.local/share";
        const QString path = base + "/ymusic/offline";
        return QDir().mkpath(path) && QDesktopServices::openUrl(QUrl::fromLocalFile(path));
    }

signals:
    void changed();
    void saveFailed();

private:
    void save(const QString &key, const QVariant &value) {
        m_store.setValue(key, value);
        m_store.sync();
        emit changed();
        if (m_store.status() != QSettings::NoError) emit saveFailed();
    }
    QSettings m_store;
};
