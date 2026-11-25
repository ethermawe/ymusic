#include "app/WindowController.h"

#include <QEvent>
#include <QGuiApplication>
#include <QPlatformSurfaceEvent>
#include <QQuickWindow>
#include <QTimer>
#include <QWindow>

#ifdef Q_OS_WIN
#include <windows.h>
#include <windowsx.h>
#include <commctrl.h>
#include <dwmapi.h>
#endif

namespace ymusic {

namespace {

Qt::WindowFlags windowFlagsFor(bool nativeTitleBar) {
#ifdef Q_OS_MACOS
    Q_UNUSED(nativeTitleBar);
    return Qt::Window | Qt::ExpandedClientAreaHint | Qt::NoTitleBarBackgroundHint;
#else
    return nativeTitleBar
        ? (Qt::Window | Qt::WindowTitleHint | Qt::WindowSystemMenuHint
           | Qt::WindowMinMaxButtonsHint | Qt::WindowCloseButtonHint)
        : (Qt::Window | Qt::FramelessWindowHint);
#endif
}

} // namespace

#ifdef Q_OS_WIN

namespace {

constexpr DWORD kImmersiveDarkMode = 20;
constexpr DWORD kCornerPreference = 33;
constexpr DWORD kBorderColor = 34;
constexpr DWORD kCaptionColor = 35;
constexpr DWORD kTextColor = 36;

COLORREF toColorRef(const QColor &color) {
    return RGB(color.red(), color.green(), color.blue());
}

} // namespace

struct WindowController::Native {
    HWND handle = nullptr;

    ~Native() {
        if (handle) {
            RemoveWindowSubclass(handle, &Native::windowProcedure, reinterpret_cast<UINT_PTR>(this));
            handle = nullptr;
        }
    }

    static LRESULT CALLBACK windowProcedure(HWND window, UINT message, WPARAM wParam, LPARAM lParam,
                                            UINT_PTR identity, DWORD_PTR context) {
        auto *controller = reinterpret_cast<WindowController *>(context);
        if (message == WM_THEMECHANGED || message == WM_DWMCOMPOSITIONCHANGED || message == WM_STYLECHANGED) {
            QTimer::singleShot(0, controller, &WindowController::applyPlatformStyle);
        }
        if (controller->m_window && !(GetWindowLongPtrW(window, GWL_STYLE) & WS_CAPTION)) {
            if (message == WM_NCCALCSIZE) {
                if (IsZoomed(window)) {
                    auto *bounds = wParam ? &reinterpret_cast<NCCALCSIZE_PARAMS *>(lParam)->rgrc[0]
                                          : reinterpret_cast<RECT *>(lParam);
                    MONITORINFO monitor {sizeof(MONITORINFO)};
                    if (GetMonitorInfoW(MonitorFromRect(bounds, MONITOR_DEFAULTTONEAREST), &monitor)) {
                        *bounds = monitor.rcWork;
                    }
                }
                return 0;
            }
            if (message == WM_NCHITTEST && !IsZoomed(window)
                && controller->m_window->visibility() != QWindow::FullScreen) {
                RECT bounds {};
                if (GetWindowRect(window, &bounds)) {
                    using WindowDpi = UINT (WINAPI *)(HWND);
                    using MetricsForDpi = int (WINAPI *)(int, UINT);
                    static const auto windowDpi = reinterpret_cast<WindowDpi>(
                        GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetDpiForWindow"));
                    static const auto metricsForDpi = reinterpret_cast<MetricsForDpi>(
                        GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetSystemMetricsForDpi"));
                    const UINT dpi = windowDpi
                        ? windowDpi(window)
                        : qRound(96 * controller->m_window->devicePixelRatio());
                    const int border = metricsForDpi
                        ? metricsForDpi(SM_CXSIZEFRAME, dpi) + metricsForDpi(SM_CXPADDEDBORDER, dpi)
                        : GetSystemMetrics(SM_CXSIZEFRAME) + GetSystemMetrics(SM_CXPADDEDBORDER);
                    const int horizontal = GET_X_LPARAM(lParam);
                    const int vertical = GET_Y_LPARAM(lParam);
                    const bool left = horizontal >= bounds.left && horizontal < bounds.left + border;
                    const bool right = horizontal < bounds.right && horizontal >= bounds.right - border;
                    const bool top = vertical >= bounds.top && vertical < bounds.top + border;
                    const bool bottom = vertical < bounds.bottom && vertical >= bounds.bottom - border;
                    if (top && left) return HTTOPLEFT;
                    if (top && right) return HTTOPRIGHT;
                    if (bottom && left) return HTBOTTOMLEFT;
                    if (bottom && right) return HTBOTTOMRIGHT;
                    if (left) return HTLEFT;
                    if (right) return HTRIGHT;
                    if (top) return HTTOP;
                    if (bottom) return HTBOTTOM;
                }
            }
        }
        if (message == WM_NCDESTROY) {
            RemoveWindowSubclass(window, &Native::windowProcedure, identity);
            if (controller->m_native) {
                controller->m_native->handle = nullptr;
            }
        }
        return DefSubclassProc(window, message, wParam, lParam);
    }
};

#else

struct WindowController::Native {};

#endif

WindowController::WindowController(QObject *parent)
    : QObject(parent)
    , m_native(std::make_unique<Native>()) {
}

WindowController::~WindowController() = default;

void WindowController::attach(QWindow *window, bool nativeTitleBar) {
    if (!window) return;

    if (m_window != window) {
        if (m_window) {
            m_window->removeEventFilter(this);
            disconnect(m_window, nullptr, this, nullptr);
        }
#ifdef Q_OS_WIN
        if (m_native->handle) {
            RemoveWindowSubclass(m_native->handle, &Native::windowProcedure,
                                 reinterpret_cast<UINT_PTR>(m_native.get()));
            m_native->handle = nullptr;
        }
#endif
        m_window = window;
        m_window->installEventFilter(this);
        connect(m_window, &QWindow::visibleChanged, this, [this](bool visible) {
            if (visible) applyPlatformStyle();
        });
        connect(m_window, &QWindow::visibilityChanged, this, [this](QWindow::Visibility) {
            applyPlatformStyle();
        });
        if (auto *quick = qobject_cast<QQuickWindow *>(m_window.data())) {
            m_background = quick->color();
            connect(quick, &QQuickWindow::colorChanged, this, [this](const QColor &color) {
                m_background = color;
                applyPlatformStyle();
            });
        }
    }

    setNativeTitleBar(window, nativeTitleBar);
    applyPlatformStyle();
}

void WindowController::setNativeTitleBar(QWindow *window, bool enabled) {
    if (!window) return;
    const Qt::WindowFlags desired = windowFlagsFor(enabled);
    if (window->flags() == desired) {
        applyPlatformStyle();
        return;
    }

#ifdef Q_OS_WIN
    if (window->handle() && QGuiApplication::platformName() == QLatin1StringView("windows")) {
        WINDOWPLACEMENT placement {sizeof(WINDOWPLACEMENT)};
        const bool placed = GetWindowPlacement(reinterpret_cast<HWND>(window->winId()), &placement);
        const auto visibility = window->visibility();
        const auto states = window->windowStates();
        const bool active = window->isActive();
        window->hide();
        window->destroy();
        window->setWindowStates(Qt::WindowNoState);
        window->setFlags(desired);
        window->create();
        if (placed) {
            placement.showCmd = SW_HIDE;
            SetWindowPlacement(reinterpret_cast<HWND>(window->winId()), &placement);
        }
        window->setWindowStates(states);
        window->setVisibility(visibility);
        if (active && window->isVisible()) {
            window->requestActivate();
        }
        applyPlatformStyle();
        return;
    }
#endif

    window->setFlags(desired);
    applyPlatformStyle();
}

void WindowController::updateTheme(QWindow *window, const QColor &background) {
    m_background = background;
    if (window && window == m_window) {
        applyPlatformStyle();
    }
}

bool WindowController::eventFilter(QObject *watched, QEvent *event) {
    if (watched == m_window && event->type() == QEvent::PlatformSurface) {
        const auto *surface = static_cast<QPlatformSurfaceEvent *>(event);
        if (surface->surfaceEventType() == QPlatformSurfaceEvent::SurfaceCreated) {
            applyPlatformStyle();
        }
    }
    return QObject::eventFilter(watched, event);
}

void WindowController::attachNativeHandle() {
#ifdef Q_OS_WIN
    if (!m_window || !m_window->handle()
        || QGuiApplication::platformName() != QLatin1StringView("windows")) {
        return;
    }
    const HWND handle = reinterpret_cast<HWND>(m_window->winId());
    if (m_native->handle == handle) return;
    if (m_native->handle) {
        RemoveWindowSubclass(m_native->handle, &Native::windowProcedure,
                             reinterpret_cast<UINT_PTR>(m_native.get()));
        m_native->handle = nullptr;
    }
    if (SetWindowSubclass(handle, &Native::windowProcedure,
                          reinterpret_cast<UINT_PTR>(m_native.get()),
                          reinterpret_cast<DWORD_PTR>(this))) {
        m_native->handle = handle;
    }
#endif
}

void WindowController::applyPlatformStyle() {
#ifdef Q_OS_WIN
    if (!m_window || !m_window->handle()
        || QGuiApplication::platformName() != QLatin1StringView("windows")) {
        return;
    }
    attachNativeHandle();
    const HWND handle = reinterpret_cast<HWND>(m_window->winId());
    if (m_window->flags().testFlag(Qt::FramelessWindowHint)
        && m_window->visibility() != QWindow::FullScreen) {
        const LONG_PTR current = GetWindowLongPtrW(handle, GWL_STYLE);
        const LONG_PTR desired = (current | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU)
                                 & ~WS_CAPTION;
        if (current != desired) {
            SetWindowLongPtrW(handle, GWL_STYLE, desired);
            SetWindowPos(handle, nullptr, 0, 0, 0, 0,
                         SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
        }
    }
    const QColor background = m_background.isValid() ? m_background : QColor(0x14, 0x12, 0x18);
    const BOOL dark = background.lightnessF() < 0.5;
    const DWORD corners = 2; // DWMWCP_ROUND
    const COLORREF border = 0xfffffffe; // DWMWA_COLOR_NONE
    const COLORREF caption = toColorRef(background);
    const COLORREF text = dark ? RGB(255, 255, 255) : RGB(0, 0, 0);
    DwmSetWindowAttribute(handle, kImmersiveDarkMode, &dark, sizeof(dark));
    DwmSetWindowAttribute(handle, kCornerPreference, &corners, sizeof(corners));
    DwmSetWindowAttribute(handle, kBorderColor, &border, sizeof(border));
    DwmSetWindowAttribute(handle, kCaptionColor, &caption, sizeof(caption));
    DwmSetWindowAttribute(handle, kTextColor, &text, sizeof(text));
#endif
}

} // namespace ymusic
