#include "ThemeManager.h"
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDebug>

ThemeManager &ThemeManager::instance() {
    static ThemeManager s_instance;
    return s_instance;
}

ThemeManager::ThemeManager(QObject *parent)
    : QObject(parent) {
    m_debounceTimer.setSingleShot(true);
    m_debounceTimer.setInterval(150);
    connect(&m_debounceTimer, &QTimer::timeout, this, &ThemeManager::loadColors);

    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, &ThemeManager::onFileChanged);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &ThemeManager::onFileChanged);

    QString home = QDir::homePath();
    QStringList paths = {
        home + "/.config/noctalia/colors.json",
        home + "/.local/state/quickshell/user/generated/colors.json",
        home + "/.config/presets/user/colors.json"
    };

    for (const QString &p : paths) {
        if (QFile::exists(p)) {
            m_watcher.addPath(p);
        }
        QFileInfo fi(p);
        if (fi.dir().exists()) {
            m_watcher.addPath(fi.dir().absolutePath());
        }
    }

    loadColors();
}

void ThemeManager::onFileChanged() {
    m_debounceTimer.start();
}

void ThemeManager::reload() {
    loadColors();
}

void ThemeManager::setDefaults() {
    m_background = QColor("#0a0c10");
    m_surface = QColor("#12151c");
    m_surfaceDim = QColor("#0e1015");
    m_surfaceBright = QColor("#232733");
    m_surfaceContainerLowest = QColor("#08090d");
    m_surfaceContainerLow = QColor("#141720");
    m_surfaceContainer = QColor("#191d28");
    m_surfaceContainerHigh = QColor("#212635");
    m_surfaceContainerHighest = QColor("#2b3144");
    m_onSurface = QColor("#f0f2f8");
    m_onSurfaceVariant = QColor("#9ea3b5");
    m_outline = QColor("#4b5166");
    m_outlineVariant = QColor("#262b3a");
    m_primary = QColor("#fc3f1d");
    m_primaryHover = QColor("#ff583b");
    m_onPrimary = QColor("#ffffff");
    m_primaryContainer = QColor("#45140b");
    m_onPrimaryContainer = QColor("#ffdad4");
    m_secondary = QColor("#e59b24");
    m_secondaryContainer = QColor("#362712");
    m_tertiary = QColor("#36c39f");
    m_error = QColor("#ff5449");
    m_isDark = true;
}

void ThemeManager::deriveSurfaces() {
    qreal lum = m_background.lightnessF();
    m_isDark = (lum < 0.5);

    if (m_isDark) {
        m_surfaceDim = m_surface.darker(110);
        m_surfaceBright = m_surface.lighter(130);
        m_surfaceContainerLowest = m_background.darker(115);
        m_surfaceContainerLow = m_surface.darker(108);
        m_surfaceContainer = m_surface;
        m_surfaceContainerHigh = m_surface.lighter(120);
        m_surfaceContainerHighest = m_surface.lighter(140);
        m_outlineVariant = m_outline.darker(145);
        m_primaryContainer = m_primary.darker(220);
        m_onPrimaryContainer = m_primary.lighter(170);
        m_secondaryContainer = m_secondary.darker(220);
    } else {
        m_surfaceDim = m_surface.darker(108);
        m_surfaceBright = m_surface.lighter(105);
        m_surfaceContainerLowest = m_background.lighter(105);
        m_surfaceContainerLow = m_surface.lighter(104);
        m_surfaceContainer = m_surface;
        m_surfaceContainerHigh = m_surface.darker(108);
        m_surfaceContainerHighest = m_surface.darker(115);
        m_outlineVariant = m_outline.lighter(130);
        m_primaryContainer = m_primary.lighter(180);
        m_onPrimaryContainer = m_primary.darker(200);
        m_secondaryContainer = m_secondary.lighter(180);
    }
}

bool ThemeManager::tryLoadNoctalia() {
    QString path = QDir::homePath() + "/.config/noctalia/colors.json";
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) return false;

    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (!doc.isObject()) return false;
    QJsonObject obj = doc.object();

    if (!obj.contains("mPrimary") || !obj.contains("mSurface")) return false;

    m_primary = QColor(obj["mPrimary"].toString());
    m_onPrimary = QColor(obj["mOnPrimary"].toString("#ffffff"));
    m_secondary = QColor(obj["mSecondary"].toString("#e59b24"));
    m_tertiary = QColor(obj["mTertiary"].toString("#36c39f"));
    m_error = QColor(obj["mError"].toString("#ff5449"));
    m_surface = QColor(obj["mSurface"].toString("#131313"));
    m_background = m_surface.darker(120);
    m_onSurface = QColor(obj["mOnSurface"].toString("#e2e2e2"));
    m_onSurfaceVariant = QColor(obj["mOnSurfaceVariant"].toString("#c6c6c6"));
    m_outline = QColor(obj["mOutline"].toString("#474747"));
    m_primaryHover = obj.contains("mHover") ? QColor(obj["mHover"].toString()) : m_primary.lighter(115);

    deriveSurfaces();
    return true;
}

bool ThemeManager::tryLoadQuickshell() {
    QString path = QDir::homePath() + "/.local/state/quickshell/user/generated/colors.json";
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) return false;

    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (!doc.isObject()) return false;
    QJsonObject obj = doc.object();

    if (!obj.contains("primary") || !obj.contains("surface")) return false;

    m_primary = QColor(obj["primary"].toString());
    m_onPrimary = QColor(obj["on_primary"].toString("#ffffff"));
    m_background = QColor(obj["background"].toString("#0a0c10"));
    m_surface = QColor(obj["surface"].toString("#12151c"));
    m_surfaceContainerLow = QColor(obj["surface_container_low"].toString());
    m_surfaceContainer = QColor(obj["surface_container"].toString());
    m_surfaceContainerHigh = QColor(obj["surface_container_high"].toString());
    m_surfaceContainerHighest = QColor(obj["surface_container_highest"].toString());
    m_onSurface = QColor(obj["on_surface"].toString("#f0f2f8"));
    m_onSurfaceVariant = QColor(obj["on_surface_variant"].toString("#9ea3b5"));
    m_outline = QColor(obj["outline"].toString("#4b5166"));
    m_outlineVariant = QColor(obj["outline_variant"].toString("#262b3a"));
    m_secondary = QColor(obj["secondary"].toString("#e59b24"));
    m_secondaryContainer = QColor(obj["secondary_container"].toString("#362712"));
    m_primaryHover = m_primary.lighter(115);

    deriveSurfaces();
    return true;
}

bool ThemeManager::tryLoadPresets() {
    QString path = QDir::homePath() + "/.config/presets/user/colors.json";
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) return false;

    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (!doc.isObject()) return false;
    QJsonObject root = doc.object();

    QJsonObject special = root["special"].toObject();
    QJsonObject colors = root["colors"].toObject();

    if (!special.contains("background")) return false;

    m_background = QColor(special["background"].toString());
    m_surface = m_background.lighter(115);
    m_onSurface = QColor(special["foreground"].toString("#e2e2e2"));
    m_onSurfaceVariant = m_onSurface.darker(130);
    m_primary = QColor(colors["color1"].toString("#fc3f1d"));
    m_primaryHover = m_primary.lighter(115);
    m_onPrimary = QColor("#ffffff");
    m_outline = QColor(colors["color8"].toString("#474747"));
    m_secondary = QColor(colors["color2"].toString("#e59b24"));

    deriveSurfaces();
    return true;
}

void ThemeManager::loadColors() {
    bool ok = tryLoadNoctalia();
    if (!ok) ok = tryLoadQuickshell();
    if (!ok) ok = tryLoadPresets();
    if (!ok) setDefaults();

    emit themeChanged();
}
