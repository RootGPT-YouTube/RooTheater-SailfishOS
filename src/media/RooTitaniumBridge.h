#ifndef ROOTITANIUMBRIDGE_H
#define ROOTITANIUMBRIDGE_H

#include <QObject>
#include <QString>

// Hands YouTube videos to RooTitanium, when it is installed and the viewer asked for
// it in Options. RooTitanium is a Qt6 app and cannot live inside this process, so the
// session bus is the only way across: the sandbox lets us see and call that one name
// (RooTitaniumPlayer.permission) and D-Bus activation starts the browser if it is closed.
class RooTitaniumBridge : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool installed READ installed NOTIFY installedChanged)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)

public:
    explicit RooTitaniumBridge(QObject *parent = nullptr);

    bool installed() const { return m_installed; }
    bool enabled() const { return m_enabled; }
    void setEnabled(bool on);

    // Asks the bus again: RooTitanium may have been installed or removed meanwhile.
    Q_INVOKABLE void refresh();

    // True when the video has gone to RooTitanium, false when the in-app player has to
    // show it. A call that fails later on comes back through openFailed.
    Q_INVOKABLE bool playYouTube(const QString &videoId, const QString &title);

signals:
    void installedChanged();
    void enabledChanged();
    void openFailed(const QString &videoId, const QString &title);

private:
    bool m_installed = false;
    bool m_enabled = false;
};

#endif // ROOTITANIUMBRIDGE_H
