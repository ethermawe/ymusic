#include "app/DevToolsBridge.h"

#include <QClipboard>
#include <QColor>
#include <QDateTime>
#include <QFile>
#include <QGuiApplication>
#include <QMetaObject>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QTextStream>
#include <algorithm>
#include <vector>

#ifdef Q_OS_LINUX
#include <unistd.h>
#endif

#ifdef Q_OS_WIN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <psapi.h>
#endif

namespace ymusic {

namespace {

constexpr int kMaxLogEntries = 400;

QString cleanTypeName(const QObject *obj) {
    if (!obj) return {};
    QString name = QString::fromLatin1(obj->metaObject()->className());
    const int qmlIdx = name.indexOf(QStringLiteral("_QMLTYPE_"));
    if (qmlIdx > 0) {
        name = name.left(qmlIdx);
    }
    const int qmlGenIdx = name.indexOf(QStringLiteral("_QML_"));
    if (qmlGenIdx > 0) {
        name = name.left(qmlGenIdx);
    }
    if (name.startsWith(QStringLiteral("QQuick"))) {
        name = name.mid(6);
    }
    return name;
}

int countItemsRec(const QQuickItem *item) {
    if (!item) return 0;
    int total = 1;
    const auto children = item->childItems();
    for (const QQuickItem *child : children) {
        total += countItemsRec(child);
    }
    return total;
}

bool isPassThroughType(const QString &type) {
    return type == QLatin1StringView("MouseArea")
        || type == QLatin1StringView("CornerCaps")
        || type == QLatin1StringView("Stickers")
        || type == QLatin1StringView("Ripple")
        || type == QLatin1StringView("SoftShadow")
        || type == QLatin1StringView("SoftShadowItem")
        || type == QLatin1StringView("FastWheel")
        || type == QLatin1StringView("FocusScope")
        || type == QLatin1StringView("Loader")
        || type == QLatin1StringView("DevToolsOverlay");
}

bool isVisualCandidate(const QQuickItem *item, const QString &type) {
    if (isPassThroughType(type)) return false;
    if (item->width() <= 0.0 || item->height() <= 0.0) return false;
    // Skip transparent rectangles with no border (often used as layout/clip wrappers).
    if (type == QLatin1StringView("Rectangle")) {
        const QColor c = item->property("color").value<QColor>();
        if (c.isValid() && c.alpha() == 0) {
            const QObject *border = item->property("border").value<QObject *>();
            const qreal bw = border ? border->property("width").toReal() : 0.0;
            if (bw <= 0.0) return false;
        }
    }
    // Skip plain empty QQuickItem containers (like `bursts` overlay, Row/Column/Layouts).
    const QByteArray raw = item->metaObject()->className();
    if (raw == "QQuickItem" || raw == "QQuickRow" || raw == "QQuickColumn"
        || raw == "QQuickFlow" || raw == "QQuickGrid" || raw == "QQuickRowLayout"
        || raw == "QQuickColumnLayout" || raw == "QQuickGridLayout"
        || raw == "QQuickLoader" || raw == "QQuickOverlay") {
        return false;
    }
    if (item->flags() & QQuickItem::ItemHasContents) {
        return true;
    }
    // Named custom QML components (e.g. RippleButton, IconButton, TrackRow, CardItem).
    return raw.contains("_QMLTYPE_") || raw.contains("_QML_");
}

QQuickItem *pickDeepest(QQuickItem *item,
                        const QPointF &scenePt,
                        QQuickItem *ignoreSubtree) {
    if (!item || item == ignoreSubtree || !item->isVisible() || item->opacity() <= 0.001) {
        return nullptr;
    }

    const QPointF local = item->mapFromScene(scenePt);
    const bool inside = local.x() >= 0.0 && local.y() >= 0.0
        && local.x() <= item->width() && local.y() <= item->height();

    if (item->clip() && !inside) {
        return nullptr;
    }

    // Visit children in reverse stacking order (higher z / later sibling first).
    QList<QQuickItem *> children = item->childItems();
    std::stable_sort(children.begin(), children.end(), [](const QQuickItem *a, const QQuickItem *b) {
        return a->z() < b->z();
    });
    for (int i = children.size() - 1; i >= 0; --i) {
        if (QQuickItem *hit = pickDeepest(children.at(i), scenePt, ignoreSubtree)) {
            return hit;
        }
    }

    if (inside) {
        const QString type = cleanTypeName(item);
        if (isVisualCandidate(item, type)) {
            return item;
        }
    }
    return nullptr;
}

void collectModSlotsRec(QQuickItem *item, QQuickItem *root, QVariantList &out) {
    if (!item || !item->isVisible()) return;
    const QString type = cleanTypeName(item);
    if (type == QLatin1StringView("ModSlotHost")) {
        const QString slotName = item->property("slotName").toString();
        if (!slotName.isEmpty()) {
            const QRectF rect = root
                ? root->mapRectFromItem(item, QRectF(0, 0, item->width(), item->height()))
                : item->mapRectToScene(QRectF(0, 0, item->width(), item->height()));
            QVariantMap entry;
            entry.insert(QStringLiteral("slotName"), slotName);
            entry.insert(QStringLiteral("x"), rect.x());
            entry.insert(QStringLiteral("y"), rect.y());
            entry.insert(QStringLiteral("width"), rect.width());
            entry.insert(QStringLiteral("height"), rect.height());
            out.append(entry);
        }
    }
    const auto children = item->childItems();
    for (QQuickItem *child : children) {
        collectModSlotsRec(child, root, out);
    }
}

} // namespace

DevToolsBridge::DevToolsBridge(QObject *parent) : QObject(parent) {
    s_instance = this;
}

DevToolsBridge::~DevToolsBridge() {
    if (s_instance == this) {
        s_instance = nullptr;
    }
}

DevToolsBridge *DevToolsBridge::instance() {
    return s_instance;
}

void DevToolsBridge::attachEngine(QQmlEngine *engine) {
    m_engine = engine;
}

void DevToolsBridge::pushQtLog(QtMsgType type, const QString &message) {
    QString level = QStringLiteral("info");
    switch (type) {
    case QtDebugMsg: level = QStringLiteral("debug"); break;
    case QtInfoMsg: level = QStringLiteral("info"); break;
    case QtWarningMsg: level = QStringLiteral("warn"); break;
    case QtCriticalMsg:
    case QtFatalMsg: level = QStringLiteral("error"); break;
    }

    QMetaObject::invokeMethod(
        this,
        [this, level, message]() {
            appendLogInternal(level, QStringLiteral("qt"), message);
        },
        Qt::QueuedConnection);
}

QVariantList DevToolsBridge::logs() const {
    QMutexLocker lock(&m_mutex);
    return m_logs;
}

QString DevToolsBridge::qtVersion() const {
    return QString::fromLatin1(qVersion());
}

QString DevToolsBridge::graphicsApi() const {
    switch (QQuickWindow::graphicsApi()) {
    case QSGRendererInterface::Vulkan: return QStringLiteral("Vulkan");
    case QSGRendererInterface::OpenGL: return QStringLiteral("OpenGL");
    case QSGRendererInterface::Direct3D11: return QStringLiteral("Direct3D 11");
    case QSGRendererInterface::Direct3D12: return QStringLiteral("Direct3D 12");
    case QSGRendererInterface::Metal: return QStringLiteral("Metal");
    case QSGRendererInterface::Software: return QStringLiteral("Software");
    default: return QStringLiteral("Auto");
    }
}

void DevToolsBridge::refreshMetrics() {
    double rss = 0.0;
    double pss = 0.0;

#ifdef Q_OS_LINUX
    QFile rollup(QStringLiteral("/proc/self/smaps_rollup"));
    if (rollup.open(QIODevice::ReadOnly | QIODevice::Text)) {
        const QByteArray data = rollup.readAll();
        const QList<QByteArray> lines = data.split('\n');
        for (const QByteArray &line : lines) {
            if (line.startsWith("Rss:")) {
                const auto parts = line.simplified().split(' ');
                if (parts.size() >= 2) rss = parts[1].toDouble() / 1024.0;
            } else if (line.startsWith("Pss:")) {
                const auto parts = line.simplified().split(' ');
                if (parts.size() >= 2) pss = parts[1].toDouble() / 1024.0;
            }
        }
    }
    if (rss <= 0.0) {
        QFile statm(QStringLiteral("/proc/self/statm"));
        if (statm.open(QIODevice::ReadOnly | QIODevice::Text)) {
            const auto parts = statm.readAll().simplified().split(' ');
            if (parts.size() >= 2) {
                const long pageSize = ::sysconf(_SC_PAGESIZE);
                rss = (parts[1].toDouble() * static_cast<double>(pageSize)) / (1024.0 * 1024.0);
            }
        }
    }
#elif defined(Q_OS_WIN)
    PROCESS_MEMORY_COUNTERS_EX pmc{};
    if (GetProcessMemoryInfo(GetCurrentProcess(),
                             reinterpret_cast<PROCESS_MEMORY_COUNTERS *>(&pmc),
                             sizeof(pmc))) {
        rss = static_cast<double>(pmc.WorkingSetSize) / (1024.0 * 1024.0);
        pss = static_cast<double>(pmc.PrivateUsage) / (1024.0 * 1024.0);
    }
#endif

    m_rssMb = rss;
    m_pssMb = pss > 0.0 ? pss : rss;
    emit metricsChanged();
}

void DevToolsBridge::clearLogs() {
    {
        QMutexLocker lock(&m_mutex);
        m_logs.clear();
    }
    emit logsChanged();
}

void DevToolsBridge::appendConsoleEntry(const QString &level,
                                        const QString &source,
                                        const QString &message) {
    appendLogInternal(level, source, message);
}

void DevToolsBridge::appendLogInternal(const QString &level,
                                       const QString &source,
                                       const QString &message) {
    QVariantMap entry;
    entry.insert(QStringLiteral("time"), QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss.zzz")));
    entry.insert(QStringLiteral("level"), level);
    entry.insert(QStringLiteral("source"), source);
    entry.insert(QStringLiteral("message"), message);

    {
        QMutexLocker lock(&m_mutex);
        m_logs.append(entry);
        if (m_logs.size() > kMaxLogEntries) {
            m_logs.remove(0, m_logs.size() - kMaxLogEntries);
        }
    }
    emit logsChanged();
}

int DevToolsBridge::countItems(QQuickItem *root) const {
    return countItemsRec(root);
}

QQuickItem *DevToolsBridge::pickItemAt(QQuickItem *root,
                                       qreal x,
                                       qreal y,
                                       QQuickItem *ignoreSubtree) const {
    if (!root) return nullptr;
    const QPointF scenePt = root->mapToScene(QPointF(x, y));
    return pickDeepest(root, scenePt, ignoreSubtree);
}

QVariantMap DevToolsBridge::inspectItem(QQuickItem *item, QQuickItem *coordRoot) const {
    QVariantMap info;
    if (!item) return info;

    const QRectF sceneRect = coordRoot
        ? coordRoot->mapRectFromItem(item, QRectF(0, 0, item->width(), item->height()))
        : item->mapRectToScene(QRectF(0, 0, item->width(), item->height()));

    info.insert(QStringLiteral("type"), cleanTypeName(item));
    info.insert(QStringLiteral("rawClass"), QString::fromLatin1(item->metaObject()->className()));
    info.insert(QStringLiteral("objectName"), item->objectName());
    info.insert(QStringLiteral("x"), item->x());
    info.insert(QStringLiteral("y"), item->y());
    info.insert(QStringLiteral("width"), item->width());
    info.insert(QStringLiteral("height"), item->height());
    info.insert(QStringLiteral("sceneX"), sceneRect.x());
    info.insert(QStringLiteral("sceneY"), sceneRect.y());
    info.insert(QStringLiteral("sceneWidth"), sceneRect.width());
    info.insert(QStringLiteral("sceneHeight"), sceneRect.height());
    info.insert(QStringLiteral("visible"), item->isVisible());
    info.insert(QStringLiteral("opacity"), item->opacity());
    info.insert(QStringLiteral("z"), item->z());
    info.insert(QStringLiteral("clip"), item->clip());
    info.insert(QStringLiteral("childCount"), item->childItems().size());

    const QVariant colorVar = item->property("color");
    if (colorVar.isValid() && colorVar.canConvert<QColor>()) {
        const QColor c = colorVar.value<QColor>();
        if (c.isValid()) {
            info.insert(QStringLiteral("color"), c.name(QColor::HexArgb));
        }
    }
    const QVariant textVar = item->property("text");
    if (textVar.isValid()) {
        const QString t = textVar.toString();
        if (!t.isEmpty()) {
            info.insert(QStringLiteral("text"), t.left(140));
        }
    }
    const QVariant slotVar = item->property("slotName");
    if (slotVar.isValid()) {
        const QString s = slotVar.toString();
        if (!s.isEmpty()) {
            info.insert(QStringLiteral("slotName"), s);
        }
    }

    QVariantList chain;
    QQuickItem *cur = item;
    int depth = 0;
    while (cur && depth < 12) {
        QVariantMap node;
        node.insert(QStringLiteral("type"), cleanTypeName(cur));
        node.insert(QStringLiteral("objectName"), cur->objectName());
        node.insert(QStringLiteral("stepsUp"), depth);
        chain.append(node);
        cur = cur->parentItem();
        ++depth;
    }
    info.insert(QStringLiteral("chain"), chain);
    return info;
}

QQuickItem *DevToolsBridge::ancestorAt(QQuickItem *item, int stepsUp) const {
    QQuickItem *cur = item;
    for (int i = 0; i < stepsUp && cur; ++i) {
        cur = cur->parentItem();
    }
    return cur;
}

QVariantList DevToolsBridge::findModSlots(QQuickItem *root) const {
    QVariantList out;
    collectModSlotsRec(root, root, out);
    return out;
}

void DevToolsBridge::copyToClipboard(const QString &text) const {
    if (QClipboard *cb = QGuiApplication::clipboard()) {
        cb->setText(text);
    }
}

void DevToolsBridge::collectGarbage() {
    if (m_engine) {
        m_engine->collectGarbage();
    }
}

} // namespace ymusic
