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

    // 4. Valid mod with slots, storage, override, and network allowlist
    const QString goodModDir = ymusic::paths::modsDirectory() + QStringLiteral("/demo-mod");
    CHECK(writeText(goodModDir + QStringLiteral("/ui/Page.qml"), "import QtQuick\nItem {}\n"));
    CHECK(writeText(goodModDir + QStringLiteral("/overrides/Bar.qml"), "import QtQuick\nItem {}\n"));
    CHECK(writeText(goodModDir + QStringLiteral("/manifest.json"), R"({
        "id": "demo-mod",
        "name": "Demo Mod",
        "version": "1.2.3",
        "author": "Tester",
        "apiVersion": 1,
        "permissions": ["playback:read", "ui:slots", "ui:override", "storage", "network:api.example.com"],
        "sidebar": { "title": "Демо", "symbol": "extension" },
        "slots": { "sidebar.page": "ui/Page.qml" },
        "overrides": { "qml/player/FloatingPlayerBar.qml": "overrides/Bar.qml" }
    })"));

    AppSettings settings;
    ModManager manager(&settings, nullptr, nullptr, false);
    CHECK(manager.modsVariantList().size() == 1);
    CHECK(manager.activeModCount() == 0);
    CHECK(manager.activeOverrideCount() == 0);

    // Enable mod
    manager.setModEnabled(QStringLiteral("demo-mod"), true);
    CHECK(manager.activeModCount() == 1);
    CHECK(manager.activeOverrideCount() == 1);
    CHECK(manager.overridesNeedRestart());

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

    // ModApi permission enforcement & storage isolation
    ModApi *api = manager.apiForMod(QStringLiteral("demo-mod"));
    CHECK(api != nullptr);
    CHECK(!api->toggle()); // playback:control not granted
    CHECK(!api->httpGet(QStringLiteral("https://evil.example.org/steal"), QStringLiteral("req1")));
    CHECK(api->storageSet(QStringLiteral("counter"), 42));
    CHECK(api->storageGet(QStringLiteral("counter")).toInt() == 42);
    CHECK(api->registerTrackMenuAction(QStringLiteral("open"), QStringLiteral("Открыть"), QStringLiteral("open_in_new"), false));
    CHECK(manager.trackMenuActionsVariantList().size() == 1);

    // Slot lookup
    const QVariantList pageSlots = manager.slotEntries(QStringLiteral("sidebar.page"));
    CHECK(pageSlots.size() == 1);
    CHECK(pageSlots.first().toMap().value(QStringLiteral("modId")).toString() == QStringLiteral("demo-mod"));

    // Rapid reload lifecycle (leak/dangling-action safety)
    for (int i = 0; i < 20; ++i) {
        manager.reloadMods();
        QCoreApplication::processEvents();
    }
    CHECK(manager.activeModCount() == 1);
    CHECK(manager.trackMenuActionsVariantList().isEmpty()); // Cleared automatically when ModApi recreated

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
