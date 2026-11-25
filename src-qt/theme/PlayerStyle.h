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

#include <QCache>
#include <QColor>
#include <QList>
#include <QObject>
#include <QUrl>
#include <QVariantAnimation>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;
class YMusicBackend;

namespace ymusic {

class ArtworkCache;
class Theme;
struct WeightedPalette;

class PlayerStyle : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QList<QColor> palette READ palette NOTIFY paletteChanged FINAL)
    Q_PROPERTY(QList<qreal> weights READ weights NOTIFY paletteChanged FINAL)
    Q_PROPERTY(QColor primary READ primary NOTIFY paletteChanged FINAL)
    Q_PROPERTY(QColor secondary READ secondary NOTIFY paletteChanged FINAL)
    Q_PROPERTY(ymusic::MaterialScheme *scheme READ scheme CONSTANT FINAL)
    Q_PROPERTY(ymusic::MaterialScheme *darkScheme READ darkScheme CONSTANT FINAL)

public:
    PlayerStyle(YMusicBackend *backend, Theme *theme, ArtworkCache *artwork, QObject *parent = nullptr);
    ~PlayerStyle() override;

    static PlayerStyle *instance();
    static PlayerStyle *create(QQmlEngine *, QJSEngine *);

    QList<QColor> palette() const { return m_palette; }
    QList<qreal> weights() const { return m_weights; }
    QColor primary() const { return m_palette.value(0); }
    QColor secondary() const { return m_palette.value(1); }
    MaterialScheme *scheme() const { return m_scheme; }
    MaterialScheme *darkScheme() const { return m_darkScheme; }

signals:
    void paletteChanged();

private:
    struct Target {
        QList<QColor> palette;
        QList<qreal> weights;
        MaterialScheme::Roles light;
        MaterialScheme::Roles dark;
    };

    void artworkChanged();
    void adoptFallback();
    Target themeTarget() const;
    void retarget(Target target);
    void step(qreal progress);
    static Target targetFor(const QList<QColor> &palette, const QList<qreal> &weights, bool dark);
    static Target targetFor(const WeightedPalette &palette, bool dark);

    YMusicBackend *m_backend;
    Theme *m_theme;
    ArtworkCache *m_artwork;
    MaterialScheme *m_scheme;
    MaterialScheme *m_darkScheme;
    QUrl m_artworkUrl;
    QCache<QUrl, Target> m_targets {128};
    Target m_fallback;
    bool m_onFallback = true;

    QList<QColor> m_palette;
    QList<qreal> m_weights;
    Target m_from;
    Target m_to;
    QVariantAnimation m_transition;
};

} // namespace ymusic
