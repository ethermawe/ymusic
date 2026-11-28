#include "sdk/ModTheme.h"

#ifndef YMUSIC_SDK_HEADLESS
#include "AppSettings.h"
#include "theme/MaterialScheme.h"
#include "theme/Theme.h"
#endif

#include <QFontDatabase>
#include <QJSEngine>

#include <algorithm>
#include <cmath>

namespace ymusic::sdk {

namespace {
ModTheme *s_sdkTheme = nullptr;
} // namespace

SdkColors::SdkColors(QObject *parent)
    : QObject(parent)
{
    syncFromAppTheme();
}

void SdkColors::syncFromAppTheme()
{
#ifndef YMUSIC_SDK_HEADLESS
    ymusic::Theme *appTheme = ymusic::Theme::instance();
    if (!appTheme || !appTheme->colors()) {
        return;
    }
    const ymusic::MaterialScheme *c = appTheme->colors();
    m_dark = c->dark();
    m_primary = c->primary();
    m_onPrimary = c->onPrimary();
    m_primaryContainer = c->primaryContainer();
    m_primaryContainerHover = c->primaryContainerHover();
    m_onPrimaryContainer = c->onPrimaryContainer();
    m_secondary = c->secondary();
    m_secondaryContainer = c->secondaryContainer();
    m_tertiary = c->tertiary();
    m_tertiaryContainer = c->tertiaryContainer();
    m_onTertiaryContainer = c->onTertiaryContainer();
    m_surface = c->surface();
    m_surfaceContainer = c->surfaceContainer();
    m_surfaceContainerHigh = c->surfaceContainerHigh();
    m_surfaceContainerLowest = c->surfaceContainerLowest();
    m_onSurface = c->onSurface();
    m_onSurfaceVariant = c->onSurfaceVariant();
    m_outline = c->outline();
    m_outlineVariant = c->outlineVariant();
    m_error = c->error();
    m_errorContainer = c->errorContainer();
    m_onErrorContainer = c->onErrorContainer();
    m_layer0 = c->layer0();
    m_layer0Border = c->layer0Border();
    m_layer1 = c->layer1();
    m_layer2Hover = c->layer2Hover();
    emit changed();
#endif
}

ModTheme::ModTheme(QObject *parent)
    : QObject(parent)
    , m_colors(new SdkColors(this))
{
    bindToAppSingletons();
    sync();
}

ModTheme::~ModTheme()
{
    if (s_sdkTheme == this) {
        s_sdkTheme = nullptr;
    }
}

ModTheme *ModTheme::instance()
{
    if (!s_sdkTheme) {
        s_sdkTheme = new ModTheme();
    } else {
        s_sdkTheme->bindToAppSingletons();
    }
    return s_sdkTheme;
}

ModTheme *ModTheme::create(QQmlEngine *, QJSEngine *)
{
    ModTheme *inst = instance();
    QJSEngine::setObjectOwnership(inst, QJSEngine::CppOwnership);
    return inst;
}

void ModTheme::bindToAppSingletons()
{
#ifndef YMUSIC_SDK_HEADLESS
    if (m_bound) return;
    ymusic::Theme *appTheme = ymusic::Theme::instance();
    AppSettings *settings = AppSettings::instance();
    if (appTheme) {
        connect(appTheme, &ymusic::Theme::schemeChanged, this, &ModTheme::sync);
        m_bound = true;
    }
    if (settings) {
        connect(settings, &AppSettings::appearanceChanged, this, &ModTheme::sync);
        connect(settings, &AppSettings::reduceMotionChanged, this, &ModTheme::sync);
        connect(settings, &AppSettings::performanceModeChanged, this, &ModTheme::sync);
    }
#endif
}

void ModTheme::sync()
{
    m_colors->syncFromAppTheme();
    emit changed();
}

QString ModTheme::fontFamily() const
{
#ifndef YMUSIC_SDK_HEADLESS
    if (AppSettings *s = AppSettings::instance()) {
        const QString custom = s->customFontFamily().trimmed();
        if (!custom.isEmpty()) return custom;
    }
    if (ymusic::Theme *t = ymusic::Theme::instance()) {
        return t->fontFamily();
    }
#endif
    return QStringLiteral("Sans Serif");
}

QString ModTheme::monoFontFamily() const
{
#ifndef YMUSIC_SDK_HEADLESS
    if (ymusic::Theme *t = ymusic::Theme::instance()) {
        return t->monoFontFamily();
    }
#endif
    return QFontDatabase::systemFont(QFontDatabase::FixedFont).family();
}

bool ModTheme::reduceMotion() const
{
#ifndef YMUSIC_SDK_HEADLESS
    if (AppSettings *s = AppSettings::instance()) {
        return s->reduceMotion();
    }
#endif
    return false;
}

bool ModTheme::performanceMode() const
{
#ifndef YMUSIC_SDK_HEADLESS
    if (AppSettings *s = AppSettings::instance()) {
        return s->performanceMode();
    }
#endif
    return false;
}

QVariantMap ModTheme::rounding() const
{
    double scale = 1.0;
#ifndef YMUSIC_SDK_HEADLESS
    if (AppSettings *s = AppSettings::instance()) {
        scale = std::clamp(s->roundingScale(), 0.25, 2.0);
    }
#endif
    const auto r = [scale](double base) { return std::round(base * scale); };
    return {
        {QStringLiteral("verySmall"), r(6.0)},
        {QStringLiteral("small"), r(10.0)},
        {QStringLiteral("normal"), r(14.0)},
        {QStringLiteral("large"), r(20.0)},
        {QStringLiteral("veryLarge"), r(28.0)},
        {QStringLiteral("full"), 999.0},
    };
}

QVariantMap ModTheme::fontSize() const
{
    return {
        {QStringLiteral("smallest"), 11},
        {QStringLiteral("smaller"), 12},
        {QStringLiteral("small"), 13},
        {QStringLiteral("normal"), 14},
        {QStringLiteral("large"), 16},
        {QStringLiteral("title"), 20},
        {QStringLiteral("headline"), 24},
    };
}

QColor ModTheme::withAlpha(const QColor &color, qreal alpha) const
{
    QColor c = color;
    c.setAlphaF(static_cast<float>(std::clamp(alpha, 0.0, 1.0)));
    return c;
}

} // namespace ymusic::sdk
