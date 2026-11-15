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

#pragma once

#include "theme/MaterialScheme.h"
#include "theme/Themes.h"

#include <QColor>
#include <QFileSystemWatcher>
#include <QObject>
#include <QTimer>
#include <QtQml/qqmlregistration.h>

class AppSettings;
class QQmlEngine;
class QJSEngine;

namespace ymusic {

class Theme : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(ymusic::MaterialScheme *colors READ colors CONSTANT FINAL)
    Q_PROPERTY(bool dark READ dark NOTIFY schemeChanged FINAL)
    Q_PROPERTY(bool usingSystemScheme READ usingSystemScheme NOTIFY schemeChanged FINAL)
    Q_PROPERTY(QString systemSchemePath READ systemSchemePath NOTIFY schemeChanged FINAL)
    Q_PROPERTY(QString fontFamily READ fontFamily CONSTANT FINAL)
    Q_PROPERTY(QString monoFontFamily READ monoFontFamily CONSTANT FINAL)

public:
    static constexpr QRgb kAccent = 0xfffc3f1d;
    static constexpr QRgb kRoseAccent = 0xffff3d8a;

    explicit Theme(AppSettings *settings, QObject *parent = nullptr);
    ~Theme() override;

    static Theme *instance();
    static Theme *create(QQmlEngine *, QJSEngine *);

    MaterialScheme *colors() const { return m_colors; }
    bool dark() const { return m_colors->dark(); }
    bool usingSystemScheme() const { return m_usingSystemScheme; }
    QString systemSchemePath() const { return m_systemSchemePath; }
    QString fontFamily() const;
    QString monoFontFamily() const;

    static MaterialScheme::Roles rolesFromSeed(QColor seed, bool dark, bool fidelity);

    Q_INVOKABLE QList<ymusic::ThemeOption> themeOptions(bool dark) const;
    Q_INVOKABLE void refreshSystemScheme();

    Q_INVOKABLE static QColor mix(const QColor &a, const QColor &b, qreal amountOfA);
    Q_INVOKABLE static QColor withAlpha(const QColor &color, qreal alpha);

signals:
    void schemeChanged();

private:
    void reload();
    void resolveSystemScheme(bool dark);
    void watchSchemeFile();
    bool wantsDark() const;

    AppSettings *m_settings;
    MaterialScheme *m_colors;
    QFileSystemWatcher m_watcher;
    QTimer m_reloadDebounce;
    bool m_usingSystemScheme = false;
    QString m_systemSchemePath;
    std::optional<MaterialScheme::Roles> m_systemRoles;
    QStringList m_schemeDirectories;
    QStringList m_schemeFiles;
};

} // namespace ymusic
