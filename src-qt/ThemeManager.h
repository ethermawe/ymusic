#pragma once

#include <QObject>
#include <QColor>
#include <QFileSystemWatcher>
#include <QTimer>

class ThemeManager : public QObject {
    Q_OBJECT

    Q_PROPERTY(QColor background READ background NOTIFY themeChanged)
    Q_PROPERTY(QColor surface READ surface NOTIFY themeChanged)
    Q_PROPERTY(QColor surfaceDim READ surfaceDim NOTIFY themeChanged)
    Q_PROPERTY(QColor surfaceBright READ surfaceBright NOTIFY themeChanged)
    Q_PROPERTY(QColor surfaceContainerLowest READ surfaceContainerLowest NOTIFY themeChanged)
    Q_PROPERTY(QColor surfaceContainerLow READ surfaceContainerLow NOTIFY themeChanged)
    Q_PROPERTY(QColor surfaceContainer READ surfaceContainer NOTIFY themeChanged)
    Q_PROPERTY(QColor surfaceContainerHigh READ surfaceContainerHigh NOTIFY themeChanged)
    Q_PROPERTY(QColor surfaceContainerHighest READ surfaceContainerHighest NOTIFY themeChanged)
    Q_PROPERTY(QColor onSurface READ onSurface NOTIFY themeChanged)
    Q_PROPERTY(QColor onSurfaceVariant READ onSurfaceVariant NOTIFY themeChanged)
    Q_PROPERTY(QColor outline READ outline NOTIFY themeChanged)
    Q_PROPERTY(QColor outlineVariant READ outlineVariant NOTIFY themeChanged)
    Q_PROPERTY(QColor primary READ primary NOTIFY themeChanged)
    Q_PROPERTY(QColor primaryHover READ primaryHover NOTIFY themeChanged)
    Q_PROPERTY(QColor onPrimary READ onPrimary NOTIFY themeChanged)
    Q_PROPERTY(QColor primaryContainer READ primaryContainer NOTIFY themeChanged)
    Q_PROPERTY(QColor onPrimaryContainer READ onPrimaryContainer NOTIFY themeChanged)
    Q_PROPERTY(QColor secondary READ secondary NOTIFY themeChanged)
    Q_PROPERTY(QColor secondaryContainer READ secondaryContainer NOTIFY themeChanged)
    Q_PROPERTY(QColor tertiary READ tertiary NOTIFY themeChanged)
    Q_PROPERTY(QColor error READ error NOTIFY themeChanged)
    Q_PROPERTY(bool isDark READ isDark NOTIFY themeChanged)

public:
    explicit ThemeManager(QObject *parent = nullptr);

    static ThemeManager &instance();

    QColor background() const { return m_background; }
    QColor surface() const { return m_surface; }
    QColor surfaceDim() const { return m_surfaceDim; }
    QColor surfaceBright() const { return m_surfaceBright; }
    QColor surfaceContainerLowest() const { return m_surfaceContainerLowest; }
    QColor surfaceContainerLow() const { return m_surfaceContainerLow; }
    QColor surfaceContainer() const { return m_surfaceContainer; }
    QColor surfaceContainerHigh() const { return m_surfaceContainerHigh; }
    QColor surfaceContainerHighest() const { return m_surfaceContainerHighest; }
    QColor onSurface() const { return m_onSurface; }
    QColor onSurfaceVariant() const { return m_onSurfaceVariant; }
    QColor outline() const { return m_outline; }
    QColor outlineVariant() const { return m_outlineVariant; }
    QColor primary() const { return m_primary; }
    QColor primaryHover() const { return m_primaryHover; }
    QColor onPrimary() const { return m_onPrimary; }
    QColor primaryContainer() const { return m_primaryContainer; }
    QColor onPrimaryContainer() const { return m_onPrimaryContainer; }
    QColor secondary() const { return m_secondary; }
    QColor secondaryContainer() const { return m_secondaryContainer; }
    QColor tertiary() const { return m_tertiary; }
    QColor error() const { return m_error; }
    bool isDark() const { return m_isDark; }

    Q_INVOKABLE void reload();

signals:
    void themeChanged();

private slots:
    void onFileChanged();

private:
    void loadColors();
    bool tryLoadNoctalia();
    bool tryLoadQuickshell();
    bool tryLoadPresets();
    void setDefaults();
    void deriveSurfaces();

    QFileSystemWatcher m_watcher;
    QTimer m_debounceTimer;

    QColor m_background;
    QColor m_surface;
    QColor m_surfaceDim;
    QColor m_surfaceBright;
    QColor m_surfaceContainerLowest;
    QColor m_surfaceContainerLow;
    QColor m_surfaceContainer;
    QColor m_surfaceContainerHigh;
    QColor m_surfaceContainerHighest;
    QColor m_onSurface;
    QColor m_onSurfaceVariant;
    QColor m_outline;
    QColor m_outlineVariant;
    QColor m_primary;
    QColor m_primaryHover;
    QColor m_onPrimary;
    QColor m_primaryContainer;
    QColor m_onPrimaryContainer;
    QColor m_secondary;
    QColor m_secondaryContainer;
    QColor m_tertiary;
    QColor m_error;
    bool m_isDark = true;
};
