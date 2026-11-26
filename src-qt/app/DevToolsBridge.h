#pragma once

#include <QMutex>
#include <QObject>
#include <QPointer>
#include <QQuickItem>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

class QQmlEngine;

namespace ymusic {

class DevToolsBridge : public QObject {
    Q_OBJECT

    Q_PROPERTY(QVariantList logs READ logs NOTIFY logsChanged FINAL)
    Q_PROPERTY(QString qtVersion READ qtVersion CONSTANT FINAL)
    Q_PROPERTY(QString graphicsApi READ graphicsApi CONSTANT FINAL)
    Q_PROPERTY(double memoryRssMb READ memoryRssMb NOTIFY metricsChanged FINAL)
    Q_PROPERTY(double memoryPssMb READ memoryPssMb NOTIFY metricsChanged FINAL)

public:
    explicit DevToolsBridge(QObject *parent = nullptr);
    ~DevToolsBridge() override;

    static DevToolsBridge *instance();

    void attachEngine(QQmlEngine *engine);
    void pushQtLog(QtMsgType type, const QString &message);

    QVariantList logs() const;
    QString qtVersion() const;
    QString graphicsApi() const;
    double memoryRssMb() const { return m_rssMb; }
    double memoryPssMb() const { return m_pssMb; }

    Q_INVOKABLE void refreshMetrics();
    Q_INVOKABLE void clearLogs();
    Q_INVOKABLE void appendConsoleEntry(const QString &level,
                                        const QString &source,
                                        const QString &message);
    Q_INVOKABLE int countItems(QQuickItem *root) const;
    Q_INVOKABLE QQuickItem *pickItemAt(QQuickItem *root,
                                       qreal x,
                                       qreal y,
                                       QQuickItem *ignoreSubtree = nullptr) const;
    Q_INVOKABLE QVariantMap inspectItem(QQuickItem *item, QQuickItem *coordRoot = nullptr) const;
    Q_INVOKABLE QQuickItem *ancestorAt(QQuickItem *item, int stepsUp) const;
    Q_INVOKABLE QVariantList findModSlots(QQuickItem *root) const;
    Q_INVOKABLE void copyToClipboard(const QString &text) const;
    Q_INVOKABLE void collectGarbage();

signals:
    void logsChanged();
    void metricsChanged();

private:
    void appendLogInternal(const QString &level, const QString &source, const QString &message);

    QPointer<QQmlEngine> m_engine;
    mutable QMutex m_mutex;
    QVariantList m_logs;
    double m_rssMb = 0.0;
    double m_pssMb = 0.0;

    inline static DevToolsBridge *s_instance = nullptr;
};

} // namespace ymusic
