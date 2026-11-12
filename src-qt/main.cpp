#include <QGuiApplication>
#include <QFont>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQmlNetworkAccessManagerFactory>
#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QNetworkDiskCache>
#include <QStandardPaths>
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QDebug>
#include <QLocalServer>
#include <QLocalSocket>
#include <QLockFile>
#include <QDir>
#include <QFileInfo>
#include "YMusicBackend.h"
#include "TrackModel.h"
#include "CardModel.h"
#include "ThemeManager.h"
#include "AppSettings.h"

class CustomNetworkAccessManager : public QNetworkAccessManager {
    Q_OBJECT
public:
    explicit CustomNetworkAccessManager(QObject *parent = nullptr) : QNetworkAccessManager(parent) {}
protected:
    QNetworkReply *createRequest(Operation op, const QNetworkRequest &request, QIODevice *outgoingData = nullptr) override {
        QNetworkRequest req = request;
        req.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);
        req.setHeader(QNetworkRequest::UserAgentHeader, "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36");
        return QNetworkAccessManager::createRequest(op, req, outgoingData);
    }
};

class CustomNamFactory : public QQmlNetworkAccessManagerFactory {
public:
    QNetworkAccessManager *create(QObject *parent) override {
        auto *nam = new CustomNetworkAccessManager(parent);
        auto *diskCache = new QNetworkDiskCache(nam);
        QString cachePath = QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + "/ymusic_qt_cache";
        diskCache->setCacheDirectory(cachePath);
        diskCache->setMaximumCacheSize(100 * 1024 * 1024); // 100 MB
        nam->setCache(diskCache);
        return nam;
    }
};

int main(int argc, char *argv[]) {
    bool graphicsOverride = qEnvironmentVariableIsSet("QSG_RHI_BACKEND");
    // Opt-in: keep Qt's default and user environment unless explicitly selected.
    for (int i = 1; i < argc; ++i) {
        const QByteArray arg(argv[i]);
        if (arg == "--graphics=vulkan") {
            graphicsOverride = true;
            QQuickWindow::setGraphicsApi(QSGRendererInterface::Vulkan);
        } else if (arg == "--graphics=opengl") {
            graphicsOverride = true;
            QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
        } else if (arg.startsWith("--graphics=")) {
            qCritical() << "Supported graphics backends: vulkan, opengl";
            return 2;
        }
    }
    // Release decoded CPU-side cover pixels once uploaded to the GPU.
    // Respect an explicit user override when diagnosing a graphics driver.
    if (!qEnvironmentVariableIsSet("QSG_TRANSIENT_IMAGES"))
        qputenv("QSG_TRANSIENT_IMAGES", "1");
    QGuiApplication app(argc, argv);
    app.setApplicationName("ymusic");
    app.setOrganizationName("finrixx");
    app.setApplicationDisplayName("Yandex Music");

    // A lock distinguishes a stale socket from a live instance. Never unlink
    // another instance's socket just because it has not started listening yet.
    QString runtimeDir = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    if (runtimeDir.isEmpty()) runtimeDir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    QDir().mkpath(runtimeDir);
    const QString socketName = runtimeDir + "/ymusic-qml-instance";
    QLockFile instanceLock(socketName + ".lock");
    if (!instanceLock.tryLock(0)) {
        QLocalSocket socket;
        socket.connectToServer(socketName);
        if (!socket.waitForConnected(1500)) {
            qWarning() << "YMusic is already running, but could not be activated.";
            return 1;
        }
        socket.write("activate\n");
        socket.waitForBytesWritten(1000);
        return 0;
    }
    QLocalServer instanceServer;
    instanceServer.setSocketOptions(QLocalServer::UserAccessOption);
    QLocalServer::removeServer(socketName);
    if (!instanceServer.listen(socketName)) {
        qCritical() << "Could not create the single-instance socket:" << instanceServer.errorString();
        return 1;
    }

    AppSettings settings;
    if (!graphicsOverride) {
        if (settings.graphicsBackend() == "vulkan")
            QQuickWindow::setGraphicsApi(QSGRendererInterface::Vulkan);
        else if (settings.graphicsBackend() == "opengl")
            QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
    }

    QFont appFont("Rubik", 10);
    appFont.setStyleHint(QFont::SansSerif);
    app.setFont(appFont);

    QQuickStyle::setStyle("Basic");

    qmlRegisterUncreatableType<TrackModel>("ymusic.ui", 1, 0, "TrackModel", "Provided by backend");
    qmlRegisterUncreatableType<CardModel>("ymusic.ui", 1, 0, "CardModel", "Provided by backend");
    qmlRegisterUncreatableType<YMusicBackend>("ymusic.ui", 1, 0, "YMusicBackend", "Provided by backend");
    qmlRegisterUncreatableType<ThemeManager>("ymusic.ui", 1, 0, "ThemeManager", "Provided by context");
    qmlRegisterUncreatableType<AppSettings>("ymusic.ui", 1, 0, "AppSettings", "Provided by context");

    YMusicBackend backend;

    QQmlApplicationEngine engine;
    engine.setNetworkAccessManagerFactory(new CustomNamFactory);
    engine.rootContext()->setContextProperty("backend", &backend);
    engine.rootContext()->setContextProperty("themeManager", &ThemeManager::instance());
    engine.rootContext()->setContextProperty("appSettings", &settings);

    engine.loadFromModule("ymusic.ui", "Main");

    if (engine.rootObjects().isEmpty()) {
        return -1;
    }

    QObject::connect(&instanceServer, &QLocalServer::newConnection, &app, [&]() {
        while (auto *socket = instanceServer.nextPendingConnection()) {
            socket->disconnectFromServer();
            socket->deleteLater();
            if (auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first())) {
                if (window->visibility() == QWindow::Minimized) window->showNormal();
                else window->show();
                window->raise();
                window->requestActivate();
            }
        }
    });

    return app.exec();
}

#include "main.moc"
