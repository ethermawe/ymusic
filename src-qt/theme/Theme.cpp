/*
 * Swiftify, a spotify player for desktop
 * Copyright (C) 2026  shred0s
 * Modified for ymusic (2026).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#include "theme/Theme.h"

#include "AppSettings.h"
#include "app/Fonts.h"
#include "artwork/ArtworkPalette.h"
#include "cpp/cam/hct.h"
#include "cpp/scheme/scheme_content.h"
#include "cpp/scheme/scheme_tonal_spot.h"
#include "theme/ColorMath.h"

#include <QAbstractNativeEventFilter>
#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QEvent>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLoggingCategory>
#include <QPalette>
#include <QQmlEngine>
#include <QStandardPaths>
#include <QStyleHints>
#include <QUrl>

#ifdef Q_OS_WIN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

#include <functional>
#include <iterator>

namespace ymusic {

Q_LOGGING_CATEGORY(lcTheme, "ymusic.theme")

namespace {

Theme *s_instance = nullptr;

bool systemPrefersLight()
{
    return QGuiApplication::styleHints()->colorScheme() == Qt::ColorScheme::Light;
}

QString expandedPath(QString path)
{
    if (QUrl(path).isLocalFile()) path = QUrl(path).toLocalFile();
    if (path == QLatin1StringView("~")) path = QDir::homePath();
    if (path.startsWith(QLatin1StringView("~/"))) path.replace(0, 1, QDir::homePath());
    return QDir::cleanPath(path);
}

QString xdgDirectory(const char *variable, const QString &fallback)
{
    const QString path = qEnvironmentVariable(variable);
    return path.isEmpty() || QDir::isRelativePath(path) ? QDir::homePath() + fallback : QDir::cleanPath(path);
}

QStringList schemeSearchRoots()
{
    const QString config = xdgDirectory("XDG_CONFIG_HOME", QStringLiteral("/.config"));
    const QString cache = xdgDirectory("XDG_CACHE_HOME", QStringLiteral("/.cache"));
    const QString state = xdgDirectory("XDG_STATE_HOME", QStringLiteral("/.local/state"));
    QStringList roots;
#ifndef Q_OS_MACOS
    roots.append(state + QStringLiteral("/quickshell/user/generated"));
#endif
    roots.append(config + QStringLiteral("/matugen"));
    roots.append(cache + QStringLiteral("/matugen"));
    roots.append(state + QStringLiteral("/matugen"));
    for (const QString &base : {QStringLiteral("/.config"), QStringLiteral("/.cache"), QStringLiteral("/.local/state")}) {
        roots.append(QDir::homePath() + base + QStringLiteral("/matugen"));
    }
    roots.removeDuplicates();
    return roots;
}

QStringList shellSchemeFiles()
{
    const QString config = xdgDirectory("XDG_CONFIG_HOME", QStringLiteral("/.config"));
    const QString cache = xdgDirectory("XDG_CACHE_HOME", QStringLiteral("/.cache"));
    return {
        cache + QStringLiteral("/DankMaterialShell/dms-colors.json"),
        config + QStringLiteral("/presets/user/colors.json"),
        config + QStringLiteral("/noctalia/colors.json"),
        cache + QStringLiteral("/wal/colors.json"),
    };
}

QRgb parseRgb(const QJsonObject &obj, const char *key, QRgb fallback)
{
    const QString str = obj.value(QLatin1StringView(key)).toString();
    if (str.isEmpty()) return fallback;
    const QColor c(str);
    return c.isValid() ? c.rgba() : fallback;
}

std::optional<MaterialScheme::Roles> readFallbackShellScheme(const QByteArray &data)
{
    const QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isObject()) return std::nullopt;
    const QJsonObject root = doc.object();

    // Noctalia colors.json
    if (root.contains(QLatin1StringView("mPrimary")) && root.contains(QLatin1StringView("mSurface"))) {
        const QColor surface(root.value(QLatin1StringView("mSurface")).toString());
        const bool dark = color::luminance709(surface) < 0.5;
        const QColor bg = surface.darker(120);
        const QColor raised = dark ? surface.lighter(120) : surface.darker(108);
        const QColor raisedMore = dark ? surface.lighter(140) : surface.darker(115);
        const themes::Variant v {
            bg.darker(115).rgba(),
            bg.rgba(),
            surface.rgba(),
            raised.rgba(),
            raisedMore.rgba(),
            parseRgb(root, "mOutline", 0xff474747),
            parseRgb(root, "mOnSurface", 0xffe2e2e2),
            parseRgb(root, "mOnSurfaceVariant", 0xffc6c6c6),
            parseRgb(root, "mOutline", 0xff777777),
            parseRgb(root, "mPrimary", Theme::kAccent),
            parseRgb(root, "mSecondary", 0xffe59b24),
            parseRgb(root, "mTertiary", 0xff36c39f),
            parseRgb(root, "mError", 0xffff5449),
        };
        return themes::roles(v, dark);
    }

    // Pywal / illogical-impulse preset JSON
    if (root.contains(QLatin1StringView("colors")) && root.value(QLatin1StringView("colors")).isObject()) {
        const QJsonObject colors = root.value(QLatin1StringView("colors")).toObject();
        const QJsonObject special = root.value(QLatin1StringView("special")).toObject();
        const QString bgHex = !special.value(QLatin1StringView("background")).toString().isEmpty()
            ? special.value(QLatin1StringView("background")).toString()
            : colors.value(QLatin1StringView("color0")).toString();
        const QColor bg(bgHex);
        if (!bg.isValid()) return std::nullopt;
        const bool dark = color::luminance709(bg) < 0.5;
        const QColor surface = dark ? bg.lighter(120) : bg.darker(106);
        const QColor raised = dark ? surface.lighter(125) : surface.darker(108);
        const QColor raisedMore = dark ? surface.lighter(145) : surface.darker(115);
        const QRgb fg = QColor(special.value(QLatin1StringView("foreground")).toString(
            colors.value(QLatin1StringView("color15")).toString(QStringLiteral("#e2e2e2")))).rgba();
        QRgb primary = parseRgb(colors, "color5", 0);
        if (!primary) primary = parseRgb(colors, "color10", 0);
        if (!primary) primary = parseRgb(colors, "color3", 0);
        if (!primary) primary = parseRgb(colors, "color1", Theme::kAccent);
        const QRgb secondary = parseRgb(colors, "color4", parseRgb(colors, "color13", 0xffe59b24));
        const QRgb tertiary = parseRgb(colors, "color3", parseRgb(colors, "color6", 0xff36c39f));
        const QRgb outline = parseRgb(colors, "color8", parseRgb(colors, "color7", 0xff4b5166));
        const themes::Variant v {
            bg.darker(110).rgba(),
            bg.rgba(),
            surface.rgba(),
            raised.rgba(),
            raisedMore.rgba(),
            outline,
            fg,
            color::mix(QColor::fromRgba(fg), bg, 0.72).rgba(),
            outline,
            primary,
            secondary,
            tertiary,
            0xffff5449,
        };
        return themes::roles(v, dark);
    }

    return std::nullopt;
}

std::optional<MaterialScheme::Roles> readScheme(const QString &path, bool dark)
{
    const QFileInfo info(path);
    if (!info.isFile() || info.size() > 4 * 1024 * 1024) return std::nullopt;
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) return std::nullopt;
    const QByteArray bytes = file.readAll();
    if (auto matugen = MaterialScheme::fromMatugenJson(bytes, dark)) {
        return matugen;
    }
    return readFallbackShellScheme(bytes);
}

QString existingAncestor(QString path)
{
    while (!QDir(path).exists()) {
        const QString parent = QFileInfo(path).absolutePath();
        if (parent == path) break;
        path = parent;
    }
    return path;
}

QStringList schemeFiles(const QStringList &roots, QStringList &watchedDirectories)
{
    QStringList candidates;
    std::function<void(const QString &, int)> scan = [&](const QString &path, int depth) {
        if (candidates.size() >= 512 || watchedDirectories.size() >= 64) return;
        const QDir directory(path);
        watchedDirectories.append(existingAncestor(path));
        watchedDirectories.removeDuplicates();
        if (!directory.exists()) return;
        const auto files = directory.entryInfoList({QStringLiteral("*.json")}, QDir::Files | QDir::Readable, QDir::Name | QDir::IgnoreCase);
        const QString colors = directory.filePath(QStringLiteral("colors.json"));
        if (QFileInfo::exists(colors)) candidates.append(colors);
        for (const QFileInfo &file : files) {
            if (candidates.size() >= 512) break;
            if (file.fileName() != QLatin1StringView("colors.json")) candidates.append(file.absoluteFilePath());
        }
        if (depth >= 2) return;
        for (const QFileInfo &child : directory.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::NoSymLinks, QDir::Name)) {
            const QString name = child.fileName().toLower();
            if (name == QLatin1StringView("templates") || name == QLatin1StringView("template")
                || name == QLatin1StringView("images") || name.startsWith(u'.')) continue;
            scan(child.absoluteFilePath(), depth + 1);
        }
    };
    for (const QString &root : roots) scan(root, 0);
    candidates.removeDuplicates();
    return candidates;
}

QString normalizedPreset(const QString &preset)
{
    if (preset.isEmpty() || preset == QLatin1StringView("auto") || preset == QLatin1StringView("system")) {
        return QStringLiteral("auto");
    }
    if (preset == QLatin1StringView("yandex_dark")) {
        return QStringLiteral("yandex");
    }
    if (preset == QLatin1StringView("light_clean")) {
        return QStringLiteral("default");
    }
    return preset;
}

#ifdef Q_OS_WIN
class WindowsThemeEventFilter final : public QAbstractNativeEventFilter {
public:
    explicit WindowsThemeEventFilter(std::function<void()> onChange)
        : m_onChange(std::move(onChange)) {}

    bool nativeEventFilter(const QByteArray &eventType, void *message, qintptr *) override
    {
        if (eventType != QByteArrayLiteral("windows_generic_MSG") || !message) {
            return false;
        }
        const auto *msg = static_cast<const MSG *>(message);
        if (msg->message == WM_DWMCOLORIZATIONCOLORCHANGED) {
            m_onChange();
        } else if (msg->message == WM_SETTINGCHANGE) {
            if (msg->wParam == SPI_SETDESKWALLPAPER) {
                m_onChange();
            } else if (msg->lParam) {
                const QString area = QString::fromWCharArray(reinterpret_cast<const wchar_t *>(msg->lParam));
                if (area == QLatin1StringView("ImmersiveColorSet")
                    || area == QLatin1StringView("WindowsThemeElement")) {
                    m_onChange();
                }
            }
        }
        return false;
    }

private:
    std::function<void()> m_onChange;
};

QStringList windowsWallpaperCandidates(QStringList &watchedDirectories)
{
    QStringList candidates;
    wchar_t pathBuf[1024] {};
    if (SystemParametersInfoW(SPI_GETDESKWALLPAPER, static_cast<UINT>(std::size(pathBuf)), pathBuf, 0)) {
        const QString spiPath = QDir::cleanPath(QString::fromWCharArray(pathBuf));
        if (!spiPath.isEmpty()) {
            const QFileInfo info(spiPath);
            if (info.isFile()) {
                candidates.append(info.absoluteFilePath());
            }
            watchedDirectories.append(existingAncestor(info.absolutePath()));
        }
    }

    const QString appData = qEnvironmentVariable("APPDATA");
    if (!appData.isEmpty()) {
        const QString themesDir = QDir::cleanPath(appData + QStringLiteral("/Microsoft/Windows/Themes"));
        watchedDirectories.append(existingAncestor(themesDir));
        const QString transcoded = themesDir + QStringLiteral("/TranscodedWallpaper");
        if (QFileInfo::exists(transcoded)) {
            candidates.append(QFileInfo(transcoded).absoluteFilePath());
        }
    }
    candidates.removeDuplicates();
    watchedDirectories.removeDuplicates();
    return candidates;
}

std::optional<QColor> extractWallpaperSeedCached(const QString &path)
{
    struct Cache {
        QString path;
        qint64 modifiedMs = -1;
        qint64 size = -1;
        QColor seed;
    };
    static Cache cache;

    const QFileInfo info(path);
    if (!info.isFile() || info.size() <= 0 || info.size() > 32 * 1024 * 1024) {
        return std::nullopt;
    }
    const qint64 modifiedMs = info.lastModified().toMSecsSinceEpoch();
    const qint64 size = info.size();
    if (cache.path == info.absoluteFilePath() && cache.modifiedMs == modifiedMs
        && cache.size == size && cache.seed.isValid()) {
        return cache.seed;
    }

    QFile file(info.absoluteFilePath());
    if (!file.open(QIODevice::ReadOnly)) {
        return std::nullopt;
    }
    const auto seed = Theme::wallpaperSeedFromBytes(file.readAll());
    if (seed && seed->isValid()) {
        cache = {info.absoluteFilePath(), modifiedMs, size, *seed};
        return seed;
    }
    return std::nullopt;
}

std::optional<MaterialScheme::Roles> readWindowsWallpaperRoles(const QString &path, bool dark)
{
    if (const auto seed = extractWallpaperSeedCached(path)) {
        return Theme::rolesFromSeed(*seed, dark, false);
    }
    const QColor accent = QGuiApplication::palette().color(QPalette::Accent);
    if (accent.isValid() && accent.alpha() > 0) {
        return Theme::rolesFromSeed(accent, dark, false);
    }
    return std::nullopt;
}
#endif

} // namespace

Theme::Theme(AppSettings *settings, QObject *parent)
    : QObject(parent)
    , m_settings(settings)
    , m_colors(new MaterialScheme(this))
{
    if (!s_instance) {
        s_instance = this;
    }

    m_reloadDebounce.setSingleShot(true);
    m_reloadDebounce.setInterval(120);
    connect(&m_reloadDebounce, &QTimer::timeout, this, &Theme::reload);
    const auto scheduleReload = [this] { m_reloadDebounce.start(); };
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, scheduleReload);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, scheduleReload);
    connect(QGuiApplication::styleHints(), &QStyleHints::colorSchemeChanged, this, scheduleReload);
    if (auto *coreApp = QCoreApplication::instance()) {
        coreApp->installEventFilter(this);
#ifdef Q_OS_WIN
        m_nativeFilter = new WindowsThemeEventFilter(scheduleReload);
        coreApp->installNativeEventFilter(m_nativeFilter);
#endif
    }
    if (m_settings) {
        connect(m_settings, &AppSettings::themeChanged, this, scheduleReload);
    }

    reload();
}

Theme::~Theme()
{
#ifdef Q_OS_WIN
    if (m_nativeFilter) {
        if (auto *coreApp = QCoreApplication::instance()) {
            coreApp->removeNativeEventFilter(m_nativeFilter);
        }
        delete m_nativeFilter;
        m_nativeFilter = nullptr;
    }
#endif
    if (s_instance == this) {
        s_instance = nullptr;
    }
}

bool Theme::eventFilter(QObject *watched, QEvent *event)
{
    if (watched == QCoreApplication::instance() && event->type() == QEvent::ApplicationPaletteChange) {
        m_reloadDebounce.start();
    }
    return QObject::eventFilter(watched, event);
}

Theme *Theme::instance()
{
    return s_instance;
}

Theme *Theme::create(QQmlEngine *, QJSEngine *)
{
    QJSEngine::setObjectOwnership(s_instance, QJSEngine::CppOwnership);
    return s_instance;
}

void Theme::resolveSystemScheme(bool dark)
{
    m_schemeDirectories.clear();
    m_schemeFiles.clear();
    m_systemRoles.reset();
    const QString configured = m_settings ? m_settings->matugenColorsPath() : QString();
    if (!configured.isEmpty()) {
        m_systemSchemePath = QFileInfo(expandedPath(configured)).absoluteFilePath();
        m_systemRoles = readScheme(m_systemSchemePath, dark);
        m_schemeDirectories.append(existingAncestor(QFileInfo(m_systemSchemePath).absolutePath()));
        return;
    }
    m_systemSchemePath.clear();
    QStringList candidates = schemeFiles(schemeSearchRoots(), m_schemeDirectories);
    qsizetype shellIndex = 0;
    while (shellIndex < candidates.size() && candidates.at(shellIndex).contains(QLatin1StringView("/quickshell/user/generated/"))) {
        ++shellIndex;
    }
    for (const QString &path : shellSchemeFiles()) {
        if (QFileInfo::exists(path)) {
            candidates.insert(shellIndex++, path);
            m_schemeFiles.append(path);
        } else {
            m_schemeDirectories.append(existingAncestor(QFileInfo(path).absolutePath()));
        }
    }
    m_schemeDirectories.removeDuplicates();
    for (const QString &path : candidates) {
        if (const auto roles = readScheme(path, dark)) {
            m_systemSchemePath = path;
            m_systemRoles = roles;
            return;
        }
    }
#ifdef Q_OS_WIN
    for (const QString &wallpaperPath : windowsWallpaperCandidates(m_schemeDirectories)) {
        if (const auto roles = readWindowsWallpaperRoles(wallpaperPath, dark)) {
            m_systemSchemePath = wallpaperPath;
            m_schemeFiles.append(wallpaperPath);
            m_systemRoles = roles;
            return;
        }
    }
    const QColor accent = QGuiApplication::palette().color(QPalette::Accent);
    if (accent.isValid() && accent.alpha() > 0) {
        m_systemSchemePath = QStringLiteral("Windows Accent");
        m_systemRoles = rolesFromSeed(accent, dark, false);
    }
#endif
}

void Theme::refreshSystemScheme()
{
    reload();
}

QString Theme::fontFamily() const
{
    return fonts::interfaceFamily();
}

QString Theme::monoFontFamily() const
{
    return fonts::fixedFamily();
}

MaterialScheme::Roles Theme::rolesFromSeed(QColor seed, bool dark, bool fidelity)
{
    using namespace material_color_utilities;
    const Hct hct(seed.rgba() | 0xff000000u);
    if (fidelity) {
        return MaterialScheme::fromDynamicScheme(SchemeContent(hct, dark, 0.0));
    }
    return MaterialScheme::fromDynamicScheme(SchemeTonalSpot(hct, dark, 0.0));
}

std::optional<QColor> Theme::wallpaperSeedFromBytes(const QByteArray &encoded)
{
    const auto extracted = palette::extract(encoded);
    if (!extracted || extracted->colors.isEmpty()) {
        return std::nullopt;
    }
    return extracted->colors.first();
}

QColor Theme::mix(const QColor &a, const QColor &b, qreal amountOfA)
{
    return color::mix(a, b, amountOfA);
}

QColor Theme::withAlpha(const QColor &color, qreal alpha)
{
    return color::withAlpha(color, alpha);
}

void Theme::reload()
{
    const bool wasUsingSystem = m_usingSystemScheme;
    const bool hadDark = m_colors->dark();
    const QString previousPath = m_systemSchemePath;
    const auto previousRoles = m_colors->roles();

    const QString rawPreset = m_settings ? m_settings->themePreset() : QStringLiteral("auto");
    const QString preset = normalizedPreset(rawPreset);

    resolveSystemScheme(wantsDark());
    watchSchemeFile();

    if (preset == QLatin1StringView("auto") && m_systemRoles) {
        const QColor background = (*m_systemRoles)[static_cast<std::size_t>(MaterialScheme::Role::Background)];
        m_usingSystemScheme = true;
        m_colors->setRoles(*m_systemRoles, color::luminance709(background) < 0.5);
        if (!wasUsingSystem || hadDark != m_colors->dark() || previousPath != m_systemSchemePath || previousRoles != m_colors->roles()) {
            emit schemeChanged();
        }
        return;
    }

    const bool dark = rawPreset == QLatin1StringView("light_clean") ? false : wantsDark();
    m_usingSystemScheme = false;
    if (preset == QLatin1StringView("builtin") || preset == QLatin1StringView("swiftify")) {
        m_colors->setRoles(rolesFromSeed(QColor::fromRgba(kRoseAccent), dark, true), dark);
    } else if (const themes::Family *family = themes::find(preset)) {
        m_colors->setRoles(themes::roles(dark ? family->dark : family->light, dark), dark);
    } else if (const themes::Family *yandex = themes::find(QStringLiteral("yandex"))) {
        m_colors->setRoles(themes::roles(dark ? yandex->dark : yandex->light, dark), dark);
    } else {
        m_colors->setRoles(rolesFromSeed(QColor::fromRgba(kAccent), dark, true), dark);
    }

    if (wasUsingSystem || hadDark != dark || previousPath != m_systemSchemePath || previousRoles != m_colors->roles()) {
        emit schemeChanged();
    }
}

bool Theme::wantsDark() const
{
    const QString mode = m_settings ? m_settings->themeMode() : QStringLiteral("auto");
    if (mode == QLatin1StringView("light")) {
        return false;
    }
    if (mode == QLatin1StringView("dark")) {
        return true;
    }
    // Preserve dark default when desktop does not explicitly prefer light or no mode set.
    return !systemPrefersLight();
}

QList<ThemeOption> Theme::themeOptions(bool dark) const
{
    using Role = MaterialScheme::Role;
    const auto option = [](const QString &id, const QString &name, const MaterialScheme::Roles &roles) {
        const auto role = [&roles](Role which) { return roles[static_cast<std::size_t>(which)]; };
        return ThemeOption {id, name, role(Role::Background), role(Role::SurfaceContainerLow), role(Role::OnSurface),
                            role(Role::Primary), role(Role::Secondary), role(Role::Tertiary)};
    };
    QList<ThemeOption> options;
    std::optional<MaterialScheme::Roles> desktop = readScheme(systemSchemePath(), dark);
#ifdef Q_OS_WIN
    if (!desktop && !systemSchemePath().isEmpty()) {
        desktop = readWindowsWallpaperRoles(systemSchemePath(), dark);
    }
#endif
    const themes::Family *yandex = themes::find(QStringLiteral("yandex"));
    const MaterialScheme::Roles fallbackAuto = yandex
        ? themes::roles(dark ? yandex->dark : yandex->light, dark)
        : rolesFromSeed(QColor::fromRgba(kAccent), dark, true);
    options.append(option(QStringLiteral("auto"),
                          QStringLiteral("Авто (система)"),
                          desktop ? *desktop : fallbackAuto));
    options.append(option(QStringLiteral("builtin"),
                          QStringLiteral("Swiftify Rose"),
                          rolesFromSeed(QColor::fromRgba(kRoseAccent), dark, true)));
    for (const themes::Family &family : themes::families()) {
        options.append(option(family.id, family.name, themes::roles(dark ? family.dark : family.light, dark)));
    }
    return options;
}

void Theme::watchSchemeFile()
{
    const QStringList watched = m_watcher.files() + m_watcher.directories();
    if (!watched.isEmpty()) {
        m_watcher.removePaths(watched);
    }
    const QString preset = normalizedPreset(m_settings ? m_settings->themePreset() : QStringLiteral("auto"));
    if (preset != QLatin1StringView("auto")) {
        return;
    }
    m_watcher.addPaths(m_schemeDirectories);
    if (!m_schemeFiles.isEmpty()) {
        m_watcher.addPaths(m_schemeFiles);
    }
    if (!m_systemSchemePath.isEmpty()) {
        const QFileInfo info(m_systemSchemePath);
        if (info.exists()) {
            m_watcher.addPath(info.absoluteFilePath());
            if (info.canonicalFilePath() != info.absoluteFilePath()) m_watcher.addPath(info.canonicalFilePath());
        }
    }
}

} // namespace ymusic
