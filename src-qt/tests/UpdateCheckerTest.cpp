#include "app/UpdateChecker.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QTemporaryFile>
#include <QtGlobal>

#include <iostream>

using ymusic::UpdateChecker;

#define CHECK(cond)                                                                         \
    do {                                                                                    \
        if (!(cond)) {                                                                      \
            std::cerr << "Check failed at line " << __LINE__ << ": " #cond << std::endl;    \
            return 1;                                                                       \
        }                                                                                   \
    } while (false)

int main(int argc, char *argv[]) {
    QCoreApplication app(argc, argv);

    // Semver parsing and ordering
    CHECK(UpdateChecker::isNewerVersion("0.2.3", "0.2.2"));
    CHECK(UpdateChecker::isNewerVersion("v0.3.0", "0.2.2"));
    CHECK(UpdateChecker::isNewerVersion("1.0.0", "0.9.9"));
    CHECK(!UpdateChecker::isNewerVersion("0.2.2", "0.2.2"));
    CHECK(!UpdateChecker::isNewerVersion("0.2.1", "0.2.2"));
    CHECK(!UpdateChecker::isNewerVersion("0.2.3-rc1", "0.2.3"));
    CHECK(UpdateChecker::isNewerVersion("0.2.3", "0.2.3-rc1"));
    CHECK(!UpdateChecker::isNewerVersion("invalid", "0.2.2"));

    const QUrl prodManifest("https://github.com/ethermawe/ymusic/releases/latest/download/latest-windows.json");
    const QString validSha = QString(64, QLatin1Char('a'));

    // Valid manifest
    {
        const QByteArray json = QStringLiteral(
            R"({"version":"0.2.3","tag":"v0.2.3","url":"https://github.com/ethermawe/ymusic/releases/download/v0.2.3/ymusic-v0.2.3-windows-x86_64-setup.exe","sha256":"%1","notes_url":"https://github.com/ethermawe/ymusic/releases/tag/v0.2.3"})")
            .arg(validSha)
            .toUtf8();
        QString err;
        const auto m = UpdateChecker::parseManifest(json, prodManifest, &err);
        CHECK(m.has_value());
        CHECK(m->version == "0.2.3");
        CHECK(m->tag == "v0.2.3");
        CHECK(m->sha256 == validSha);
    }

    // Reject untrusted host or insecure HTTP in production
    {
        const QByteArray evilJson = QStringLiteral(
            R"({"version":"0.2.3","url":"https://evil.example.com/setup.exe","sha256":"%1"})")
            .arg(validSha)
            .toUtf8();
        CHECK(!UpdateChecker::parseManifest(evilJson, prodManifest).has_value());

        const QByteArray httpJson = QStringLiteral(
            R"({"version":"0.2.3","url":"http://github.com/ethermawe/ymusic/releases/download/v0.2.3/setup.exe","sha256":"%1"})")
            .arg(validSha)
            .toUtf8();
        CHECK(!UpdateChecker::parseManifest(httpJson, prodManifest).has_value());
    }

    // Reject malformed SHA-256
    {
        const QByteArray badShaJson =
            R"({"version":"0.2.3","url":"https://github.com/ethermawe/ymusic/releases/download/v0.2.3/setup.exe","sha256":"deadbeef"})";
        CHECK(!UpdateChecker::parseManifest(badShaJson, prodManifest).has_value());
    }

    // SHA-256 helper
    {
        QTemporaryFile tmp;
        CHECK(tmp.open());
        const QByteArray payload("ymusic-installer-payload");
        CHECK(tmp.write(payload) == payload.size());
        CHECK(tmp.flush());
        const QString expected = QString::fromLatin1(
            QCryptographicHash::hash(payload, QCryptographicHash::Sha256).toHex());
        CHECK(UpdateChecker::fileSha256(tmp.fileName()) == expected);
    }

    return 0;
}
