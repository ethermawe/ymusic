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
        home + "/.local/state/quickshell/user/generated/colors.json",
        home + "/.cache/wal/colors.json",
        home + "/.config/presets/user/colors.json",
        home + "/.config/noctalia/colors.json"
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
    if (m_preset != "auto") return;
    // При атомарной замене файла (rename) watcher теряет его — добавляем заново.
    QString home = QDir::homePath();
    const QStringList paths = {
        home + "/.local/state/quickshell/user/generated/colors.json",
        home + "/.cache/wal/colors.json",
        home + "/.config/presets/user/colors.json",
        home + "/.config/noctalia/colors.json"
    };
    const QStringList watched = m_watcher.files();
    for (const QString &p : paths) {
        if (!watched.contains(p) && QFile::exists(p)) {
            m_watcher.addPath(p);
        }
    }
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

    m_background = QColor(obj["background"].toString("#141314"));
    m_surface = QColor(obj["surface"].toString("#141314"));
    m_surfaceDim = obj.contains("surface_dim") ? QColor(obj["surface_dim"].toString()) : m_surface.darker(110);
    m_surfaceBright = obj.contains("surface_bright") ? QColor(obj["surface_bright"].toString()) : m_surface.lighter(130);
    m_surfaceContainerLowest = obj.contains("surface_container_lowest") ? QColor(obj["surface_container_lowest"].toString()) : m_background.darker(115);
    m_surfaceContainerLow = obj.contains("surface_container_low") ? QColor(obj["surface_container_low"].toString()) : m_surface.darker(108);
    m_surfaceContainer = obj.contains("surface_container") ? QColor(obj["surface_container"].toString()) : m_surface;
    m_surfaceContainerHigh = obj.contains("surface_container_high") ? QColor(obj["surface_container_high"].toString()) : m_surface.lighter(120);
    m_surfaceContainerHighest = obj.contains("surface_container_highest") ? QColor(obj["surface_container_highest"].toString()) : m_surface.lighter(140);

    m_onSurface = QColor(obj["on_surface"].toString("#e7e1e3"));
    m_onSurfaceVariant = QColor(obj["on_surface_variant"].toString("#cac5c7"));
    m_outline = QColor(obj["outline"].toString("#949091"));
    m_outlineVariant = QColor(obj["outline_variant"].toString("#494648"));

    m_primary = QColor(obj["primary"].toString());
    m_primaryContainer = obj.contains("primary_container") ? QColor(obj["primary_container"].toString()) : m_primary.darker(200);
    m_onPrimary = QColor(obj["on_primary"].toString("#ffffff"));
    m_onPrimaryContainer = obj.contains("on_primary_container") ? QColor(obj["on_primary_container"].toString()) : m_primary.lighter(170);
    m_primaryHover = m_primary.lighter(115);

    m_secondary = QColor(obj["secondary"].toString("#cec3cd"));
    m_secondaryContainer = obj.contains("secondary_container") ? QColor(obj["secondary_container"].toString()) : m_secondary.darker(200);
    m_tertiary = QColor(obj["tertiary"].toString("#d4c0d7"));
    m_error = QColor(obj["error"].toString("#ffb4ab"));

    m_isDark = (m_background.lightnessF() < 0.5);
    return true;
}

bool ThemeManager::tryLoadWal() {
    QString path = QDir::homePath() + "/.cache/wal/colors.json";
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) return false;

    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (!doc.isObject()) return false;
    QJsonObject root = doc.object();
    if (!root.contains("colors")) return false;

    QJsonObject colors = root["colors"].toObject();
    QString bgStr = colors["color0"].toString();
    if (bgStr.isEmpty()) return false;
    // If color1 and color2 are empty, this is a corrupt/partial wal file
    if (colors["color1"].toString().isEmpty() && colors["color2"].toString().isEmpty()) return false;

    m_background = QColor(bgStr);
    m_surface = m_background.lighter(115);
    QString fgStr = colors["color15"].toString();
    m_onSurface = fgStr.isEmpty() ? QColor("#e2e2e2") : QColor(fgStr);
    m_onSurfaceVariant = m_onSurface.darker(130);

    QString accentStr = colors["color10"].toString();
    if (accentStr.isEmpty()) accentStr = colors["color3"].toString();
    if (accentStr.isEmpty()) accentStr = colors["color1"].toString();
    if (accentStr.isEmpty()) accentStr = "#ffb3ae";

    m_primary = QColor(accentStr);
    m_primaryHover = m_primary.lighter(115);
    m_onPrimary = m_primary.lightnessF() > 0.6 ? QColor("#131313") : QColor("#ffffff");

    QString secStr = colors["color5"].toString();
    if (secStr.isEmpty()) secStr = colors["color13"].toString();
    m_secondary = secStr.isEmpty() ? m_primary.darker(120) : QColor(secStr);

    QString outStr = colors["color7"].toString();
    m_outline = outStr.isEmpty() ? QColor("#353535") : QColor(outStr);

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
    m_surface = m_background.lighter(125);
    m_surfaceContainerLowest = m_background;
    m_surfaceContainerLow = m_background.lighter(115);
    m_surfaceContainer = m_background.lighter(130);
    m_surfaceContainerHigh = m_background.lighter(150);
    m_surfaceContainerHighest = m_background.lighter(175);

    m_onSurface = QColor(special["foreground"].toString("#e2e2e2"));
    m_onSurfaceVariant = m_onSurface.darker(125);

    // Pick luminous purple/accent from illogical-impulse
    QString pStr = colors["color5"].toString();
    if (pStr.isEmpty()) pStr = colors["color6"].toString();
    if (pStr.isEmpty()) pStr = colors["color1"].toString();
    m_primary = QColor(pStr.isEmpty() ? "#9369AE" : pStr);
    m_primaryHover = m_primary.lighter(115);
    m_onPrimary = QColor("#ffffff");
    m_primaryContainer = m_primary.darker(180);
    m_onPrimaryContainer = m_primary.lighter(160);

    m_outline = QColor(colors["color8"].toString("#474747"));
    m_outlineVariant = m_outline.darker(130);

    m_secondary = QColor(colors["color4"].toString("#AE6F96"));
    m_secondaryContainer = m_secondary.darker(180);
    m_tertiary = QColor(colors["color3"].toString("#9C6697"));

    m_isDark = true;
    return true;
}

void ThemeManager::setPreset(const QString &preset) {
    const QString next = preset.isEmpty() ? QStringLiteral("auto") : preset;
    if (m_preset == next) return;
    m_preset = next;
    loadColors();
}

namespace {
struct ThemePresetDef {
    const char *id;
    const char *name;
    const char *bg;
    const char *surface;
    const char *onSurface;
    const char *onSurfaceVariant;
    const char *outline;
    const char *primary;
    const char *onPrimary;
    const char *secondary;
    const char *tertiary;
};

constexpr ThemePresetDef kPresets[] = {
    {"yandex_dark",          "Яндекс",              "#0a0c10", "#12151c", "#f0f2f8", "#9ea3b5", "#4b5166", "#fc3f1d", "#ffffff", "#e59b24", "#36c39f"},
    {"catppuccin-mocha",     "Catppuccin Mocha",    "#11111b", "#1e1e2e", "#cdd6f4", "#a6adc8", "#585b70", "#cba6f7", "#11111b", "#f5c2e7", "#94e2d5"},
    {"catppuccin-macchiato", "Catppuccin Macchiato","#181926", "#24273a", "#cad3f5", "#a5adcb", "#5b6078", "#c6a0f6", "#181926", "#f5bde6", "#8bd5ca"},
    {"catppuccin-frappe",    "Catppuccin Frappé",   "#232634", "#303446", "#c6d0f5", "#a5adce", "#626880", "#ca9ee6", "#232634", "#f4b8e4", "#81c8be"},
    {"rosepine",             "Rosé Pine",           "#191724", "#1f1d2e", "#e0def4", "#908caa", "#524f67", "#c4a7e7", "#191724", "#ebbcba", "#9ccfd8"},
    {"rosepine-moon",        "Rosé Pine Moon",      "#232136", "#2a273f", "#e0def4", "#908caa", "#56526e", "#c4a7e7", "#232136", "#ea9a97", "#9ccfd8"},
    {"gruvbox",              "Gruvbox",             "#1d2021", "#282828", "#ebdbb2", "#a89984", "#665c54", "#fe8019", "#1d2021", "#fabd2f", "#8ec07c"},
    {"nord",                 "Nord",                "#242933", "#2e3440", "#eceff4", "#d8dee9", "#4c566a", "#88c0d0", "#1b242e", "#81a1c1", "#a3be8c"},
    {"tokyonight",           "Tokyo Night",         "#16161e", "#1a1b26", "#c0caf5", "#a9b1d6", "#414868", "#7aa2f7", "#16161e", "#bb9af7", "#7dcfff"},
    {"tokyonight-storm",     "Tokyo Night Storm",   "#1f2335", "#24283b", "#c0caf5", "#a9b1d6", "#414868", "#7aa2f7", "#1f2335", "#bb9af7", "#7dcfff"},
    {"dracula",              "Dracula",             "#191a21", "#282a36", "#f8f8f2", "#c3c6d7", "#44475a", "#bd93f9", "#191a21", "#ff79c6", "#8be9fd"},
    {"everforest",           "Everforest",          "#232a2e", "#2d353b", "#d3c6aa", "#9da9a0", "#4f585e", "#a7c080", "#232a2e", "#83c092", "#dbbc7f"},
    {"kanagawa",             "Kanagawa",            "#16161d", "#1f1f28", "#dcd7ba", "#c8c093", "#54546d", "#7e9cd8", "#16161d", "#957fb8", "#98bb6c"},
    {"solarized",            "Solarized",           "#00212b", "#002b36", "#93a1a1", "#839496", "#586e75", "#268bd2", "#00212b", "#2aa198", "#b58900"},
    {"one",                  "One Dark",            "#1b1d23", "#282c34", "#abb2bf", "#9da5b4", "#4b5263", "#61afef", "#1b1d23", "#c678dd", "#98c379"},
    {"light_clean",          "Светлая",             "#f2f4f8", "#ffffff", "#171923", "#5c6274", "#b4bac8", "#e5391a", "#ffffff", "#d97706", "#0d9488"},
};
}

QVariantList ThemeManager::availablePresets() const {
    QVariantList list;
    QVariantMap autoItem;
    autoItem["id"] = QStringLiteral("auto");
    autoItem["name"] = QStringLiteral("Авто (система)");
    autoItem["window"] = m_preset == "auto" ? m_background.name() : QStringLiteral("#0a0c10");
    autoItem["page"] = m_preset == "auto" ? m_surface.name() : QStringLiteral("#12151c");
    autoItem["text"] = m_preset == "auto" ? m_onSurface.name() : QStringLiteral("#f0f2f8");
    autoItem["primary"] = m_preset == "auto" ? m_primary.name() : QStringLiteral("#fc3f1d");
    autoItem["secondary"] = m_preset == "auto" ? m_secondary.name() : QStringLiteral("#e59b24");
    autoItem["tertiary"] = m_preset == "auto" ? m_tertiary.name() : QStringLiteral("#36c39f");
    list.append(autoItem);

    for (const auto &p : kPresets) {
        QVariantMap item;
        item["id"] = QString::fromUtf8(p.id);
        item["name"] = QString::fromUtf8(p.name);
        item["window"] = QString::fromUtf8(p.bg);
        item["page"] = QString::fromUtf8(p.surface);
        item["text"] = QString::fromUtf8(p.onSurface);
        item["primary"] = QString::fromUtf8(p.primary);
        item["secondary"] = QString::fromUtf8(p.secondary);
        item["tertiary"] = QString::fromUtf8(p.tertiary);
        list.append(item);
    }
    return list;
}

bool ThemeManager::applyNamedPreset(const QString &preset) {
    for (const auto &p : kPresets) {
        if (preset == QLatin1String(p.id)) {
            m_background = QColor(p.bg);
            m_surface = QColor(p.surface);
            m_onSurface = QColor(p.onSurface);
            m_onSurfaceVariant = QColor(p.onSurfaceVariant);
            m_outline = QColor(p.outline);
            m_primary = QColor(p.primary);
            m_primaryHover = m_primary.lighter(115);
            m_onPrimary = QColor(p.onPrimary);
            m_secondary = QColor(p.secondary);
            m_tertiary = QColor(p.tertiary);
            m_error = QColor("#ff5449");
            deriveSurfaces();
            return true;
        }
    }
    return false;
}

void ThemeManager::loadColors() {
    // Не все загрузчики заполняют каждый цвет: начинаем с дефолтов, чтобы не оставалось
    // невалидных или устаревших значений от предыдущей темы.
    setDefaults();
    if (m_preset != "auto" && applyNamedPreset(m_preset)) {
        emit themeChanged();
        return;
    }
    bool ok = tryLoadQuickshell();
    if (!ok) ok = tryLoadPresets();
    if (!ok) ok = tryLoadNoctalia();
    if (!ok) ok = tryLoadWal();
    if (!ok) setDefaults();

    emit themeChanged();
}
