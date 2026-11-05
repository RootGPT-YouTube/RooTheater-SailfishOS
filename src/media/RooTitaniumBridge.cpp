#include "RooTitaniumBridge.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusReply>
#include <QStringList>
#include <QDebug>

namespace {
const char kService[] = "com.github.RootGPT_YouTube.rootitanium";
const char kPath[] = "/com/github/RootGPT_YouTube/rootitanium";
const char kInterface[] = "org.freedesktop.Application";
// RooTitanium reads this marker, drops it and takes the video to fullscreen by itself.
// A version that does not know it just opens the page: a fragment is harmless.
const char kAutoFullscreen[] = "#rt-autofullscreen";
// Starting the browser from cold takes a while on a slow phone.
const int kOpenTimeoutMs = 60000;
}

RooTitaniumBridge::RooTitaniumBridge(QObject *parent)
    : QObject(parent)
{
    refresh();
}

void RooTitaniumBridge::setEnabled(bool on)
{
    if (m_enabled == on)
        return;
    m_enabled = on;
    emit enabledChanged();
}

void RooTitaniumBridge::refresh()
{
    // The activation file comes with the package, so this answers "installed" even
    // when the browser is not running. Reading the .desktop file would not work: the
    // sandbox hides it.
    const QDBusReply<QStringList> names = QDBusConnection::sessionBus().call(
                QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.DBus"),
                                               QStringLiteral("/org/freedesktop/DBus"),
                                               QStringLiteral("org.freedesktop.DBus"),
                                               QStringLiteral("ListActivatableNames")));
    const bool now = names.isValid() && names.value().contains(QLatin1String(kService));
    if (now != m_installed) {
        m_installed = now;
        emit installedChanged();
    }
}

bool RooTitaniumBridge::playYouTube(const QString &videoId, const QString &title)
{
    if (!m_enabled)
        return false;
    refresh();
    if (!m_installed)
        return false;

    QDBusMessage call = QDBusMessage::createMethodCall(QLatin1String(kService),
                                                       QLatin1String(kPath),
                                                       QLatin1String(kInterface),
                                                       QStringLiteral("openUrl"));
    const QString url = QStringLiteral("https://m.youtube.com/watch?v=") + videoId
            + QLatin1String(kAutoFullscreen);
    call.setArguments({ QStringList(url) });
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(
                QDBusConnection::sessionBus().asyncCall(call, kOpenTimeoutMs), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, videoId, title](QDBusPendingCallWatcher *w) {
        QDBusPendingReply<> reply = *w;
        w->deleteLater();
        if (reply.isError()) {
            qWarning() << "RooTitanium did not answer:" << reply.error().message();
            emit openFailed(videoId, title);
        }
    });
    return true;
}
