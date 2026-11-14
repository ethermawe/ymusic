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
