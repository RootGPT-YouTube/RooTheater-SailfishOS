/*
    RooTheater — a multimedia player for Sailfish OS.
    Copyright (C) 2026 RootGPT

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program. If not, see <http://www.gnu.org/licenses/>.
*/

#ifdef QT_QML_DEBUG
#include <QtQuick>
#endif

#include <sailfishapp.h>
#include <QScopedPointer>
#include <QGuiApplication>
#include <QQuickView>
#include <QQmlContext>
#include <QQmlEngine>
#include <qqml.h>
#include <QDBusConnection>
#include <QString>

#include "media/MediaEngine.h"
#include "media/VideoSurface.h"
#include "media/CoverImageProvider.h"
#include "media/TrackCoverProvider.h"
#include "media/TagReader.h"
#include "media/TrackIndexer.h"
#include "media/StorageRoots.h"
#include "media/MediaGalleryModel.h"
#include "media/FileOperations.h"
#include "media/ImageEditor.h"
#include "media/OpenHandler.h"
#include "media/ShareHandler.h"
#include "media/CoverState.h"
#include "media/YtSubscriptions.h"
#include "media/YtFeed.h"
#include "media/YtSearch.h"
#ifdef HAVE_LIBVLC
#include "media/VlcBackend.h"
#endif
#ifdef HAVE_DROIDMEDIA
#include "media/DroidCodecBackend.h"
#include "media/DroidVideoSink.h"
#endif

#ifndef APP_VERSION
#define APP_VERSION "0.0.0"
#endif

int main(int argc, char *argv[])
{
    QScopedPointer<QGuiApplication> app(SailfishApp::application(argc, argv));
    app->setApplicationName("harbour-rootheater");
    app->setApplicationVersion(APP_VERSION);

    // Engine facade exposed to QML. Backend enum (MediaEngine.Droidmedia, …) is
    // accessible once the type is registered under this import URI.
    qmlRegisterType<MediaEngine>("RooTheater.Media", 1, 0, "MediaEngine");
    // Shared CPU-buffer video sink for the libVLC and droidmedia backends.
    qmlRegisterType<VideoSurface>("RooTheater.Media", 1, 0, "VideoSurface");
    // Media gallery: storage roots + the folder-grouped image/video model.
    qmlRegisterType<StorageRoots>("RooTheater.Media", 1, 0, "StorageRoots");
    qmlRegisterType<MediaGalleryModel>("RooTheater.Media", 1, 0, "MediaGalleryModel");
    // Gallery file actions (delete); share is handled QML-side via Sailfish.Share.
    qmlRegisterType<FileOperations>("RooTheater.Media", 1, 0, "FileOperations");
    // Full-resolution image editor (crop + freehand/circle/arrow annotations).
    qmlRegisterType<ImageEditor>("RooTheater.Media", 1, 0, "ImageEditor");
    // Async per-file metadata reader (album track titles + the "View tags" view).
    qmlRegisterType<TagReader>("RooTheater.Media", 1, 0, "TagReader");
    // Batch track-number reader backing the audio "Sort by Track" order.
    qmlRegisterType<TrackIndexer>("RooTheater.Media", 1, 0, "TrackIndexer");
    // YouTube RSS: subscriptions model is a shared instance (ytSubs context
    // property, below); the per-page video feed is instantiated in QML.
    qmlRegisterType<YtFeed>("RooTheater.Media", 1, 0, "YtFeed");
    // Keyless YouTube search (videos + channels), instantiated per page.
    qmlRegisterType<YtSearch>("RooTheater.Media", 1, 0, "YtSearch");
#ifdef HAVE_LIBVLC
    // Layer 3 libvlc backend (built only when libvlc is vendored; see the .pro).
    qmlRegisterType<VlcBackend>("RooTheater.Media", 1, 0, "VlcBackend");
#endif
#ifdef HAVE_DROIDMEDIA
    // Layer 1 direct droidmedia HW decode backend (v0.3).
    qmlRegisterType<DroidCodecBackend>("RooTheater.Media", 1, 0, "DroidCodecBackend");
    // Zero-copy EGLImage video surface for the droidmedia path (v0.3.3).
    qmlRegisterType<DroidVideoSink>("RooTheater.Media", 1, 0, "DroidVideoSink");
#endif

    QScopedPointer<QQuickView> view(SailfishApp::createView());

    // MIME-handler plumbing: own the app's session-bus name and export the
    // org.freedesktop.Application interface so SailfishOS can hand us a file to
    // open. The bus name/object path come from the .desktop X-Sailjail identity
    // (OrganizationName.ApplicationName); ExecDBus there makes Sailjail grant it.
    OpenHandler *openHandler = new OpenHandler(app.data());
    // A path may also arrive on argv (Exec … %U); take the first non-option one.
    for (int i = 1; i < argc; ++i) {
        const QString a = QString::fromLocal8Bit(argv[i]);
        if (a.startsWith(QLatin1Char('-')))
            continue;
        openHandler->setInitialPath(a);
        break;
    }
    // "Share with" (Transfer Engine): sailfish-share calls org.sailfishos.share
    // .share(a{sv}) on /share/<method-id> of our bus name; the method id comes
    // from the .desktop X-Share-Methods (rootheater_share). Separate object from
    // OpenHandler but routed the same way.
    ShareHandler *shareHandler = new ShareHandler(app.data());
    {
        const QString busName = QStringLiteral("com.github.RootGPT_YouTube.rootheater");
        const QString objPath = QStringLiteral("/com/github/RootGPT_YouTube/rootheater");
        const QString sharePath = QStringLiteral("/share/rootheater_share");
        QDBusConnection bus = QDBusConnection::sessionBus();
        bus.registerObject(objPath, openHandler, QDBusConnection::ExportAllSlots);
        bus.registerObject(sharePath, shareHandler, QDBusConnection::ExportAllSlots);
        bus.registerService(busName);
    }
    // Bring the window forward when a file (or bare activation) arrives.
    QObject::connect(openHandler, &OpenHandler::openRequested,
                     [&view](const QString &) { view->raise(); });
    QObject::connect(openHandler, &OpenHandler::activated,
                     [&view]() { view->raise(); });
    QObject::connect(shareHandler, &ShareHandler::shareRequested,
                     [&view](const QString &) { view->raise(); });
    view->rootContext()->setContextProperty("openHandler", openHandler);
    view->rootContext()->setContextProperty("shareHandler", shareHandler);

    // Shared playback state for the app cover (written by the viewer/player).
    CoverState *coverState = new CoverState(app.data());
    view->rootContext()->setContextProperty("coverState", coverState);

    // Shared YouTube subscriptions model (Home grid + YouTube page stay in sync).
    YtSubscriptions *ytSubs = new YtSubscriptions(app.data());
    view->rootContext()->setContextProperty("ytSubs", ytSubs);

    // In-memory provider for embedded audio cover art (engine owns it). MediaEngine
    // reaches it via g_coverProvider; QML shows "image://rtcover/<token>".
    g_coverProvider = new CoverImageProvider;
    view->engine()->addImageProvider(QStringLiteral("rtcover"), g_coverProvider);

    // Path-keyed lazy cover provider for the gallery grids (per-album / per-track
    // embedded art): QML uses "image://rttrackcover/<percent-encoded-path>". The
    // QML engine takes ownership of the provider.
    view->engine()->addImageProvider(QStringLiteral("rttrackcover"), new TrackCoverProvider);

    // Exposed to QML (AboutPage); single source of truth is RT_APP_VERSION in the .pro.
    view->rootContext()->setContextProperty("appVersion", QStringLiteral(APP_VERSION));

    view->setSource(SailfishApp::pathTo("qml/harbour-rootheater.qml"));
    view->show();

    return app->exec();
}
