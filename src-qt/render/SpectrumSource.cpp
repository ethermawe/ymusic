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

#include "render/SpectrumSource.h"

#include "YMusicBackend.h"

#include <QQmlEngine>

#include <algorithm>
#include <array>
#include <cmath>

namespace ymusic {

namespace {
SpectrumSource *s_instance = nullptr;
constexpr double kLoadingCycleSeconds = 1.6;
} // namespace

SpectrumSource::SpectrumSource(YMusicBackend *backend, QObject *parent)
    : QObject(parent)
    , m_backend(backend)
    , m_levels(kBands, 0.0f)
{
    if (!s_instance) {
        s_instance = this;
    }
    m_pollTimer.setInterval(16);
    m_pollTimer.setTimerType(Qt::PreciseTimer);
    connect(&m_pollTimer, &QTimer::timeout, this, &SpectrumSource::poll);
    m_loadingTimer.setInterval(16);
    connect(&m_loadingTimer, &QTimer::timeout, this, &SpectrumSource::tickLoading);

    if (m_backend) {
        connect(m_backend, &YMusicBackend::playbackStateChanged, this, &SpectrumSource::updateActivity);
    }
    updateActivity();
}

SpectrumSource::~SpectrumSource()
{
    if (s_instance == this) {
        s_instance = nullptr;
    }
}

SpectrumSource *SpectrumSource::instance()
{
    return s_instance;
}

SpectrumSource *SpectrumSource::create(QQmlEngine *, QJSEngine *)
{
    QJSEngine::setObjectOwnership(s_instance, QJSEngine::CppOwnership);
    return s_instance;
}

void SpectrumSource::updateActivity()
{
    const bool active = m_backend && m_backend->playing();
    const bool buffering = m_backend && m_backend->buffering();

    if (active) {
        if (!m_pollTimer.isActive()) {
            m_pollTimer.start();
        }
    } else {
        m_pollTimer.stop();
        clear();
    }

    if (buffering != m_loading) {
        m_loading = buffering;
        m_loadingPhase = 0;
        m_loadingClock.restart();
        emit loadingChanged();
    }
    if (m_loading) {
        if (!m_loadingTimer.isActive()) {
            m_loadingClock.restart();
            m_loadingTimer.start();
        }
    } else {
        m_loadingTimer.stop();
    }
}

void SpectrumSource::poll()
{
    if (!m_backend) {
        return;
    }
    float next[kBands];
    const int count = m_backend->spectrumLevels(next, kBands);
    publish(next, count);
}

void SpectrumSource::publish(const float *next, int count)
{
    bool changed = false;
    for (int band = 0; band < kBands; ++band) {
        const float raw = band < count ? next[band] : 0.0f;
        const float level = std::isfinite(raw) ? std::clamp(raw, 0.0f, 1.0f) : 0.0f;
        if (level != m_levels[band]) {
            m_levels[band] = level;
            changed = true;
        }
    }
    if (changed) {
        emit levelsChanged();
    }
}

void SpectrumSource::tickLoading()
{
    m_loadingPhase = float(std::fmod(m_loadingClock.elapsed() / 1000.0, kLoadingCycleSeconds) / kLoadingCycleSeconds);
    emit levelsChanged();
}

void SpectrumSource::clear()
{
    if (std::none_of(m_levels.begin(), m_levels.end(), [](float level) { return level > 0; })) {
        return;
    }
    m_levels.fill(0.0f);
    emit levelsChanged();
}

std::array<float, 5> SpectrumSource::energies() const
{
    const auto mean = [this](int from, int to) {
        float sum = 0;
        for (int band = from; band < to; ++band) {
            sum += m_levels[band];
        }
        return sum / float(to - from);
    };
    return {
        mean(0, 6),
        mean(6, 14),
        mean(14, 24),
        mean(24, 38),
        mean(38, kBands),
    };
}

} // namespace ymusic
