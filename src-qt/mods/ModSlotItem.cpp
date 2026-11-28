#include "mods/ModSlotItem.h"

#include "mods/ModApi.h"
#include "mods/ModManager.h"
#include "mods/ModUrlInterceptor.h"

#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlError>

#include <algorithm>

namespace ymusic::mods {

ModSlotView::ModSlotView(QQuickItem *parent)
    : QQuickItem(parent)
{
}

ModSlotView::~ModSlotView()
{
    clearLoaded();
}

void ModSlotView::setModId(const QString &id)
{
    if (m_modId == id) return;
    m_modId = id;
    emit modIdChanged();
    scheduleReload();
}

void ModSlotView::setSlotName(const QString &name)
{
    if (m_slotName == name) return;
    m_slotName = name;
    emit slotNameChanged();
}

void ModSlotView::setSourceUrl(const QUrl &url)
{
    if (m_sourceUrl == url) return;
    m_sourceUrl = url;
    emit sourceUrlChanged();
    scheduleReload();
}

void ModSlotView::setSlotContext(const QVariantMap &ctx)
{
    if (m_slotContext == ctx) return;
    m_slotContext = ctx;
    if (m_modContext) {
        m_modContext->setContextProperty(QStringLiteral("slotContext"), m_slotContext);
    }
    if (m_loadedObject && m_loadedObject->metaObject()->indexOfProperty("slotContext") >= 0) {
        m_loadedObject->setProperty("slotContext", m_slotContext);
    }
    emit slotContextChanged();
}

void ModSlotView::setReloadRevision(int rev)
{
    if (m_reloadRevision == rev) return;
    m_reloadRevision = rev;
    emit reloadRevisionChanged();
    scheduleReload();
}

void ModSlotView::setFillContent(bool fill)
{
    if (m_fillContent == fill) return;
    m_fillContent = fill;
    emit fillContentChanged();
    syncItemGeometry();
}

void ModSlotView::setFitWidth(bool fit)
{
    if (m_fitWidth == fit) return;
    m_fitWidth = fit;
    emit fitWidthChanged();
    syncItemGeometry();
}

void ModSlotView::setActive(bool active)
{
    if (m_active == active) return;
    m_active = active;
    emit activeChanged();
    scheduleReload();
}

void ModSlotView::componentComplete()
{
    QQuickItem::componentComplete();
    m_completed = true;
    loadNow();
}

void ModSlotView::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    syncItemGeometry();
}

void ModSlotView::scheduleReload()
{
    if (m_completed) {
        loadNow();
    }
}

void ModSlotView::clearLoaded()
{
    const bool hadLoaded = (m_loadedObject != nullptr);
    if (m_loadedItem) {
        m_loadedItem->setParentItem(nullptr);
    }
    if (m_loadedObject) {
        m_loadedObject->disconnect(this);
        delete m_loadedObject.data();
        m_loadedObject.clear();
    }
    m_loadedItem.clear();
    if (m_modContext) {
        delete m_modContext.data();
        m_modContext.clear();
    }
    m_loadedKey.clear();
    if (hadLoaded) {
        setImplicitSize(0, 0);
        emit loadedChanged();
    }
}

void ModSlotView::setError(const QString &message)
{
    if (m_errorString != message) {
        m_errorString = message;
        emit errorStringChanged();
    }
    if (!message.isEmpty()) {
        if (ModManager *mgr = ModManager::instance()) {
            mgr->reportModError(m_modId.isEmpty() ? QStringLiteral("sandbox") : m_modId, message);
        }
    }
}

void ModSlotView::loadNow()
{
    if (!m_active || m_modId.isEmpty() || !m_sourceUrl.isValid() || m_sourceUrl.isEmpty()) {
        clearLoaded();
        setError({});
        return;
    }

    const QString key = m_modId + u'|' + m_sourceUrl.toString() + u'|' + QString::number(m_reloadRevision);
    if (key == m_loadedKey && m_loadedObject) {
        return;
    }

    clearLoaded();
    setError({});

    ModManager *mgr = ModManager::instance();
    if (!mgr) {
        setError(QStringLiteral("ModManager недоступен"));
        return;
    }

    ModApi *api = mgr->apiForMod(m_modId);
    QQmlEngine *modEngine = mgr->sandboxEngineForMod(m_modId);
    const QString modDir = mgr->modDirectoryForMod(m_modId);
    if (!api || !modEngine || modDir.isEmpty()) {
        return;
    }

    if (m_sourceUrl.isLocalFile()) {
        QString importErr;
        if (!validateModQmlImports(m_sourceUrl.toLocalFile(), modDir, &importErr)) {
            setError(QStringLiteral("Ошибка слота '%1': %2").arg(m_slotName, importErr));
            return;
        }
    }

    auto *modCtx = new QQmlContext(modEngine->rootContext(), this);
    modCtx->setContextProperty(QStringLiteral("modApi"), api);
    modCtx->setContextProperty(QStringLiteral("slotContext"), m_slotContext);

    QQmlComponent component(modEngine, m_sourceUrl, QQmlComponent::PreferSynchronous);
    if (component.isError()) {
        QStringList errs;
        for (const QQmlError &e : component.errors()) {
            errs.append(e.toString());
        }
        delete modCtx;
        setError(QStringLiteral("Ошибка загрузки слота '%1': %2").arg(m_slotName, errs.join(QStringLiteral(" | "))));
        return;
    }

    QObject *obj = component.beginCreate(modCtx);
    if (!obj) {
        QStringList errs;
        for (const QQmlError &e : component.errors()) {
            errs.append(e.toString());
        }
        delete modCtx;
        setError(QStringLiteral("Не удалось создать компонент слота '%1': %2")
                     .arg(m_slotName, errs.isEmpty() ? m_sourceUrl.toString() : errs.join(QStringLiteral(" | "))));
        return;
    }

    if (obj->metaObject()->indexOfProperty("modApi") >= 0) {
        obj->setProperty("modApi", QVariant::fromValue(static_cast<QObject *>(api)));
    }
    if (obj->metaObject()->indexOfProperty("slotContext") >= 0) {
        obj->setProperty("slotContext", m_slotContext);
    }

    component.completeCreate();
    if (component.isError()) {
        QStringList errs;
        for (const QQmlError &e : component.errors()) {
            errs.append(e.toString());
        }
        delete obj;
        delete modCtx;
        setError(QStringLiteral("Ошибка инициализации слота '%1': %2").arg(m_slotName, errs.join(QStringLiteral(" | "))));
        return;
    }

    // Re-apply after completeCreate() so QML default initializers (e.g. `property var slotContext: ({})`)
    // do not overwrite the injected context/API values.
    if (obj->metaObject()->indexOfProperty("modApi") >= 0) {
        obj->setProperty("modApi", QVariant::fromValue(static_cast<QObject *>(api)));
    }
    if (obj->metaObject()->indexOfProperty("slotContext") >= 0) {
        obj->setProperty("slotContext", m_slotContext);
    }

    m_modContext = modCtx;
    m_loadedObject = obj;
    m_loadedKey = key;

    if (auto *item = qobject_cast<QQuickItem *>(obj)) {
        m_loadedItem = item;
        item->setParent(this);
        item->setParentItem(this);
        connect(item, &QQuickItem::implicitWidthChanged, this, &ModSlotView::syncImplicitSize);
        connect(item, &QQuickItem::implicitHeightChanged, this, &ModSlotView::syncImplicitSize);
        connect(item, &QQuickItem::widthChanged, this, &ModSlotView::syncImplicitSize);
        connect(item, &QQuickItem::heightChanged, this, &ModSlotView::syncImplicitSize);
        syncImplicitSize();
        syncItemGeometry();
    } else {
        obj->setParent(this);
    }

    emit loadedChanged();
}

void ModSlotView::syncItemGeometry()
{
    if (!m_loadedItem) return;
    if (m_fillContent) {
        m_loadedItem->setPosition(QPointF(0, 0));
        m_loadedItem->setSize(size());
    } else if (m_fitWidth) {
        m_loadedItem->setX(0);
        m_loadedItem->setWidth(width());
    }
}

void ModSlotView::syncImplicitSize()
{
    if (!m_loadedItem) return;
    const qreal iw = std::max(m_loadedItem->implicitWidth(), m_loadedItem->width());
    const qreal ih = std::max(m_loadedItem->implicitHeight(), m_loadedItem->height());
    setImplicitSize(iw, ih);
}

} // namespace ymusic::mods
