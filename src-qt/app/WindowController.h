#pragma once

#include <QColor>
#include <QObject>
#include <QPointer>

#include <memory>

class QWindow;

namespace ymusic {

class WindowController : public QObject {
    Q_OBJECT

public:
    explicit WindowController(QObject *parent = nullptr);
    ~WindowController() override;

    Q_INVOKABLE void attach(QWindow *window, bool nativeTitleBar);
    Q_INVOKABLE void setNativeTitleBar(QWindow *window, bool enabled);
    Q_INVOKABLE void updateTheme(QWindow *window, const QColor &background);

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    struct Native;

    void attachNativeHandle();
    void applyPlatformStyle();

    QPointer<QWindow> m_window;
    QColor m_background;
    std::unique_ptr<Native> m_native;
};

} // namespace ymusic
