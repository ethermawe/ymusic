#pragma once

#include <QObject>
#include <QParallelAnimationGroup>
#include <QPointer>
#include <QQuickItem>
#include <QtQml/qqmlregistration.h>

namespace ymusic {

/// Attached property `Reveal.shown` that smoothly springs items into and out of visibility.
class RevealAttached : public QObject {
    Q_OBJECT
    QML_ANONYMOUS

    Q_PROPERTY(bool shown READ isShown WRITE setShown NOTIFY shownChanged FINAL)
    Q_PROPERTY(qreal scaleFrom READ scaleFrom WRITE setScaleFrom NOTIFY scaleFromChanged FINAL)
    Q_PROPERTY(int duration READ duration WRITE setDuration NOTIFY timingChanged FINAL)
    Q_PROPERTY(qreal overshoot READ overshoot WRITE setOvershoot NOTIFY timingChanged FINAL)

public:
    explicit RevealAttached(QObject *parent);

    bool isShown() const { return m_shown; }
    void setShown(bool shown);
    qreal scaleFrom() const { return m_scaleFrom; }
    void setScaleFrom(qreal scale);
    int duration() const { return m_duration; }
    void setDuration(int duration);
    qreal overshoot() const { return m_overshoot; }
    void setOvershoot(qreal overshoot);

signals:
    void shownChanged();
    void scaleFromChanged();
    void timingChanged();

private:
    void animate(bool shown);

    QPointer<QQuickItem> m_item;
    bool m_shown = true;
    bool m_settled = false;
    qreal m_scaleFrom = 0.85;
    int m_duration = 440;
    qreal m_overshoot = 2.2;
    QParallelAnimationGroup m_animation;
};

class Reveal : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Reveal is only an attached property.")
    QML_ATTACHED(RevealAttached)

public:
    static RevealAttached *qmlAttachedProperties(QObject *object) { return new RevealAttached(object); }
};

} // namespace ymusic
