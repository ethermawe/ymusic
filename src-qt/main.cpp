#include <QApplication>
#include <QSystemTrayIcon>
#include <QMenu>
#include <QAction>
#include <QIcon>
#include <QFont>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlError>
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
#include <QDateTime>
#include <QFile>
#include <QFileInfo>
#include <QLoggingCategory>
#include <QMessageBox>
#include <QMutex>
#include <QMutexLocker>
#include <QProcess>
#include <QSysInfo>
#include <QTextStream>
#include <cstdio>
#ifndef QT_NO_SESSIONMANAGER
#include <QSessionManager>
#endif

#include "YMusicBackend.h"
#include "TrackModel.h"
#include "app/QrImageProvider.h"
#include "CardModel.h"
#include "ThemeManager.h"
#include "AppSettings.h"
#include "app/Fonts.h"
#include "app/Paths.h"
#include "app/UpdateChecker.h"
#include "app/WindowController.h"
#include "artwork/ArtworkCache.h"
#include "app/DevToolsBridge.h"
#include "motion/AmbientClock.h"
#include "motion/ScrollMomentum.h"
#include "mods/ModManager.h"
#include "render/SpectrumSource.h"
#include "theme/PlayerStyle.h"
#include "theme/Theme.h"

namespace {

QMutex g_logMutex;
QFile g_logFile;
QtMessageHandler g_prevHandler = nullptr;

void fileMessageHandler(QtMsgType type, const QMessageLogContext &ctx, const QString &msg) {
    {
        QMutexLocker lock(&g_logMutex);
        if (g_logFile.isOpen()) {
            const char *lvl = "DBG";
            switch (type) {
            case QtDebugMsg: lvl = "DBG"; break;
            case QtInfoMsg: lvl = "INF"; break;
            case QtWarningMsg: lvl = "WRN"; break;
            case QtCriticalMsg: lvl = "CRT"; break;
            case QtFatalMsg: lvl = "FTL"; break;
            }
            QTextStream out(&g_logFile);
            out << QDateTime::currentDateTime().toString(Qt::ISODateWithMs)
                << " [" << lvl << "] " << msg << '\n';
            out.flush();
        }
    }
    if (auto *dt = ymusic::DevToolsBridge::instance()) {
        dt->pushQtLog(type, msg);
    }
    if (g_prevHandler) {
        g_prevHandler(type, ctx, msg);
    } else if (type != QtDebugMsg) {
        const QByteArray local = msg.toLocal8Bit();
        std::fprintf(stderr, "%s\n", local.constData());
        std::fflush(stderr);
    }
}

void installFileLogger() {
    const QString path = ymusic::paths::logFilePath();
    QMutexLocker lock(&g_logMutex);
    const QFileInfo info(path);
    QIODevice::OpenMode mode = QIODevice::WriteOnly | QIODevice::Text;
    if (info.exists() && info.size() < 1024 * 1024) {
        mode |= QIODevice::Append;
    } else {
        mode |= QIODevice::Truncate;
    }
    g_logFile.setFileName(path);
    if (g_logFile.open(mode)) {
        g_prevHandler = qInstallMessageHandler(fileMessageHandler);
    }
}

void showFatalStartupError(const QString &details) {
    qCritical().noquote() << details;
    if (qEnvironmentVariable("QT_QPA_PLATFORM") == QLatin1StringView("offscreen")) {
        return;
    }
    QMessageBox::critical(
        nullptr,
        QStringLiteral("Yandex Music"),
        details + QStringLiteral("\n\nЛог: ") + ymusic::paths::logFilePath());
}

void tuneSceneGraph() {
    const auto fallback = [](const char *name, const char *value) {
        if (!qEnvironmentVariableIsSet(name)) {
            qputenv(name, value);
        }
    };
    fallback("QSG_ATLAS_WIDTH", "64");
    fallback("QSG_ATLAS_HEIGHT", "64");
    fallback("QSG_ATLAS_SIZE_LIMIT", "1");
    fallback("QSG_TRANSIENT_IMAGES", "1");
    fallback("QT_MAX_CACHED_GLYPH_SIZE", "512");
}

} // namespace

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
        diskCache->setMaximumCacheSize(100 * 1024 * 1024);
        nam->setCache(diskCache);
        return nam;
    }
};

int main(int argc, char *argv[]) {
    bool graphicsOverride = qEnvironmentVariableIsSet("QSG_RHI_BACKEND");
    bool safeModeArg = false;
    for (int i = 1; i < argc; ++i) {
        const QByteArray arg(argv[i]);
        if (arg == "--safe-mode") {
            safeModeArg = true;
        } else if (arg == "--graphics=vulkan") {
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
    tuneSceneGraph();

    QApplication app(argc, argv);
    app.setApplicationName("ymusic");
    app.setOrganizationName("finrixx");
    app.setApplicationDisplayName("Yandex Music");
#ifdef YMUSIC_APP_VERSION
    app.setApplicationVersion(QStringLiteral(YMUSIC_APP_VERSION));
#endif
    app.setDesktopFileName("ymusic");
    installFileLogger();
    qInfo().noquote() << QStringLiteral("Starting Yandex Music %1 on %2 (%3)")
        .arg(app.applicationVersion(), QSysInfo::prettyProductName(), QGuiApplication::platformName());

    QIcon appIcon = QIcon::fromTheme(QStringLiteral("ymusic"));
    if (appIcon.isNull()) appIcon = QIcon(QStringLiteral(":/icons/ymusic.svg"));
    if (appIcon.isNull()) appIcon = QIcon(QStringLiteral(":/icons/ymusic.png"));
    if (appIcon.isNull()) appIcon = QIcon(QStringLiteral(":/icon.svg"));
    app.setWindowIcon(appIcon);

    QString runtimeDir = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    if (runtimeDir.isEmpty()) runtimeDir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    QDir().mkpath(runtimeDir);
    const QString lockPath = runtimeDir + "/ymusic-qml-instance.lock";
#ifdef Q_OS_WIN
    const QString socketName = QStringLiteral("ymusic-qml-instance");
#else
    const QString socketName = runtimeDir + "/ymusic-qml-instance";
#endif
    QLockFile instanceLock(lockPath);
    instanceLock.setStaleLockTime(0);
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
        showFatalStartupError(
            QStringLiteral("Не удалось создать сокет одиночного экземпляра: %1")
                .arg(instanceServer.errorString()));
        return 1;
    }

#ifdef Q_OS_LINUX
    ymusic::ScrollMomentum scrollMomentum;
    app.installEventFilter(&scrollMomentum);
#endif

    AppSettings settings;
    if (!graphicsOverride) {
        if (settings.graphicsBackend() == "vulkan")
            QQuickWindow::setGraphicsApi(QSGRendererInterface::Vulkan);
        else if (settings.graphicsBackend() == "opengl")
            QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
    }

    QQuickStyle::setStyle("Basic");
    ymusic::fonts::loadIconFont();
    ymusic::fonts::loadInterfaceFont();

    QFont appFont(ymusic::fonts::interfaceFamily(), 10);
    appFont.setStyleHint(QFont::SansSerif);
    app.setFont(appFont);

    extern void qml_register_types_ymusic_ui();
    qml_register_types_ymusic_ui();

    qmlRegisterUncreatableType<TrackModel>("ymusic.ui", 1, 0, "TrackModel", "Provided by backend");
    qmlRegisterUncreatableType<CardModel>("ymusic.ui", 1, 0, "CardModel", "Provided by backend");
    qmlRegisterUncreatableType<YMusicBackend>("ymusic.ui", 1, 0, "YMusicBackend", "Provided by backend");
    qmlRegisterUncreatableType<ThemeManager>("ymusic.ui", 1, 0, "ThemeManager", "Provided by context");
    qmlRegisterUncreatableType<AppSettings>("ymusic.ui", 1, 0, "AppSettings", "Provided by context");

    CustomNetworkAccessManager network;
    YMusicBackend backend;
    ymusic::ArtworkCache artwork(&network);
    ymusic::Theme theme(&settings);
    ymusic::PlayerStyle playerStyle(&backend, &theme, &artwork);
    ymusic::SpectrumSource spectrum(&backend);
    const bool safeMode = safeModeArg || QGuiApplication::queryKeyboardModifiers().testFlag(Qt::ShiftModifier);
    ymusic::mods::ModManager modManager(&settings, &backend, &spectrum, safeMode);

    ThemeManager::instance().setPreset(settings.themePreset());
    const auto syncDiscord = [&]() {
        backend.setDiscordRpcConfig(
            settings.discordRpcEnabled(),
            settings.discordRpcDisplay(),
            settings.discordRpcType(),
            settings.discordRpcShowPaused(),
            settings.discordRpcShowCover(),
            settings.discordRpcShowAlbum(),
            settings.discordRpcShowTimestamps(),
            settings.discordRpcShowButton());
    };
    syncDiscord();
    backend.setTempo(settings.playbackSpeed());
    QObject::connect(&settings, &AppSettings::changed, &backend, [&]() {
        ThemeManager::instance().setPreset(settings.themePreset());
        syncDiscord();
        if (!qFuzzyCompare(backend.tempo() + 1.0, settings.playbackSpeed() + 1.0)) {
            backend.setTempo(settings.playbackSpeed());
        }
    });

    const bool trayAvailable = QSystemTrayIcon::isSystemTrayAvailable();
    if (trayAvailable) {
        app.setQuitOnLastWindowClosed(false);
    }

    ymusic::WindowController windowController;
    ymusic::UpdateChecker updateChecker;
    ymusic::DevToolsBridge devToolsBridge;
    updateChecker.setAutoCheckEnabled(settings.autoUpdateEnabled());
    QObject::connect(&settings, &AppSettings::autoUpdateEnabledChanged, &updateChecker, [&]() {
        updateChecker.setAutoCheckEnabled(settings.autoUpdateEnabled());
    });

    QQmlApplicationEngine engine;
    devToolsBridge.attachEngine(&engine);
    modManager.attachEngine(&engine);
    engine.addUrlInterceptor(modManager.urlInterceptor());
    engine.setNetworkAccessManagerFactory(new CustomNamFactory);
    engine.addImageProvider(QStringLiteral("art"), new ymusic::ArtworkImageProvider);
    engine.addImageProvider(QStringLiteral("qr"), new ymusic::QrImageProvider);
    engine.rootContext()->setContextProperty("backend", &backend);
    engine.rootContext()->setContextProperty("themeManager", &ThemeManager::instance());
    engine.rootContext()->setContextProperty("appSettings", &settings);
    engine.rootContext()->setContextProperty("spinClock", ymusic::AmbientClock::spin());
    engine.rootContext()->setContextProperty("trayAvailable", trayAvailable);
    engine.rootContext()->setContextProperty("windowController", &windowController);
    engine.rootContext()->setContextProperty("updater", &updateChecker);
    engine.rootContext()->setContextProperty("devTools", &devToolsBridge);

    QStringList qmlErrors;
    QObject::connect(&engine, &QQmlApplicationEngine::warnings, &app, [&](const QList<QQmlError> &warnings) {
        for (const QQmlError &err : warnings) {
            const QString line = err.toString();
            qWarning().noquote() << line;
            qmlErrors.append(line);
        }
    });

    engine.loadFromModule("ymusic.ui", "Main");

    if (engine.rootObjects().isEmpty() && modManager.activeOverrideCount() > 0) {
        const QString reason = qmlErrors.isEmpty()
            ? QStringLiteral("Ошибка загрузки Main с активными UI-оверрайдами")
            : qmlErrors.join(QStringLiteral(" | "));
        modManager.quarantineOverrideMods(reason);
        qmlErrors.clear();
        engine.clearComponentCache();
        engine.loadFromModule("ymusic.ui", "Main");
    }

    if (engine.rootObjects().isEmpty()) {
        const QString detail = qmlErrors.isEmpty()
            ? QStringLiteral("Не удалось загрузить интерфейс приложения (ymusic.ui/Main).")
            : QStringLiteral("Не удалось загрузить интерфейс приложения:\n\n") + qmlErrors.join(QLatin1Char('\n'));
        showFatalStartupError(detail);
        return -1;
    }

    auto toggleWindowVisibility = [&]() {
        if (auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first())) {
            if (window->isVisible() && window->visibility() != QWindow::Minimized) {
                window->hide();
            } else {
                if (window->visibility() == QWindow::Minimized) window->showNormal();
                else window->show();
                window->raise();
                window->requestActivate();
            }
        }
    };

    if (trayAvailable) {
        auto *tray = new QSystemTrayIcon(appIcon, &app);
        auto *trayMenu = new QMenu();

        auto *trackInfoAction = trayMenu->addAction(QStringLiteral("Yandex Music"));
        trackInfoAction->setEnabled(false);

        auto *showAction = trayMenu->addAction(QStringLiteral("Показать / скрыть окно"));
        QObject::connect(showAction, &QAction::triggered, &app, toggleWindowVisibility);

        trayMenu->addSeparator();

        auto *playPauseAction = trayMenu->addAction(QStringLiteral("Воспроизвести"));
        QObject::connect(playPauseAction, &QAction::triggered, &backend, &YMusicBackend::toggle);

        auto *prevAction = trayMenu->addAction(QStringLiteral("Предыдущий трек"));
        QObject::connect(prevAction, &QAction::triggered, &backend, &YMusicBackend::prev);

        auto *nextAction = trayMenu->addAction(QStringLiteral("Следующий трек"));
        QObject::connect(nextAction, &QAction::triggered, &backend, &YMusicBackend::next);

        auto *likeAction = trayMenu->addAction(QStringLiteral("Нравится"));
        likeAction->setEnabled(false);
        QObject::connect(likeAction, &QAction::triggered, &backend, &YMusicBackend::toggleNowLike);

        trayMenu->addSeparator();

        auto *quitAction = trayMenu->addAction(QStringLiteral("Выйти"));
        QObject::connect(quitAction, &QAction::triggered, &app, &QApplication::quit);

        auto updateTrayPlayback = [&, playPauseAction]() {
            playPauseAction->setText(backend.playing() ? QStringLiteral("Пауза") : QStringLiteral("Воспроизвести"));
        };
        auto updateTrayTrack = [&, tray, trackInfoAction, likeAction]() {
            if (backend.hasTrack()) {
                const QString label = backend.nowArtists().isEmpty()
                    ? backend.nowTitle()
                    : QStringLiteral("%1 — %2").arg(backend.nowArtists(), backend.nowTitle());
                trackInfoAction->setText(label);
                tray->setToolTip(label);
                likeAction->setEnabled(true);
                likeAction->setText(backend.nowLiked() ? QStringLiteral("Убрать лайк") : QStringLiteral("Нравится"));
            } else {
                trackInfoAction->setText(QStringLiteral("Yandex Music"));
                tray->setToolTip(QStringLiteral("Yandex Music"));
                likeAction->setEnabled(false);
                likeAction->setText(QStringLiteral("Нравится"));
            }
        };

        QObject::connect(&backend, &YMusicBackend::playbackStateChanged, &app, updateTrayPlayback);
        QObject::connect(&backend, &YMusicBackend::nowPlayingChanged, &app, updateTrayTrack);
        QObject::connect(tray, &QSystemTrayIcon::activated, &app, [&](QSystemTrayIcon::ActivationReason reason) {
            if (reason == QSystemTrayIcon::Trigger || reason == QSystemTrayIcon::DoubleClick) {
                toggleWindowVisibility();
            } else if (reason == QSystemTrayIcon::MiddleClick) {
                backend.toggle();
            }
        });

        updateTrayPlayback();
        updateTrayTrack();
        tray->setContextMenu(trayMenu);
        tray->show();
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

    QObject::connect(&app, &QCoreApplication::aboutToQuit, &backend, &YMusicBackend::saveSession);
#ifndef QT_NO_SESSIONMANAGER
    QObject::connect(&app, &QGuiApplication::commitDataRequest, &backend, [&](QSessionManager &) {
        backend.saveSession();
    });
#endif

    updateChecker.startAutoCheck();
    const int exitCode = app.exec();
    instanceServer.close();
    instanceLock.unlock();
    if (modManager.restartRequested()) {
        QStringList restartArgs = QCoreApplication::arguments().mid(1);
        restartArgs.removeAll(QStringLiteral("--safe-mode"));
        QProcess::startDetached(QCoreApplication::applicationFilePath(), restartArgs);
    }
    return exitCode;
}

#include "main.moc"
