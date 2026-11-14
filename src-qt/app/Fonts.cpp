#include "app/Fonts.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QFontDatabase>
#include <QLoggingCategory>

namespace ymusic::fonts {

Q_LOGGING_CATEGORY(lcFonts, "ymusic.fonts")

namespace {

constexpr auto kIconFamily = "Material Symbols Rounded";
constexpr auto kIconFile = "MaterialSymbolsRounded.ttf";
constexpr auto kInterfaceFamily = "Google Sans Flex";
constexpr auto kInterfaceFile = "GoogleSansFlex.ttf";

bool loadBundled(const char *family, const char *file, const char *systemFallbackPath = nullptr)
{
    if (QFontDatabase::families().contains(QLatin1StringView(family))) {
        return true;
    }
    const QString applicationDirectory = QCoreApplication::applicationDirPath();
    const QStringList candidates {
        applicationDirectory + QStringLiteral("/../share/ymusic/fonts/"),
        applicationDirectory + QStringLiteral("/../Resources/fonts/"),
        applicationDirectory + QStringLiteral("/fonts/"),
#ifdef YMUSIC_BUILD_FONT_DIRECTORY
        QStringLiteral(YMUSIC_BUILD_FONT_DIRECTORY "/"),
#endif
    };
    for (const QString &directory : candidates) {
        const QString path = QDir::cleanPath(directory + QLatin1StringView(file));
        if (QFileInfo::exists(path) && QFontDatabase::addApplicationFont(path) >= 0) {
            return true;
        }
    }
    if (systemFallbackPath) {
        const QString path = QString::fromUtf8(systemFallbackPath);
        if (QFileInfo::exists(path) && QFontDatabase::addApplicationFont(path) >= 0) {
            return true;
        }
    }
    return false;
}

} // namespace

void loadIconFont()
{
    if (!loadBundled(kIconFamily, kIconFile,
                     "/usr/share/fonts/ttf-material-symbols-variable/MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf")) {
        qCWarning(lcFonts) << "Material Symbols Rounded is not installed; icons will show as text";
    }
}

void loadInterfaceFont()
{
    if (!loadBundled(kInterfaceFamily, kInterfaceFile)) {
        qCInfo(lcFonts) << "Google Sans Flex is not installed; falling back to system UI font";
    }
}

QString iconFamily()
{
    return QString::fromLatin1(kIconFamily);
}

QString interfaceFamily()
{
    static const QString family = [] {
        const QStringList installed = QFontDatabase::families();
        for (const auto *candidate : {"Google Sans Flex", "Google Sans", "Rubik", "Inter", "Noto Sans"}) {
            if (installed.contains(QLatin1StringView(candidate))) {
                return QString::fromLatin1(candidate);
            }
        }
        return QFontDatabase::systemFont(QFontDatabase::GeneralFont).family();
    }();
    return family;
}

QString fixedFamily()
{
    static const QString family = QFontDatabase::systemFont(QFontDatabase::FixedFont).family();
    return family;
}

} // namespace ymusic::fonts
