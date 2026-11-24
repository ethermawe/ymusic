#pragma once

#include <QMap>
#include <QString>
#include <QStringList>

namespace ymusic::mods {

constexpr int kSupportedApiVersion = 1;

struct ModManifest {
    QString id;
    QString name;
    QString version;
    QString author;
    QString description;
    QString minAppVersion;
    int apiVersion = 0;

    /// Canonical absolute directory containing manifest.json
    QString directory;
    /// Optional headless background QML entry (relative -> resolved canonical file)
    QString scriptEntry;
    /// Optional settings QML page (resolved canonical file)
    QString settingsEntry;
    /// Optional sidebar page metadata when "sidebar.page" slot is present
    QString sidebarTitle;
    QString sidebarSymbol;
    /// Optional settings chapter metadata when "settings.tab" slot is present
    QString settingsTabTitle;
    QString settingsTabSymbol;
    QString settingsTabShape;
    /// Optional immersive panel metadata when "immersive.panel" slot is present
    QString immersivePanelTitle;
    QString immersivePanelSymbol;

    QStringList permissions;
    /// slot name -> resolved canonical file path
    QMap<QString, QString> slotsMap;
    /// normalized relative qml path (e.g. "qml/player/FloatingPlayerBar.qml") -> resolved canonical file path
    QMap<QString, QString> overridesMap;

    bool valid = false;
    QString error;

    bool hasPermission(const QString &perm) const;
    bool allowsNetworkHost(const QString &host) const;
};

/// Resolves a relative path strictly inside modDirectory; returns empty string on traversal or missing file.
QString resolveModPath(const QString &modDirectory, const QString &relativePath, bool mustExist = true);

/// Parses and validates manifest.json inside modDirectory.
ModManifest parseManifest(const QString &modDirectory);

/// Validates mod identifier format: lowercase alphanumeric, '-' or '_', 2..48 chars.
bool isValidModId(const QString &id);

} // namespace ymusic::mods
