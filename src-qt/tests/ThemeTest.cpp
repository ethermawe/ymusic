#include "theme/Theme.h"

#include <QBuffer>
#include <QGuiApplication>
#include <QImage>

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

    CHECK(!Theme::wallpaperSeedFromBytes(QByteArray("not-an-image")).has_value());

    return 0;
}
