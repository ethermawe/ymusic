#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include "YMusicBackend.h"
#include "TrackModel.h"
#include "CardModel.h"
#include "ThemeManager.h"

int main(int argc, char *argv[]) {
    qputenv("QT_ENABLE_HTTP2", "0");
    qputenv("QT_DISABLE_HTTP2", "1");
    qputenv("QT_NO_HTTP2", "1");
    QGuiApplication app(argc, argv);
    app.setApplicationName("ymusic");
    app.setOrganizationName("finrixx");
    app.setApplicationDisplayName("Yandex Music");

    QQuickStyle::setStyle("Basic");

    qmlRegisterUncreatableType<TrackModel>("ymusic.ui", 1, 0, "TrackModel", "Provided by backend");
    qmlRegisterUncreatableType<CardModel>("ymusic.ui", 1, 0, "CardModel", "Provided by backend");
    qmlRegisterUncreatableType<YMusicBackend>("ymusic.ui", 1, 0, "YMusicBackend", "Provided by backend");
    qmlRegisterUncreatableType<ThemeManager>("ymusic.ui", 1, 0, "ThemeManager", "Provided by context");

    YMusicBackend backend;

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("backend", &backend);
    engine.rootContext()->setContextProperty("themeManager", &ThemeManager::instance());

    engine.loadFromModule("ymusic.ui", "Main");

    if (engine.rootObjects().isEmpty()) {
        return -1;
    }

    return app.exec();
}
