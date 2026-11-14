#pragma once

#include <QElapsedTimer>
#include <QObject>
#include <QtQml/qqmlregistration.h>

namespace ymusic {

/// Shared 30 Hz ambient clock for continuously rotating shapes and squiggles.
class AmbientClock : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(qreal speed READ speed WRITE setSpeed NOTIFY speedChanged FINAL)
    Q_PROPERTY(qreal value READ value NOTIFY valueChanged FINAL)

public:
    explicit AmbientClock(QObject *parent = nullptr);
    ~AmbientClock() override;

    static AmbientClock *spin();

    qreal speed() const { return m_speed; }
    void setSpeed(qreal speed);
    qreal value() const { return m_value; }
    bool isTicking() const { return m_ticking; }

signals:
    void speedChanged();
    void valueChanged();

private:
    void accumulate();
    void tick();

    QElapsedTimer m_clock;
    qreal m_speed = 0;
    qreal m_value = 0;
    bool m_ticking = false;
};

} // namespace ymusic
