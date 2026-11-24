#include "AppSettings.h"
#include "theme/Theme.h"

#include <QBuffer>
#include <QGuiApplication>
#include <QImage>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QUrl>

#include <iostream>

using ymusic::MaterialScheme;
using ymusic::Theme;

#define CHECK(cond)                                                                         \
    do {                                                                                    \
        if (!(cond)) {                                                                      \
            std::cerr << "Check failed at line " << __LINE__ << ": " #cond << std::endl;    \
            return 1;                                                                       \
        }                                                                                   \
    } while (false)

int main(int argc, char *argv[]) {
    QTemporaryDir tmpDir;
    if (!tmpDir.isValid()) return 1;
    qputenv("HOME", tmpDir.path().toUtf8());
    qputenv("XDG_DATA_HOME", (tmpDir.path() + QStringLiteral("/data")).toUtf8());
    qputenv("XDG_CONFIG_HOME", (tmpDir.path() + QStringLiteral("/config")).toUtf8());
    QGuiApplication app(argc, argv);

    QImage img(64, 64, QImage::Format_ARGB32);
    img.fill(QColor(0x28, 0x74, 0xd8));
    QByteArray pngBytes;
    QBuffer buf(&pngBytes);
    CHECK(buf.open(QIODevice::WriteOnly));
    CHECK(img.save(&buf, "PNG"));

    const auto seed = Theme::wallpaperSeedFromBytes(pngBytes);
    CHECK(seed.has_value());
    CHECK(seed->isValid());
    CHECK(seed->blue() > seed->red());

    const auto darkRoles = Theme::rolesFromSeed(*seed, true, false);
    const auto lightRoles = Theme::rolesFromSeed(*seed, false, false);
    const QColor darkBg = darkRoles[static_cast<std::size_t>(MaterialScheme::Role::Background)];
    const QColor lightBg = lightRoles[static_cast<std::size_t>(MaterialScheme::Role::Background)];
    CHECK(darkBg.lightnessF() < 0.2);
    CHECK(lightBg.lightnessF() > 0.8);

    const auto expressive = Theme::rolesFromSeed(*seed, true, QStringLiteral("expressive"));
    const auto monochrome = Theme::rolesFromSeed(*seed, true, QStringLiteral("monochrome"));
    CHECK(expressive[static_cast<std::size_t>(MaterialScheme::Role::Primary)]
          != monochrome[static_cast<std::size_t>(MaterialScheme::Role::Primary)]);

    CHECK(!Theme::wallpaperSeedFromBytes(QByteArray("not-an-image")).has_value());

    AppSettings settings;
    Theme theme(&settings);
    settings.setThemePreset(QStringLiteral("custom"));
    settings.setThemeMode(QStringLiteral("dark"));
    settings.setCustomAccentColor(QStringLiteral("#3b82f6"));
    settings.setCustomSchemeVariant(QStringLiteral("vibrant"));
    settings.setRoundingScale(1.35);
    settings.setSurfaceOpacity(0.85);
    settings.setWindowBackgroundBlur(24.0);

    const QString exportedPath = tmpDir.path() + QStringLiteral("/neon.ymtheme");
    const QVariantMap exportRes = theme.exportThemeFile(QUrl::fromLocalFile(exportedPath));
    CHECK(exportRes.value(QStringLiteral("ok")).toBool());

    theme.resetThemeDefaults();
    CHECK(qFuzzyCompare(settings.roundingScale(), 1.0));
    CHECK(qFuzzyCompare(settings.surfaceOpacity(), 1.0));

    const QVariantMap importRes = theme.importThemeFile(QUrl::fromLocalFile(exportedPath), true);
    CHECK(importRes.value(QStringLiteral("ok")).toBool());
    CHECK(settings.customAccentColor() == QStringLiteral("#3b82f6"));
    CHECK(settings.customSchemeVariant() == QStringLiteral("vibrant"));
    CHECK(qFuzzyCompare(settings.roundingScale(), 1.35));
    CHECK(qFuzzyCompare(settings.surfaceOpacity(), 0.85));
    CHECK(qFuzzyCompare(settings.windowBackgroundBlur(), 24.0));
    CHECK(settings.themePreset().startsWith(QStringLiteral("user:")));

    CHECK(theme.deleteUserTheme(settings.themePreset()));
    CHECK(settings.themePreset() == QStringLiteral("custom"));

    return 0;
}
