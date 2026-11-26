#include "AppSettings.h"
#include "app/Paths.h"
#include "mods/ModApi.h"
#include "mods/ModManager.h"
#include "mods/ModManifest.h"
#include "mods/ModScriptHost.h"
#include "mods/ModUrlInterceptor.h"

#include <QDir>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QFile>
#include <QGuiApplication>
#include <QHostAddress>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QUrl>

#if __has_include(<QtCore/private/qzipwriter_p.h>)
#include <QtCore/private/qzipwriter_p.h>
#elif __has_include(<QtGui/private/qzipwriter_p.h>)
#include <QtGui/private/qzipwriter_p.h>
#else
#error "QZipWriter private header not found"
#endif

#include <iostream>
#include <memory>

using namespace ymusic::mods;

#define CHECK(cond)                                                                         \
    do {                                                                                    \
        if (!(cond)) {                                                                      \
            std::cerr << "Check failed at line " << __LINE__ << ": " #cond << std::endl;    \
            return 1;                                                                       \
        }                                                                                   \
    } while (false)

static bool writeText(const QString &path, const QByteArray &content) {
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) return false;
    return f.write(content) == content.size();
}

int main(int argc, char *argv[]) {
    QTemporaryDir tmpDir;
    if (!tmpDir.isValid()) return 1;
    qputenv("HOME", tmpDir.path().toUtf8());
    qputenv("XDG_DATA_HOME", (tmpDir.path() + QStringLiteral("/data")).toUtf8());
    qputenv("XDG_CONFIG_HOME", (tmpDir.path() + QStringLiteral("/config")).toUtf8());
    QGuiApplication app(argc, argv);
    app.setApplicationVersion(QStringLiteral("0.2.6"));

    // 1. Validate mod id rules
    CHECK(isValidModId(QStringLiteral("hello-ymusic")));
    CHECK(isValidModId(QStringLiteral("mod_123")));
    CHECK(!isValidModId(QStringLiteral("../escape")));
    CHECK(!isValidModId(QStringLiteral("BadCaps")));
    CHECK(!isValidModId(QStringLiteral("x")));

    // 2. Path traversal rejection
    const QString badModDir = ymusic::paths::modsDirectory() + QStringLiteral("/bad-mod");
    CHECK(writeText(badModDir + QStringLiteral("/manifest.json"), R"({
        "id": "bad-mod",
        "name": "Bad Mod",
        "version": "1.0.0",
        "apiVersion": 1,
        "permissions": ["ui:slots"],
        "slots": { "sidebar.page": "../../etc/passwd" }
    })"));
    const ModManifest bad = parseManifest(badModDir);
    CHECK(!bad.valid);
    QDir(badModDir).removeRecursively();

    // 3. Override without ui:override permission must be rejected
    const QString unauthOverrideDir = ymusic::paths::modsDirectory() + QStringLiteral("/no-perm-override");
    CHECK(writeText(unauthOverrideDir + QStringLiteral("/overrides/Bar.qml"), "import QtQuick\nItem {}\n"));
    CHECK(writeText(unauthOverrideDir + QStringLiteral("/manifest.json"), R"({
        "id": "no-perm-override",
        "name": "No Perm",
        "version": "1.0.0",
        "apiVersion": 1,
        "permissions": ["ui:slots"],
        "overrides": { "qml/player/FloatingPlayerBar.qml": "overrides/Bar.qml" }
    })"));
    const ModManifest unauth = parseManifest(unauthOverrideDir);
    CHECK(!unauth.valid);
    QDir(unauthOverrideDir).removeRecursively();

    // 3b. minAppVersion enforcement
    const QString futureModDir = ymusic::paths::modsDirectory() + QStringLiteral("/future-mod");
    CHECK(writeText(futureModDir + QStringLiteral("/manifest.json"), R"({
        "id": "future-mod",
        "name": "Future Mod",
        "version": "1.0.0",
        "minAppVersion": "9.9.0",
        "apiVersion": 1,
        "permissions": ["ui:slots"]
    })"));
    const ModManifest future = parseManifest(futureModDir);
    CHECK(!future.valid);
    QDir(futureModDir).removeRecursively();

    // 4. Valid mod with unified "ui" block (string, object, and array), shortcuts, lyrics, storage, override, and network allowlist
    const QString goodModDir = ymusic::paths::modsDirectory() + QStringLiteral("/demo-mod");
    CHECK(writeText(goodModDir + QStringLiteral("/ui/Page.qml"), "import QtQuick\nItem {}\n"));
    CHECK(writeText(goodModDir + QStringLiteral("/ui/Page2.qml"), "import QtQuick\nItem {}\n"));
    CHECK(writeText(goodModDir + QStringLiteral("/overrides/Bar.qml"), "import QtQuick\nItem {}\n"));
    CHECK(writeText(goodModDir + QStringLiteral("/manifest.json"), R"({
        "id": "demo-mod",
        "name": "Demo Mod",
        "version": "1.2.3",
        "author": "Tester",
        "minAppVersion": "0.2.0",
        "apiVersion": 1,
        "permissions": [
            "playback:read",
            "library:read",
            "lyrics:read",
            "lyrics:transform",
            "ui:slots",
            "ui:override",
            "storage",
            "network:api.example.com"
        ],
        "ui": {
            "sidebar.page": [
                { "id": "main", "file": "ui/Page.qml", "title": "Демо 1", "symbol": "extension" },
                { "id": "stats", "file": "ui/Page2.qml", "title": "Демо 2", "symbol": "bar_chart" }
            ],
            "settings.tab": { "file": "ui/Page.qml", "title": "Демо-глава", "symbol": "tune", "shape": "gem" },
            "settings.section.player": "ui/Page.qml",
            "playerBar.controls": "ui/Page.qml",
            "immersive.panel": { "file": "ui/Page.qml", "title": "Демо-панель", "symbol": "auto_awesome" }
        },
        "shortcuts": [
            { "id": "quick-ping", "sequence": "Ctrl+Alt+P", "description": "Ping" }
        ],
        "overrides": { "qml/player/FloatingPlayerBar.qml": "overrides/Bar.qml" }
    })"));

    AppSettings settings;
    ModManager manager(&settings, nullptr, nullptr, false);
    CHECK(manager.modsVariantList().size() == 1);
    const QVariantMap modInfo = manager.modsVariantList().first().toMap();
    CHECK(modInfo.value(QStringLiteral("overrideTargets")).toStringList().contains(QStringLiteral("qml/player/FloatingPlayerBar.qml")));
    CHECK(manager.activeModCount() == 0);
    CHECK(manager.activeOverrideCount() == 0);

    // Enable mod
    manager.setModEnabled(QStringLiteral("demo-mod"), true);
    CHECK(manager.activeModCount() == 1);
    CHECK(manager.activeOverrideCount() == 1);
    CHECK(manager.overridesNeedRestart());
    CHECK(manager.shortcutsVariantList().size() == 1);

    // URL interceptor matches overridden QML and ignores unrelated paths
    const QUrl intercepted = manager.urlInterceptor()->intercept(
        QUrl(QStringLiteral("qrc:/qt/qml/ymusic/ui/qml/player/FloatingPlayerBar.qml")),
        QQmlAbstractUrlInterceptor::QmlFile);
    CHECK(intercepted.isLocalFile());
    CHECK(intercepted.toLocalFile().endsWith(QStringLiteral("/overrides/Bar.qml")));

    const QUrl untouched = manager.urlInterceptor()->intercept(
        QUrl(QStringLiteral("qrc:/qt/qml/ymusic/ui/qml/Main.qml")),
        QQmlAbstractUrlInterceptor::QmlFile);
    CHECK(untouched == QUrl(QStringLiteral("qrc:/qt/qml/ymusic/ui/qml/Main.qml")));

    // ModApi permission enforcement, storage, HTTP method/host validation, shortcuts, and lyrics subtitles
    ModApi *api = manager.apiForMod(QStringLiteral("demo-mod"));
    CHECK(api != nullptr);
    CHECK(!api->toggle()); // playback:control not granted
    CHECK(!api->httpGet(QStringLiteral("https://evil.example.org/steal"), QStringLiteral("req1")));
    CHECK(!api->httpRequest(QStringLiteral("TRACE"), QStringLiteral("https://api.example.com/v1"), {}, QString(), QStringLiteral("req2")));
    CHECK(api->storageSet(QStringLiteral("counter"), 42));
    CHECK(api->storageGet(QStringLiteral("counter")).toInt() == 42);
    CHECK(api->registerTrackMenuAction(QStringLiteral("open"), QStringLiteral("Открыть"), QStringLiteral("open_in_new"), false));
    CHECK(manager.trackMenuActionsVariantList().size() == 1);

    // Dynamic shortcut registration & trigger
    CHECK(api->registerShortcut(QStringLiteral("dyn-act"), QStringLiteral("Ctrl+Alt+D"), QStringLiteral("Dynamic")));
    CHECK(manager.shortcutsVariantList().size() == 2);
    QString triggeredAction;
    QObject::connect(api, &ModApi::shortcutTriggered, [&](const QString &act) { triggeredAction = act; });
    manager.triggerShortcut(QStringLiteral("demo-mod"), QStringLiteral("dyn-act"));
    CHECK(triggeredAction == QStringLiteral("dyn-act"));
    api->unregisterShortcut(QStringLiteral("dyn-act"));
    CHECK(manager.shortcutsVariantList().size() == 1);

    // Lyrics sync & subtitle overlay
    QVariantList sampleLines;
    sampleLines.append(QVariantMap{{QStringLiteral("text"), QStringLiteral("Hello world")}});
    manager.syncLyricsState(QStringLiteral("track-42"), true, sampleLines);
    CHECK(api->lyricsTrackId() == QStringLiteral("track-42"));
    CHECK(api->lyricsSynced());
    CHECK(api->lyricsLines().size() == 1);
    CHECK(api->setLyricSubtitles(QStringLiteral("track-42"), QVariantList{QStringLiteral("Привет мир")}));
    CHECK(manager.lyricSubtitleFor(QStringLiteral("track-42"), 0) == QStringLiteral("Привет мир"));

    // Multi-slot lookup
    const QVariantList pageSlots = manager.slotEntries(QStringLiteral("sidebar.page"));
    CHECK(pageSlots.size() == 2);
    CHECK(pageSlots.at(0).toMap().value(QStringLiteral("entryId")).toString() == QStringLiteral("demo-mod:main"));
    CHECK(pageSlots.at(1).toMap().value(QStringLiteral("entryId")).toString() == QStringLiteral("demo-mod:stats"));
    CHECK(pageSlots.at(1).toMap().value(QStringLiteral("title")).toString() == QStringLiteral("Демо 2"));

    const QVariantList tabSlots = manager.slotEntries(QStringLiteral("settings.tab"));
    CHECK(tabSlots.size() == 1);
    CHECK(tabSlots.first().toMap().value(QStringLiteral("title")).toString() == QStringLiteral("Демо-глава"));
    CHECK(tabSlots.first().toMap().value(QStringLiteral("settingsTabTitle")).toString() == QStringLiteral("Демо-глава"));
    CHECK(tabSlots.first().toMap().value(QStringLiteral("shape")).toString() == QStringLiteral("gem"));
    CHECK(manager.slotEntries(QStringLiteral("settings.section.player")).size() == 1);
    CHECK(manager.slotEntries(QStringLiteral("playerBar.controls")).size() == 1);
    const QVariantList immPanels = manager.slotEntries(QStringLiteral("immersive.panel"));
    CHECK(immPanels.size() == 1);
    CHECK(immPanels.first().toMap().value(QStringLiteral("symbol")).toString() == QStringLiteral("auto_awesome"));

    // Rapid reload lifecycle (leak/dangling-action/subtitle safety)
    for (int i = 0; i < 20; ++i) {
        manager.reloadMods();
        QCoreApplication::processEvents();
    }
    CHECK(manager.activeModCount() == 1);
    CHECK(manager.trackMenuActionsVariantList().isEmpty()); // Cleared automatically when ModApi recreated
    CHECK(manager.lyricSubtitleFor(QStringLiteral("track-42"), 0).isEmpty()); // Subtitles cleared automatically
    CHECK(manager.shortcutsVariantList().size() == 1); // Declarative shortcut restored after reload

    // Load order & override conflict priority (higher in list wins)
    const QString secondModDir = ymusic::paths::modsDirectory() + QStringLiteral("/zeta-mod");
    CHECK(writeText(secondModDir + QStringLiteral("/overrides/BarZ.qml"), "import QtQuick\nItem {}\n"));
    CHECK(writeText(secondModDir + QStringLiteral("/manifest.json"), R"({
        "id": "zeta-mod",
        "name": "Zeta Mod",
        "version": "1.0.0",
        "apiVersion": 1,
        "permissions": ["ui:override"],
        "overrides": { "qml/player/FloatingPlayerBar.qml": "overrides/BarZ.qml" }
    })"));
    manager.reloadMods();
    manager.setModEnabled(QStringLiteral("zeta-mod"), true);
    // demo-mod comes before zeta-mod alphabetically, so demo-mod wins initially
    CHECK(manager.urlInterceptor()->intercept(
        QUrl(QStringLiteral("qrc:/qt/qml/ymusic/ui/qml/player/FloatingPlayerBar.qml")),
        QQmlAbstractUrlInterceptor::QmlFile).toLocalFile().endsWith(QStringLiteral("/overrides/Bar.qml")));
    // Move zeta-mod UP -> zeta-mod now has higher priority and wins!
    manager.moveMod(QStringLiteral("zeta-mod"), -1);
    CHECK(manager.urlInterceptor()->intercept(
        QUrl(QStringLiteral("qrc:/qt/qml/ymusic/ui/qml/player/FloatingPlayerBar.qml")),
        QQmlAbstractUrlInterceptor::QmlFile).toLocalFile().endsWith(QStringLiteral("/overrides/BarZ.qml")));

    // Install mod from .ymmod ZIP archive (using built-in QZipReader, plus zip-slip/symlink/limit rejection)
    const QString ymmodPath = tmpDir.path() + QStringLiteral("/zip-mod.ymmod");
    {
        QZipWriter writer(ymmodPath);
        writer.addFile(QStringLiteral("zip-mod/manifest.json"), R"({
            "id": "zip-mod",
            "name": "Zip Mod",
            "version": "1.0.0",
            "apiVersion": "1.0",
            "permissions": ["ui:slots"]
        })");
        writer.close();
    }
    {
        const QVariantMap zipRes = manager.installModFromArchive(QUrl::fromLocalFile(ymmodPath));
        CHECK(zipRes.value(QStringLiteral("ok")).toBool());
        CHECK(zipRes.value(QStringLiteral("id")).toString() == QStringLiteral("zip-mod"));
    }

    // Archive zip-slip rejection
    const QString slipPath = tmpDir.path() + QStringLiteral("/slip.ymmod");
    {
        QZipWriter writer(slipPath);
        writer.addFile(QStringLiteral("../escape.txt"), "pwned");
        writer.close();
    }
    CHECK(!manager.installModFromArchive(QUrl::fromLocalFile(slipPath)).value(QStringLiteral("ok")).toBool());

    // Archive symlink rejection
    const QString symPath = tmpDir.path() + QStringLiteral("/sym.ymmod");
    {
        QZipWriter writer(symPath);
        writer.addSymLink(QStringLiteral("link-mod/evil"), QStringLiteral("/etc/passwd"));
        writer.close();
    }
    CHECK(!manager.installModFromArchive(QUrl::fromLocalFile(symPath)).value(QStringLiteral("ok")).toBool());

    // Archive file count limit (> 2000 files) rejection
    const QString manyFilesPath = tmpDir.path() + QStringLiteral("/many.ymmod");
    {
        QZipWriter writer(manyFilesPath);
        for (int i = 0; i < 2005; ++i) {
            writer.addFile(QStringLiteral("m/f%1.txt").arg(i), "x");
        }
        writer.close();
    }
    CHECK(!manager.installModFromArchive(QUrl::fromLocalFile(manyFilesPath)).value(QStringLiteral("ok")).toBool());

    // Archive uncompressed size limit (> 50 MB) rejection
    const QString hugePath = tmpDir.path() + QStringLiteral("/huge.ymmod");
    {
        QZipWriter writer(hugePath);
        QByteArray chunk(1024 * 1024, 'A'); // 1 MB highly compressible
        for (int i = 0; i < 52; ++i) {
            writer.addFile(QStringLiteral("h/part%1.bin").arg(i), chunk);
        }
        writer.close();
    }
    CHECK(!manager.installModFromArchive(QUrl::fromLocalFile(hugePath)).value(QStringLiteral("ok")).toBool());

    // apiVersion semver checks: incompatible major -> rejected; missing -> valid with warning; "1.0" -> valid
    const QString badApiDir = ymusic::paths::modsDirectory() + QStringLiteral("/bad-api-mod");
    CHECK(writeText(badApiDir + QStringLiteral("/manifest.json"), R"({
        "id": "bad-api-mod",
        "name": "Bad API",
        "version": "1.0.0",
        "apiVersion": "2.0",
        "permissions": ["ui:slots"]
    })"));
    CHECK(!parseManifest(badApiDir).valid);
    QDir(badApiDir).removeRecursively();

    const QString noApiDir = ymusic::paths::modsDirectory() + QStringLiteral("/no-api-mod");
    CHECK(writeText(noApiDir + QStringLiteral("/manifest.json"), R"({
        "id": "no-api-mod",
        "name": "No API",
        "version": "1.0.0",
        "permissions": ["ui:slots"]
    })"));
    const ModManifest noApiParsed = parseManifest(noApiDir);
    CHECK(noApiParsed.valid);
    CHECK(!noApiParsed.warnings.isEmpty());
    QDir(noApiDir).removeRecursively();

    // Sandbox isolation tests:
    //  a) No access to backend / appSettings / Backend / AppSettings; has modApi + ymusic.sdk Theme
    //  b) import ymusic.ui is rejected
    //  c) XMLHttpRequest to disallowed host is blocked; to allowed local server succeeds
    //  d) openExternalUrl requires 'external' permission
    QTcpServer httpServer;
    CHECK(httpServer.listen(QHostAddress::LocalHost, 0));
    const quint16 port = httpServer.serverPort();
    QObject::connect(&httpServer, &QTcpServer::newConnection, &httpServer, [&]() {
        while (QTcpSocket *sock = httpServer.nextPendingConnection()) {
            QObject::connect(sock, &QTcpSocket::readyRead, sock, [sock]() {
                sock->readAll();
                sock->write("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK");
                sock->flush();
                sock->disconnectFromHost();
            });
            QObject::connect(sock, &QTcpSocket::disconnected, sock, &QObject::deleteLater);
        }
    });

    const QString sbModDir = ymusic::paths::modsDirectory() + QStringLiteral("/sandbox-mod");
    CHECK(writeText(sbModDir + QStringLiteral("/manifest.json"), R"({
        "id": "sandbox-mod",
        "name": "Sandbox Mod",
        "version": "1.0.0",
        "apiVersion": "1.0",
        "permissions": ["ui:slots", "network:127.0.0.1"]
    })"));
    CHECK(writeText(sbModDir + QStringLiteral("/good.qml"), R"(
        import QtQuick
        import ymusic.sdk 1.0
        QtObject {
            property var modApi: null
            property var slotContext: ({})
            property bool backendHidden: typeof backend === "undefined" && typeof Backend === "undefined"
            property bool settingsHidden: typeof appSettings === "undefined" && typeof AppSettings === "undefined"
            property bool hasApi: modApi !== null && modApi.modId === "sandbox-mod"
            property bool hasSdkTheme: Theme.colors !== null && Theme.fontSize.normal === 14
        }
    )"));
    CHECK(writeText(sbModDir + QStringLiteral("/bad_import.qml"), R"(
        import QtQuick
        import ymusic.ui
        QtObject {}
    )"));
    CHECK(writeText(sbModDir + QStringLiteral("/xhr_test.qml"), QStringLiteral(R"(
        import QtQuick
        QtObject {
            property int allowedStatus: -1
            property string allowedBody: ""
            property bool blockedFailed: false
            property bool doneAllowed: false
            property bool doneBlocked: false
            Component.onCompleted: {
                var okReq = new XMLHttpRequest();
                okReq.onreadystatechange = function() {
                    if (okReq.readyState === XMLHttpRequest.DONE) {
                        allowedStatus = okReq.status;
                        allowedBody = okReq.responseText;
                        doneAllowed = true;
                    }
                };
                okReq.open("GET", "http://127.0.0.1:%1/ping");
                okReq.send();

                var badReq = new XMLHttpRequest();
                badReq.onreadystatechange = function() {
                    if (badReq.readyState === XMLHttpRequest.DONE) {
                        blockedFailed = (badReq.status === 0);
                        doneBlocked = true;
                    }
                };
                badReq.open("GET", "https://disallowed.example.invalid/steal");
                badReq.send();
            }
        }
    )").arg(port).toUtf8()));

    manager.reloadMods();
    manager.setModEnabled(QStringLiteral("sandbox-mod"), true);

    ModApi *sbApi = manager.apiForMod(QStringLiteral("sandbox-mod"));
    CHECK(sbApi != nullptr);
    CHECK(!sbApi->openExternalUrl(QStringLiteral("https://example.com"))); // missing 'external'

    QString sbErr;
    std::unique_ptr<QObject> goodObj(manager.createSandboxedObject(
        QStringLiteral("sandbox-mod"),
        QUrl::fromLocalFile(sbModDir + QStringLiteral("/good.qml")),
        {{QStringLiteral("k"), 1}},
        &sbErr));
    CHECK(goodObj != nullptr);
    CHECK(goodObj->property("backendHidden").toBool());
    CHECK(goodObj->property("settingsHidden").toBool());
    CHECK(goodObj->property("hasApi").toBool());
    CHECK(goodObj->property("hasSdkTheme").toBool());

    QString badImportErr;
    std::unique_ptr<QObject> badImportObj(manager.createSandboxedObject(
        QStringLiteral("sandbox-mod"),
        QUrl::fromLocalFile(sbModDir + QStringLiteral("/bad_import.qml")),
        {},
        &badImportErr));
    CHECK(badImportObj == nullptr);
    CHECK(!badImportErr.isEmpty());

    QString xhrErr;
    std::unique_ptr<QObject> xhrObj(manager.createSandboxedObject(
        QStringLiteral("sandbox-mod"),
        QUrl::fromLocalFile(sbModDir + QStringLiteral("/xhr_test.qml")),
        {},
        &xhrErr));
    CHECK(xhrObj != nullptr);
    QElapsedTimer waitTimer;
    waitTimer.start();
    while (waitTimer.elapsed() < 5000
           && (!xhrObj->property("doneAllowed").toBool() || !xhrObj->property("doneBlocked").toBool())) {
        QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
    }
    CHECK(xhrObj->property("doneAllowed").toBool());
    CHECK(xhrObj->property("allowedStatus").toInt() == 200);
    CHECK(xhrObj->property("allowedBody").toString() == QStringLiteral("OK"));
    CHECK(xhrObj->property("doneBlocked").toBool());
    CHECK(xhrObj->property("blockedFailed").toBool());
    xhrObj.reset();
    goodObj.reset();
    manager.setModEnabled(QStringLiteral("sandbox-mod"), false);

    // Quarantine disables override mods
    manager.quarantineOverrideMods(QStringLiteral("simulated crash"));
    CHECK(manager.activeOverrideCount() == 0);
    CHECK(manager.activeModCount() == 0);

    // Catalog & audio override permissions gating
    const QString overrideModDir = ymusic::paths::modsDirectory() + QStringLiteral("/catalog-mod");
    CHECK(writeText(overrideModDir + QStringLiteral("/manifest.json"), R"({
        "id": "catalog-mod",
        "name": "Catalog Override Mod",
        "version": "1.0.0",
        "apiVersion": 1,
        "permissions": ["catalog:override", "audio:override"]
    })"));
    manager.reloadMods();
    manager.setModEnabled(QStringLiteral("catalog-mod"), true);
    ModApi *catApi = manager.apiForMod(QStringLiteral("catalog-mod"));
    CHECK(catApi != nullptr);
    QVariantMap overrides;
    QVariantMap trackOv;
    trackOv.insert(QStringLiteral("title"), QStringLiteral("Uncensored Title"));
    trackOv.insert(QStringLiteral("audioUrl"), QStringLiteral("https://cdn.example.com/track.mp3"));
    overrides.insert(QStringLiteral("12345"), trackOv);
    CHECK(catApi->setTrackOverrides(overrides));
    QVariantList injected;
    QVariantMap extraTrack;
    extraTrack.insert(QStringLiteral("id"), QStringLiteral("99999"));
    extraTrack.insert(QStringLiteral("title"), QStringLiteral("Restored Track"));
    injected.append(extraTrack);
    CHECK(catApi->setAlbumInjections(QStringLiteral("555"), injected));
    catApi->clearTrackOverrides();
    manager.setModEnabled(QStringLiteral("catalog-mod"), false);

    // Safe mode never activates mods or overrides
    manager.setModEnabled(QStringLiteral("demo-mod"), true);
    ModManager safeManager(&settings, nullptr, nullptr, true);
    CHECK(safeManager.safeMode());
    CHECK(safeManager.activeModCount() == 0);
    CHECK(safeManager.activeOverrideCount() == 0);

    // --- B2/B3/B4 Logic mods (main.js, hooks, permissions, watchdog, auto-disable, dependencies) ---
    // 1. Dependency validation: missing dep -> invalid
    const QString missingDepDir = ymusic::paths::modsDirectory() + QStringLiteral("/needs-missing");
    CHECK(writeText(missingDepDir + QStringLiteral("/main.js"), "function activate(ym) {}\n"));
    CHECK(writeText(missingDepDir + QStringLiteral("/manifest.json"), R"({
        "id": "needs-missing",
        "name": "Needs Missing",
        "version": "1.0.0",
        "apiVersion": "1.0",
        "main": "main.js",
        "dependencies": { "nonexistent-lib": ">=1.0" },
        "permissions": []
    })"));
    manager.reloadMods();
    {
        bool foundInvalid = false;
        for (const QVariant &v : manager.modsVariantList()) {
            const QVariantMap m = v.toMap();
            if (m.value(QStringLiteral("id")).toString() == QStringLiteral("needs-missing")) {
                CHECK(!m.value(QStringLiteral("valid")).toBool());
                foundInvalid = true;
            }
        }
        CHECK(foundInvalid);
    }
    QDir(missingDepDir).removeRecursively();

    // 2. Topological dependency activation order + ym.exports / ym.require + hooks + permission denial
    const QString depBaseDir = ymusic::paths::modsDirectory() + QStringLiteral("/z-dep-base");
    CHECK(writeText(depBaseDir + QStringLiteral("/main.js"), R"(
        export function activate(ym) {
            ym.exports.tag = "from-base";
            ym.hooks.on("search_results", function(p) {
                p.byBase = true;
                return p;
            });
        }
    )"));
    CHECK(writeText(depBaseDir + QStringLiteral("/manifest.json"), R"({
        "id": "z-dep-base",
        "name": "Base Lib",
        "version": "1.2.0",
        "apiVersion": "1.0",
        "main": "main.js",
        "permissions": ["hooks:search_results"]
    })"));

    const QString depChildDir = ymusic::paths::modsDirectory() + QStringLiteral("/a-dep-child");
    CHECK(writeText(depChildDir + QStringLiteral("/main.js"), R"(
        export function activate(ym) {
            const base = ym.require("z-dep-base");
            ym.exports.sawBase = (base && base.tag === "from-base");
            // Should be denied because hooks:wave_next_batch is NOT granted
            ym.exports.deniedWave = !ym.hooks.on("wave_next_batch", function(p) { return p; });
            // Allowed hook
            ym.hooks.on("search_results", function(p) {
                p.byChild = true;
                return p;
            });
            ym.hooks.on("queue_before_add", function(p) {
                if (p && p.blockMe) return ym.cancel("blocked-by-child");
                return p;
            });
        }
    )"));
    CHECK(writeText(depChildDir + QStringLiteral("/manifest.json"), R"({
        "id": "a-dep-child",
        "name": "Child Consumer",
        "version": "1.0.0",
        "apiVersion": "1.0",
        "main": "main.js",
        "dependencies": { "z-dep-base": ">=1.0" },
        "permissions": ["hooks:search_results", "hooks:queue_before_add"]
    })"));

    manager.reloadMods();
    manager.setModEnabled(QStringLiteral("a-dep-child"), true);
    manager.setModEnabled(QStringLiteral("z-dep-base"), true);

    // Even though "a-dep-child" sorts before "z-dep-base", z-dep-base MUST activate first!
    const QStringList order = manager.activationOrder();
    CHECK(order.indexOf(QStringLiteral("z-dep-base")) >= 0);
    CHECK(order.indexOf(QStringLiteral("a-dep-child")) > order.indexOf(QStringLiteral("z-dep-base")));

    const QVariantMap childExports = manager.modExports(QStringLiteral("a-dep-child")).toMap();
    CHECK(childExports.value(QStringLiteral("sawBase")).toBool());
    CHECK(childExports.value(QStringLiteral("deniedWave")).toBool());

    // Hook chain transformation
    const QVariantMap hookRes = manager.runHookChain(
        QStringLiteral("search_results"),
        QVariantMap{{QStringLiteral("q"), QStringLiteral("test")}});
    CHECK(hookRes.value(QStringLiteral("action")).toString() == QStringLiteral("continue"));
    const QVariantMap hookPayload = hookRes.value(QStringLiteral("payload")).toMap();
    CHECK(hookPayload.value(QStringLiteral("byBase")).toBool());
    CHECK(hookPayload.value(QStringLiteral("byChild")).toBool());

    // Hook cancel
    const QVariantMap cancelRes = manager.runHookChain(
        QStringLiteral("queue_before_add"),
        QVariantMap{{QStringLiteral("blockMe"), true}});
    CHECK(cancelRes.value(QStringLiteral("action")).toString() == QStringLiteral("cancel"));
    CHECK(cancelRes.value(QStringLiteral("reason")).toString() == QStringLiteral("blocked-by-child"));

    manager.setModEnabled(QStringLiteral("a-dep-child"), false);
    manager.setModEnabled(QStringLiteral("z-dep-base"), false);

    // 3. Watchdog interrupts infinite loop & auto-disables after 5 consecutive errors
    const QString hangModDir = ymusic::paths::modsDirectory() + QStringLiteral("/hang-mod");
    CHECK(writeText(hangModDir + QStringLiteral("/main.js"), R"(
        export function activate(ym) {
            ym.hooks.on("search_results", function(p) {
                if (p && p.hang) {
                    while (true) {}
                }
                if (p && p.crash) {
                    throw new Error("boom");
                }
                return p;
            });
        }
    )"));
    CHECK(writeText(hangModDir + QStringLiteral("/manifest.json"), R"({
        "id": "hang-mod",
        "name": "Hang Mod",
        "version": "1.0.0",
        "apiVersion": "1.0",
        "main": "main.js",
        "permissions": ["hooks:search_results"]
    })"));
    manager.reloadMods();
    manager.setModEnabled(QStringLiteral("hang-mod"), true);
    ModScriptHost *hangHost = manager.scriptHostForMod(QStringLiteral("hang-mod"));
    CHECK(hangHost != nullptr);
    hangHost->setWatchdogTimeoutMs(80);
    // 1st error: infinite loop interrupted by watchdog
    manager.runHookChain(QStringLiteral("search_results"), QVariantMap{{QStringLiteral("hang"), true}});
    CHECK(hangHost->consecutiveErrors() == 1);
    // 4 more errors -> reaches 5 consecutive errors -> auto-disabled!
    for (int i = 0; i < 4; ++i) {
        manager.runHookChain(QStringLiteral("search_results"), QVariantMap{{QStringLiteral("crash"), true}});
    }
    CHECK(hangHost->isAutoDisabled());
    QCoreApplication::processEvents();

    return 0;
}
