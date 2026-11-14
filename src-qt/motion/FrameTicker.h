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
