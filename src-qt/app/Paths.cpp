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

#include "app/Paths.h"

#include <QDesktopServices>
#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <QStandardPaths>
#include <QUrl>

namespace ymusic::paths {

namespace {

QString ensured(const QString &path)
{
    QDir().mkpath(path);
    return path;
}

} // namespace

QString dataDirectory()
{
    return ensured(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
                   + QStringLiteral("/ymusic"));
}

QString cacheDirectory()
{
    return ensured(QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)
                   + QStringLiteral("/ymusic"));
}

QString logDirectory()
{
    return ensured(dataDirectory() + QStringLiteral("/logs"));
}

QString logFilePath()
{
    return logDirectory() + QStringLiteral("/ymusic.log");
}

QString modsDirectory()
{
    return ensured(dataDirectory() + QStringLiteral("/mods"));
}

QString modDataDirectory()
{
    return ensured(dataDirectory() + QStringLiteral("/mod-data"));
}

bool openDirectory(const QString &path)
{
    if (path.trimmed().isEmpty()) {
        return false;
    }
    if (!QDir().mkpath(path)) {
        return false;
    }
    const QString absPath = QFileInfo(path).absoluteFilePath();

#ifdef Q_OS_LINUX
    // On Wayland/Hyprland/Arch setups, inode/directory is often hijacked by
    // kitty-open.desktop or broken portal handlers, making QDesktopServices::openUrl
    // return true while doing nothing. Check the configured default handler first.
    QString defaultHandler;
    if (!QStandardPaths::findExecutable(QStringLiteral("xdg-mime")).isEmpty()) {
        QProcess mimeProc;
        mimeProc.start(QStringLiteral("xdg-mime"),
                       {QStringLiteral("query"), QStringLiteral("default"), QStringLiteral("inode/directory")});
        if (mimeProc.waitForFinished(500) && mimeProc.exitCode() == 0) {
            defaultHandler = QString::fromUtf8(mimeProc.readAllStandardOutput()).trimmed().toLower();
        }
    }

    const bool brokenHandler = defaultHandler.isEmpty()
        || defaultHandler.contains(QLatin1StringView("kitty"))
        || defaultHandler.contains(QLatin1StringView("alacritty"))
        || defaultHandler.contains(QLatin1StringView("foot"))
        || defaultHandler.contains(QLatin1StringView("wezterm"))
        || defaultHandler.contains(QLatin1StringView("ghostty"));

    if (!brokenHandler) {
        const QString xdgOpen = QStandardPaths::findExecutable(QStringLiteral("xdg-open"));
        if (!xdgOpen.isEmpty() && QProcess::startDetached(xdgOpen, {absPath})) {
            return true;
        }
    }

    const QString desktop = (qEnvironmentVariable("XDG_CURRENT_DESKTOP") + u' '
                             + qEnvironmentVariable("QT_QPA_PLATFORMTHEME")).toLower();
    QStringList managers;
    if (desktop.contains(QLatin1StringView("gnome"))) {
        managers = {QStringLiteral("nautilus"), QStringLiteral("dolphin"), QStringLiteral("thunar"),
                    QStringLiteral("nemo"), QStringLiteral("pcmanfm-qt"), QStringLiteral("pcmanfm"), QStringLiteral("caja")};
    } else if (desktop.contains(QLatin1StringView("xfce"))) {
        managers = {QStringLiteral("thunar"), QStringLiteral("dolphin"), QStringLiteral("nautilus"),
                    QStringLiteral("nemo"), QStringLiteral("pcmanfm-qt"), QStringLiteral("pcmanfm"), QStringLiteral("caja")};
    } else {
        managers = {QStringLiteral("dolphin"), QStringLiteral("nautilus"), QStringLiteral("thunar"),
                    QStringLiteral("nemo"), QStringLiteral("pcmanfm-qt"), QStringLiteral("pcmanfm"), QStringLiteral("caja")};
    }

    for (const QString &candidate : managers) {
        const QString exe = QStandardPaths::findExecutable(candidate);
        if (!exe.isEmpty() && QProcess::startDetached(exe, {absPath})) {
            return true;
        }
    }
#endif

    return QDesktopServices::openUrl(QUrl::fromLocalFile(absPath));
}

} // namespace ymusic::paths
