#pragma once

#include <QList>
#include <QMap>
#include <QString>
#include <QStringList>

namespace ymusic::mods {

constexpr int kSupportedApiMajor = 1;
constexpr int kSupportedApiMinor = 0;
constexpr int kSupportedApiVersion = kSupportedApiMajor;

struct ModSlotItem {
    QString entryId; // unique across mods & multi-slot items (e.g. "my-mod" or "my-mod:stats")
    QString file;    // resolved canonical file path
    QString title;
    QString symbol;
    QString shape;
};

struct ModShortcutDef {
    QString id;
    QString sequence;
    QString description;
};

struct ModManifest {
    QString id;
    QString name;
    QString version;
    QString author;
    QString description;
    QString minAppVersion;
    QString apiVersion;

    /// Canonical absolute directory containing manifest.json
    QString directory;
    /// Optional headless background QML entry (resolved canonical file)
    QString scriptEntry;
    /// Optional modal settings QML page (resolved canonical file)
    QString settingsEntry;

    QStringList permissions;
    /// slot name -> list of contributed slot items (supports string, object, or array in manifest)
    QMap<QString, QList<ModSlotItem>> slotsMap;
    /// normalized relative qml path (e.g. "qml/player/FloatingPlayerBar.qml") -> resolved canonical file path
    QMap<QString, QString> overridesMap;
    /// optional declarative shortcuts registered automatically when mod loads
    QList<ModShortcutDef> shortcuts;

    bool valid = false;
    QString error;
    QStringList warnings;

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
