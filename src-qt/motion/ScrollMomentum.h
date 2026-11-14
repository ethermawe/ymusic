#pragma once

#include <QElapsedTimer>
#include <QList>
#include <QObject>
#include <QPointF>
#include <QPointer>
#include <QTimer>
#include <QWindow>

class QWheelEvent;

namespace ymusic {

/// Adds smooth kinetic momentum glide after touchpad ScrollEnd events on Wayland/Linux.
class ScrollMomentum : public QObject {
    Q_OBJECT

public:
    explicit ScrollMomentum(QObject *parent = nullptr);

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    struct Sample {
        quint64 timestamp;
        QPointF delta;
    };

    void track(QWindow *window, const QWheelEvent *event);
    void start(const QWheelEvent *end);
    void glide();
    void stop();
    void send(Qt::ScrollPhase phase, const QPoint &pixelDelta);

    QList<Sample> m_samples;
    QTimer m_timer;
    QElapsedTimer m_clock;
    qint64 m_lastTick = 0;
    QPointer<QWindow> m_window;
    QPointF m_position;
    QPointF m_globalPosition;
    Qt::KeyboardModifiers m_modifiers;
    bool m_inverted = false;
    quint64 m_timestamp = 0;
    QPointF m_velocity;
    QPointF m_remainder;
    bool m_gliding = false;
    bool m_sending = false;
};

} // namespace ymusic
