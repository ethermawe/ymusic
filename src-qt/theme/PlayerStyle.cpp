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

#include "theme/PlayerStyle.h"

#include "YMusicBackend.h"
#include "artwork/ArtworkCache.h"
#include "artwork/ArtworkPalette.h"
#include "theme/ColorMath.h"
#include "theme/Theme.h"

#include <QQmlEngine>
#include <QtConcurrent>

#include <algorithm>
#include <utility>

namespace ymusic {

namespace {

PlayerStyle *s_instance = nullptr;

} // namespace

PlayerStyle::PlayerStyle(YMusicBackend *backend, Theme *theme, ArtworkCache *artwork, QObject *parent)
    : QObject(parent)
    , m_backend(backend)
    , m_theme(theme)
    , m_artwork(artwork)
    , m_scheme(new MaterialScheme(this))
    , m_darkScheme(new MaterialScheme(this))
{
    if (!s_instance) {
        s_instance = this;
    }
    m_transition.setDuration(600);
    m_transition.setStartValue(0.0);
    m_transition.setEndValue(1.0);
    m_transition.setEasingCurve(QEasingCurve::InOutQuad);
    connect(&m_transition, &QVariantAnimation::valueChanged, this, [this](const QVariant &value) { step(value.toReal()); });

    m_fallback = themeTarget();
    m_to = m_fallback;
    m_from = m_to;
    step(1.0);

    if (m_backend) {
        connect(m_backend, &YMusicBackend::nowPlayingChanged, this, &PlayerStyle::artworkChanged);
    }
    connect(m_theme->colors(), &MaterialScheme::changed, this, [this] {
        const bool dark = m_theme->dark();
        m_targets.clear();
        m_fallback = themeTarget();
        m_to = m_onFallback ? m_fallback : targetFor(m_to.palette, m_to.weights, dark);
        m_from = m_to;
        step(1.0);
    });
}

PlayerStyle::~PlayerStyle()
{
    if (s_instance == this) {
        s_instance = nullptr;
    }
}

PlayerStyle *PlayerStyle::instance()
{
    return s_instance;
}

PlayerStyle *PlayerStyle::create(QQmlEngine *, QJSEngine *)
{
    QJSEngine::setObjectOwnership(s_instance, QJSEngine::CppOwnership);
    return s_instance;
}

PlayerStyle::Target PlayerStyle::targetFor(const QList<QColor> &palette, const QList<qreal> &weights, bool dark)
{
    const QColor seed = palette.value(0, QColor::fromRgba(Theme::kAccent));
    return {palette, weights, Theme::rolesFromSeed(seed, dark, true), Theme::rolesFromSeed(seed, true, true)};
}

PlayerStyle::Target PlayerStyle::targetFor(const WeightedPalette &palette, bool dark)
{
    QList<qreal> weights;
    for (double weight : palette.weights) {
        weights.append(weight);
    }
    return targetFor(palette.colors, weights, dark);
}

void PlayerStyle::artworkChanged()
{
    const QUrl url = (m_backend && m_backend->hasTrack() && m_backend->hasCover())
        ? QUrl(m_backend->nowCover())
        : QUrl();
    if (url == m_artworkUrl) {
        return;
    }
    m_artworkUrl = url;
    if (url.isEmpty() || !m_artwork) {
        adoptFallback();
        return;
    }
    if (const Target *cached = m_targets.object(url)) {
        m_onFallback = false;
        retarget(*cached);
        return;
    }
    m_artwork->bytes(url, [this, url](const QByteArray &data) {
        if (url != m_artworkUrl) {
            return;
        }
        if (data.isEmpty()) {
            adoptFallback();
            return;
        }
        const bool dark = m_theme->dark();
        QtConcurrent::run([data, dark]() -> std::optional<Target> {
            const std::optional<WeightedPalette> palette = palette::extract(data);
            if (!palette) {
                return std::nullopt;
            }
            return targetFor(*palette, dark);
        }).then(this, [this, url, dark](const std::optional<Target> &worked) {
            if (!worked) {
                if (url == m_artworkUrl) {
                    adoptFallback();
                }
                return;
            }
            const Target target = dark == m_theme->dark() ? *worked
                                                          : targetFor(worked->palette, worked->weights, m_theme->dark());
            m_targets.insert(url, new Target(target));
            if (url == m_artworkUrl) {
                m_onFallback = false;
                retarget(target);
            }
        });
    });
}

void PlayerStyle::adoptFallback()
{
    m_onFallback = true;
    retarget(m_fallback);
}

PlayerStyle::Target PlayerStyle::themeTarget() const
{
    using Role = MaterialScheme::Role;
    const MaterialScheme::Roles &roles = m_theme->colors()->roles();
    const bool dark = m_theme->dark();
    const MaterialScheme::Roles darkRoles = dark ? roles : Theme::rolesFromSeed(roles[std::size_t(Role::Primary)], true, false);
    const auto colour = [&](Role role) { return darkRoles[std::size_t(role)]; };
    Target target;
    target.palette = {colour(Role::Primary), colour(Role::Tertiary), colour(Role::Secondary),
                      colour(Role::PrimaryContainer), colour(Role::TertiaryContainer)};
    target.weights = {0.5, 0.25, 0.15, 0.06, 0.04};
    target.light = roles;
    target.dark = darkRoles;
    return target;
}

void PlayerStyle::retarget(Target target)
{
    m_from = {m_palette, m_weights, m_scheme->roles(), m_darkScheme->roles()};
    m_to = std::move(target);
    m_transition.stop();
    m_transition.setDuration(600);
    m_transition.start();
}

void PlayerStyle::step(qreal progress)
{
    QList<QColor> palette;
    QList<qreal> weights;
    for (qsizetype index = 0; index < m_to.palette.size(); ++index) {
        const QColor from = m_from.palette.value(index, m_to.palette.at(index));
        palette.append(color::mix(m_to.palette.at(index), from, progress));
        weights.append(m_from.weights.value(index, 0) * (1 - progress) + m_to.weights.value(index, 0) * progress);
    }
    m_palette = palette;
    m_weights = weights;
    m_scheme->setRoles(MaterialScheme::interpolate(m_from.light, m_to.light, progress), m_theme->dark());
    m_darkScheme->setRoles(MaterialScheme::interpolate(m_from.dark, m_to.dark, progress), true);
    emit paletteChanged();
}

} // namespace ymusic
