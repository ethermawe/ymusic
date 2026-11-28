#pragma once

#include <QPointer>
#include <QQmlContext>
#include <QQuickItem>
#include <QString>
#include <QUrl>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

namespace ymusic::mods {

/// Hosts a single mod QML entry inside that mod's isolated QQmlEngine and child QQmlContext.
/// Exposes ONLY `modApi` and `slotContext` to the mod component.
class ModSlotView : public QQuickItem {
    Q_OBJECT
    QML_NAMED_ELEMENT(ModSlotItem)

    Q_PROPERTY(QString modId READ modId WRITE setModId NOTIFY modIdChanged FINAL)
    Q_PROPERTY(QString slotName READ slotName WRITE setSlotName NOTIFY slotNameChanged FINAL)
    Q_PROPERTY(QUrl sourceUrl READ sourceUrl WRITE setSourceUrl NOTIFY sourceUrlChanged FINAL)
    Q_PROPERTY(QVariantMap slotContext READ slotContext WRITE setSlotContext NOTIFY slotContextChanged FINAL)
    Q_PROPERTY(int reloadRevision READ reloadRevision WRITE setReloadRevision NOTIFY reloadRevisionChanged FINAL)
    Q_PROPERTY(bool fillContent READ fillContent WRITE setFillContent NOTIFY fillContentChanged FINAL)
    Q_PROPERTY(bool fitWidth READ fitWidth WRITE setFitWidth NOTIFY fitWidthChanged FINAL)
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged FINAL)
    Q_PROPERTY(bool loaded READ loaded NOTIFY loadedChanged FINAL)
    Q_PROPERTY(QString errorString READ errorString NOTIFY errorStringChanged FINAL)
    Q_PROPERTY(QQuickItem *loadedItem READ loadedItem NOTIFY loadedChanged FINAL)

public:
    explicit ModSlotView(QQuickItem *parent = nullptr);
    ~ModSlotView() override;

    QString modId() const { return m_modId; }
    void setModId(const QString &id);

    QString slotName() const { return m_slotName; }
    void setSlotName(const QString &name);

    QUrl sourceUrl() const { return m_sourceUrl; }
    void setSourceUrl(const QUrl &url);

    QVariantMap slotContext() const { return m_slotContext; }
    void setSlotContext(const QVariantMap &ctx);

    int reloadRevision() const { return m_reloadRevision; }
    void setReloadRevision(int rev);

    bool fillContent() const { return m_fillContent; }
    void setFillContent(bool fill);

    bool fitWidth() const { return m_fitWidth; }
    void setFitWidth(bool fit);

    bool active() const { return m_active; }
    void setActive(bool active);

    bool loaded() const { return m_loadedObject != nullptr; }
    QString errorString() const { return m_errorString; }
    QQuickItem *loadedItem() const { return m_loadedItem.data(); }

signals:
    void modIdChanged();
    void slotNameChanged();
    void sourceUrlChanged();
    void slotContextChanged();
    void reloadRevisionChanged();
    void fillContentChanged();
    void fitWidthChanged();
    void activeChanged();
    void loadedChanged();
    void errorStringChanged();

protected:
    void componentComplete() override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;

private:
    void scheduleReload();
    void clearLoaded();
    void loadNow();
    void syncItemGeometry();
    void syncImplicitSize();
    void setError(const QString &message);

    QString m_modId;
    QString m_slotName;
    QUrl m_sourceUrl;
    QVariantMap m_slotContext;
    int m_reloadRevision = 0;
    bool m_fillContent = true;
    bool m_fitWidth = false;
    bool m_active = true;
    bool m_completed = false;
    QString m_loadedKey;
    QString m_errorString;

    QPointer<QQmlContext> m_modContext;
    QPointer<QObject> m_loadedObject;
    QPointer<QQuickItem> m_loadedItem;
};

} // namespace ymusic::mods
