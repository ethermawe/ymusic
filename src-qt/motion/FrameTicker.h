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
#include <QObject>
#include <QSet>
#include <QTimer>

namespace ymusic {

/// Shared 30 Hz tick for continuous ambient animations.
class FrameTicker : public QObject {
    Q_OBJECT

public:
    static constexpr int kIntervalMs = 33;

    static FrameTicker *instance();

    void subscribe(QObject *subscriber);
    void unsubscribe(QObject *subscriber);
    bool isRunning() const { return m_timer.isActive(); }

signals:
    void tick();

private:
    explicit FrameTicker(QObject *parent = nullptr);
    void update();

    QTimer m_timer;
    QSet<QObject *> m_subscribers;
};

} // namespace ymusic
