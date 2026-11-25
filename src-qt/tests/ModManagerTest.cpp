#include "AppSettings.h"
#include "app/Paths.h"
#include "mods/ModApi.h"
#include "mods/ModManager.h"
#include "mods/ModManifest.h"
#include "mods/ModUrlInterceptor.h"

#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QTemporaryDir>
#include <QUrl>

#include <iostream>

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

    // Install mod from .ymmod ZIP archive
    const QString archiveSrcDir = tmpDir.path() + QStringLiteral("/pack-src/zip-mod");
    CHECK(writeText(archiveSrcDir + QStringLiteral("/manifest.json"), R"({
        "id": "zip-mod",
        "name": "Zip Mod",
        "version": "1.0.0",
        "apiVersion": 1,
        "permissions": ["ui:slots"]
    })"));
    const QString ymmodPath = tmpDir.path() + QStringLiteral("/zip-mod.ymmod");
    QProcess zipProc;
    zipProc.start(QStringLiteral("python3"), {
        QStringLiteral("-c"),
        QStringLiteral("import zipfile, sys; z=zipfile.ZipFile(sys.argv[1],'w'); z.write(sys.argv[2],'zip-mod/manifest.json'); z.close()"),
        ymmodPath,
        archiveSrcDir + QStringLiteral("/manifest.json")
    });
    if (zipProc.waitForFinished(5000) && zipProc.exitCode() == 0) {
        const QVariantMap zipRes = manager.installModFromArchive(QUrl::fromLocalFile(ymmodPath));
        CHECK(zipRes.value(QStringLiteral("ok")).toBool());
        CHECK(zipRes.value(QStringLiteral("id")).toString() == QStringLiteral("zip-mod"));
    }

    // Quarantine disables override mods
    manager.quarantineOverrideMods(QStringLiteral("simulated crash"));
    CHECK(manager.activeOverrideCount() == 0);
    CHECK(manager.activeModCount() == 0);

    // Safe mode never activates mods or overrides
    manager.setModEnabled(QStringLiteral("demo-mod"), true);
    ModManager safeManager(&settings, nullptr, nullptr, true);
    CHECK(safeManager.safeMode());
    CHECK(safeManager.activeModCount() == 0);
    CHECK(safeManager.activeOverrideCount() == 0);

    return 0;
}
