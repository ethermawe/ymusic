#pragma once

#include <QColor>
#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class QJSEngine;
class QQmlEngine;

namespace ymusic::sdk {

/// Read-only color tokens exposed to mods via `ymusic.sdk` (`Theme.colors`).
class SdkColors : public QObject {
    Q_OBJECT
    QML_ANONYMOUS

    Q_PROPERTY(bool dark READ dark NOTIFY changed FINAL)
    Q_PROPERTY(QColor primary READ primary NOTIFY changed FINAL)
    Q_PROPERTY(QColor onPrimary READ onPrimary NOTIFY changed FINAL)
    Q_PROPERTY(QColor primaryContainer READ primaryContainer NOTIFY changed FINAL)
    Q_PROPERTY(QColor primaryContainerHover READ primaryContainerHover NOTIFY changed FINAL)
    Q_PROPERTY(QColor onPrimaryContainer READ onPrimaryContainer NOTIFY changed FINAL)
    Q_PROPERTY(QColor secondary READ secondary NOTIFY changed FINAL)
    Q_PROPERTY(QColor secondaryContainer READ secondaryContainer NOTIFY changed FINAL)
    Q_PROPERTY(QColor tertiary READ tertiary NOTIFY changed FINAL)
    Q_PROPERTY(QColor tertiaryContainer READ tertiaryContainer NOTIFY changed FINAL)
    Q_PROPERTY(QColor onTertiaryContainer READ onTertiaryContainer NOTIFY changed FINAL)
    Q_PROPERTY(QColor surface READ surface NOTIFY changed FINAL)
    Q_PROPERTY(QColor surfaceContainer READ surfaceContainer NOTIFY changed FINAL)
    Q_PROPERTY(QColor surfaceContainerHigh READ surfaceContainerHigh NOTIFY changed FINAL)
    Q_PROPERTY(QColor surfaceContainerLowest READ surfaceContainerLowest NOTIFY changed FINAL)
    Q_PROPERTY(QColor onSurface READ onSurface NOTIFY changed FINAL)
    Q_PROPERTY(QColor onSurfaceVariant READ onSurfaceVariant NOTIFY changed FINAL)
    Q_PROPERTY(QColor outline READ outline NOTIFY changed FINAL)
    Q_PROPERTY(QColor outlineVariant READ outlineVariant NOTIFY changed FINAL)
    Q_PROPERTY(QColor error READ error NOTIFY changed FINAL)
    Q_PROPERTY(QColor errorContainer READ errorContainer NOTIFY changed FINAL)
    Q_PROPERTY(QColor onErrorContainer READ onErrorContainer NOTIFY changed FINAL)
    Q_PROPERTY(QColor layer0 READ layer0 NOTIFY changed FINAL)
    Q_PROPERTY(QColor layer0Border READ layer0Border NOTIFY changed FINAL)
    Q_PROPERTY(QColor layer1 READ layer1 NOTIFY changed FINAL)
    Q_PROPERTY(QColor layer2Hover READ layer2Hover NOTIFY changed FINAL)

public:
    explicit SdkColors(QObject *parent = nullptr);

    bool dark() const { return m_dark; }
    QColor primary() const { return m_primary; }
    QColor onPrimary() const { return m_onPrimary; }
    QColor primaryContainer() const { return m_primaryContainer; }
    QColor primaryContainerHover() const { return m_primaryContainerHover; }
    QColor onPrimaryContainer() const { return m_onPrimaryContainer; }
    QColor secondary() const { return m_secondary; }
    QColor secondaryContainer() const { return m_secondaryContainer; }
    QColor tertiary() const { return m_tertiary; }
    QColor tertiaryContainer() const { return m_tertiaryContainer; }
    QColor onTertiaryContainer() const { return m_onTertiaryContainer; }
    QColor surface() const { return m_surface; }
    QColor surfaceContainer() const { return m_surfaceContainer; }
    QColor surfaceContainerHigh() const { return m_surfaceContainerHigh; }
    QColor surfaceContainerLowest() const { return m_surfaceContainerLowest; }
    QColor onSurface() const { return m_onSurface; }
    QColor onSurfaceVariant() const { return m_onSurfaceVariant; }
    QColor outline() const { return m_outline; }
    QColor outlineVariant() const { return m_outlineVariant; }
    QColor error() const { return m_error; }
    QColor errorContainer() const { return m_errorContainer; }
    QColor onErrorContainer() const { return m_onErrorContainer; }
    QColor layer0() const { return m_layer0; }
    QColor layer0Border() const { return m_layer0Border; }
    QColor layer1() const { return m_layer1; }
    QColor layer2Hover() const { return m_layer2Hover; }

    void syncFromAppTheme();

signals:
    void changed();

private:
    bool m_dark = true;
    QColor m_primary = QColor(QStringLiteral("#ffb4a4"));
    QColor m_onPrimary = QColor(QStringLiteral("#561e12"));
    QColor m_primaryContainer = QColor(QStringLiteral("#733426"));
    QColor m_primaryContainerHover = QColor(QStringLiteral("#853e2e"));
    QColor m_onPrimaryContainer = QColor(QStringLiteral("#ffdad3"));
    QColor m_secondary = QColor(QStringLiteral("#e7bdb4"));
    QColor m_secondaryContainer = QColor(QStringLiteral("#5d3f39"));
    QColor m_tertiary = QColor(QStringLiteral("#dec48c"));
    QColor m_tertiaryContainer = QColor(QStringLiteral("#564419"));
    QColor m_onTertiaryContainer = QColor(QStringLiteral("#fbe0a6"));
    QColor m_surface = QColor(QStringLiteral("#181211"));
    QColor m_surfaceContainer = QColor(QStringLiteral("#251e1d"));
    QColor m_surfaceContainerHigh = QColor(QStringLiteral("#302827"));
    QColor m_surfaceContainerLowest = QColor(QStringLiteral("#120d0c"));
    QColor m_onSurface = QColor(QStringLiteral("#ede0dd"));
    QColor m_onSurfaceVariant = QColor(QStringLiteral("#d8c2bd"));
    QColor m_outline = QColor(QStringLiteral("#a08c88"));
    QColor m_outlineVariant = QColor(QStringLiteral("#534340"));
    QColor m_error = QColor(QStringLiteral("#ffb4ab"));
    QColor m_errorContainer = QColor(QStringLiteral("#93000a"));
    QColor m_onErrorContainer = QColor(QStringLiteral("#ffdad6"));
    QColor m_layer0 = QColor(QStringLiteral("#181211"));
    QColor m_layer0Border = QColor(QStringLiteral("#382e2c"));
    QColor m_layer1 = QColor(QStringLiteral("#251e1d"));
    QColor m_layer2Hover = QColor(QStringLiteral("#382f2d"));
};

/// Read-only theme & design tokens singleton for `import ymusic.sdk 1.0`.
class ModTheme : public QObject {
    Q_OBJECT
    QML_NAMED_ELEMENT(Theme)
    QML_SINGLETON

    Q_PROPERTY(ymusic::sdk::SdkColors *colors READ colors CONSTANT FINAL)
    Q_PROPERTY(bool dark READ dark NOTIFY changed FINAL)
    Q_PROPERTY(QString fontFamily READ fontFamily NOTIFY changed FINAL)
    Q_PROPERTY(QString monoFontFamily READ monoFontFamily CONSTANT FINAL)
    Q_PROPERTY(QString iconFontFamily READ iconFontFamily CONSTANT FINAL)
    Q_PROPERTY(bool reduceMotion READ reduceMotion NOTIFY changed FINAL)
    Q_PROPERTY(bool performanceMode READ performanceMode NOTIFY changed FINAL)
    Q_PROPERTY(QVariantMap rounding READ rounding NOTIFY changed FINAL)
    Q_PROPERTY(QVariantMap fontSize READ fontSize CONSTANT FINAL)

public:
    explicit ModTheme(QObject *parent = nullptr);
    ~ModTheme() override;

    static ModTheme *instance();
    static ModTheme *create(QQmlEngine *, QJSEngine *);

    SdkColors *colors() const { return m_colors; }
    bool dark() const { return m_colors->dark(); }
    QString fontFamily() const;
    QString monoFontFamily() const;
    QString iconFontFamily() const { return QStringLiteral("Material Symbols Rounded"); }
    bool reduceMotion() const;
    bool performanceMode() const;
    QVariantMap rounding() const;
    QVariantMap fontSize() const;

    Q_INVOKABLE QColor withAlpha(const QColor &color, qreal alpha) const;

signals:
    void changed();

private:
    void bindToAppSingletons();
    void sync();

    SdkColors *m_colors = nullptr;
    bool m_bound = false;
};

} // namespace ymusic::sdk
