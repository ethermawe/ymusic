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

#include "motion/ScrollMomentum.h"

#include <QCoreApplication>
#include <QLoggingCategory>
#include <QWheelEvent>

#include <cmath>
#include <utility>

namespace ymusic {

namespace {

Q_LOGGING_CATEGORY(lcScroll, "ymusic.scroll", QtInfoMsg)

constexpr quint64 kSampleWindowMs = 80;
constexpr quint64 kRestMs = 50;
constexpr qreal kDecayMs = 325.0;
constexpr qreal kMinSpeed = 0.1;
constexpr qreal kRestSpeed = 0.02;
constexpr qreal kMaxSpeed = 8.0;
constexpr int kTickMs = 8;

qreal length(const QPointF &point)
{
    return std::hypot(point.x(), point.y());
}

} // namespace

ScrollMomentum::ScrollMomentum(QObject *parent)
    : QObject(parent)
{
    m_timer.setInterval(kTickMs);
    m_timer.setTimerType(Qt::PreciseTimer);
    connect(&m_timer, &QTimer::timeout, this, &ScrollMomentum::glide);
}

bool ScrollMomentum::eventFilter(QObject *watched, QEvent *event)
{
    if (m_sending || !watched->isWindowType()) {
        return false;
    }
    switch (event->type()) {
    case QEvent::Wheel: {
        auto *window = static_cast<QWindow *>(watched);
        const auto *wheel = static_cast<const QWheelEvent *>(event);
        qCDebug(lcScroll) << wheel->timestamp() << wheel->phase() << wheel->source() << wheel->pixelDelta()
                          << wheel->angleDelta() << wheel->device();
        if (wheel->phase() != Qt::ScrollEnd) {
            stop();
        }
        if (wheel->source() != Qt::MouseEventSynthesizedBySystem) {
            m_samples.clear();
            break;
        }
        switch (wheel->phase()) {
        case Qt::ScrollBegin:
            m_samples.clear();
            track(window, wheel);
            break;
        case Qt::ScrollUpdate:
            track(window, wheel);
            break;
        case Qt::ScrollEnd:
            if (window == m_window) {
                start(wheel);
            }
            break;
        default:
            break;
        }
        break;
    }
    case QEvent::MouseButtonPress:
    case QEvent::TouchBegin:
    case QEvent::KeyPress:
        stop();
        break;
    case QEvent::Hide:
    case QEvent::Close:
        if (watched == m_window) {
            stop();
        }
        break;
    default:
        break;
    }
    return false;
}

void ScrollMomentum::track(QWindow *window, const QWheelEvent *event)
{
    if (window != m_window) {
        m_samples.clear();
        m_window = window;
    }
    m_position = event->position();
    m_globalPosition = event->globalPosition();
    m_modifiers = event->modifiers();
    m_inverted = event->inverted();
    if (!event->pixelDelta().isNull()) {
        m_samples.append({event->timestamp(), QPointF(event->pixelDelta())});
    }
    while (!m_samples.isEmpty() && m_samples.constLast().timestamp - m_samples.constFirst().timestamp > kSampleWindowMs) {
        m_samples.removeFirst();
    }
}

void ScrollMomentum::start(const QWheelEvent *end)
{
    const QList<Sample> samples = std::exchange(m_samples, {});
    if (samples.size() < 2 || end->timestamp() - samples.constLast().timestamp > kRestMs) {
        return;
    }
    QPointF distance;
    for (qsizetype i = 1; i < samples.size(); ++i) {
        distance += samples.at(i).delta;
    }
    const qreal span = qMax<qreal>(samples.constLast().timestamp - samples.constFirst().timestamp, kTickMs);
    QPointF velocity = distance / span;
    const qreal speed = length(velocity);
    if (speed < kMinSpeed) {
        return;
    }
    if (speed > kMaxSpeed) {
        velocity *= kMaxSpeed / speed;
    }
    m_velocity = velocity;
    m_remainder = {};
    m_timestamp = end->timestamp();
    m_gliding = true;
    m_clock.start();
    m_lastTick = 0;
    m_timer.start();
}

void ScrollMomentum::glide()
{
    if (!m_window) {
        stop();
        return;
    }
    const qint64 now = m_clock.elapsed();
    const qreal elapsed = now - m_lastTick;
    if (elapsed <= 0) {
        return;
    }
    m_lastTick = now;
    const qreal decay = std::exp(-elapsed / kDecayMs);
    m_remainder += m_velocity * kDecayMs * (1.0 - decay);
    m_velocity *= decay;
    const QPoint step(qRound(m_remainder.x()), qRound(m_remainder.y()));
    m_remainder -= QPointF(step);
    if (!step.isNull()) {
        send(Qt::ScrollMomentum, step);
    }
    if (length(m_velocity) < kRestSpeed) {
        stop();
    }
}

void ScrollMomentum::stop()
{
    if (!m_gliding) {
        return;
    }
    m_gliding = false;
    m_timer.stop();
    if (m_window) {
        send(Qt::ScrollEnd, {});
    }
}

void ScrollMomentum::send(Qt::ScrollPhase phase, const QPoint &pixelDelta)
{
    QWheelEvent event(m_position, m_globalPosition, pixelDelta, QPoint(), Qt::NoButton, m_modifiers, phase,
                      m_inverted, Qt::MouseEventSynthesizedBySystem);
    event.setTimestamp(m_timestamp + quint64(qMax<qint64>(m_lastTick, 1)));
    m_sending = true;
    QCoreApplication::sendEvent(m_window, &event);
    m_sending = false;
}

} // namespace ymusic
