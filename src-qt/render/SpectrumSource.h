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

#include <QElapsedTimer>
#include <QList>
#include <QObject>
#include <QTimer>
#include <QtQml/qqmlregistration.h>

#include <array>

class QQmlEngine;
class QJSEngine;
class YMusicBackend;

namespace ymusic {

/// Audio analyser's 48 FFT bands polled at 60 Hz while playing, plus the loading pulse while buffering.
class SpectrumSource : public QObject {
    Q_OBJECT
    QML_NAMED_ELEMENT(Spectrum)
    QML_SINGLETON

    Q_PROPERTY(bool loading READ isLoading NOTIFY loadingChanged FINAL)

public:
    static constexpr int kBands = 48;

    explicit SpectrumSource(YMusicBackend *backend, QObject *parent = nullptr);
    ~SpectrumSource() override;

    static SpectrumSource *instance();
    static SpectrumSource *create(QQmlEngine *, QJSEngine *);

    const QList<float> &levels() const { return m_levels; }
    bool isLoading() const { return m_loading; }
    float loadingPhase() const { return m_loadingPhase; }

    std::array<float, 5> energies() const;
    void publish(const float *levels, int count);

signals:
    void levelsChanged();
    void loadingChanged();

private:
    void updateActivity();
    void poll();
    void tickLoading();
    void clear();

    YMusicBackend *m_backend;
    QList<float> m_levels;
    QTimer m_pollTimer;
    QTimer m_loadingTimer;
    QElapsedTimer m_loadingClock;
    bool m_loading = false;
    float m_loadingPhase = 0;
};

} // namespace ymusic
