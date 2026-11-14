#pragma once

#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

#include <algorithm>

namespace ymusic {

enum class SleepFade { None, FinalSeconds, Entire };

inline SleepFade sleepFadeFromString(const QString &value)
{
    if (value == QLatin1StringView("none")) return SleepFade::None;
    if (value == QLatin1StringView("entire")) return SleepFade::Entire;
    return SleepFade::FinalSeconds;
}

inline QString sleepFadeName(SleepFade fade)
{
    switch (fade) {
    case SleepFade::None: return QStringLiteral("none");
    case SleepFade::Entire: return QStringLiteral("entire");
    case SleepFade::FinalSeconds: return QStringLiteral("finalSeconds");
    }
    return QStringLiteral("finalSeconds");
}

inline double sleepFadeLevel(SleepFade fade, double remainingSeconds, double durationSeconds)
{
    if (durationSeconds <= 0) {
        return 1;
    }
    switch (fade) {
    case SleepFade::None:
        return 1;
    case SleepFade::FinalSeconds: {
        const double window = std::min(10.0, durationSeconds);
        return remainingSeconds < window ? std::max(0.0, remainingSeconds / window) : 1;
    }
    case SleepFade::Entire:
        return std::clamp(remainingSeconds / durationSeconds, 0.0, 1.0);
    }
    return 1;
}

class ScrubSession : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool editing READ isEditing NOTIFY editingChanged FINAL)

public:
    using QObject::QObject;

    bool isEditing() const { return m_editing; }

    Q_INVOKABLE void begin(quint64 songInstanceId)
    {
        m_songId = songInstanceId;
        m_cancelled = songInstanceId == 0;
        setEditing(true);
    }

    Q_INVOKABLE bool acceptsChanges(quint64 songInstanceId) const
    {
        return m_editing && !m_cancelled && m_songId == songInstanceId;
    }

    Q_INVOKABLE void cancel() { m_cancelled = true; }

    Q_INVOKABLE double finish(quint64 songInstanceId, double position)
    {
        const double target = acceptsChanges(songInstanceId) ? position : -1;
        m_songId = 0;
        m_cancelled = false;
        setEditing(false);
        return target;
    }

signals:
    void editingChanged();

private:
    void setEditing(bool editing)
    {
        if (m_editing != editing) {
            m_editing = editing;
            emit editingChanged();
        }
    }

    bool m_editing = false;
    bool m_cancelled = false;
    quint64 m_songId = 0;
};

} // namespace ymusic
