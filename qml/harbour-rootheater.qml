import QtQuick 2.0
import Sailfish.Silica 1.0
import "pages"
import "cover"

ApplicationWindow {
    id: app

    initialPage: Component { MainPage {} }
    cover: Component { CoverPage {} }
    allowedOrientations: Orientation.All

    // Open a file handed to us by the system (MIME handler) or the command line:
    // images go to the viewer, everything else to the player.
    function openMedia(path) {
        if (!path || path === "")
            return
        var lower = path.toLowerCase()
        function hasExt(exts) {
            for (var i = 0; i < exts.length; ++i)
                if (lower.slice(-exts[i].length) === exts[i])
                    return true
            return false
        }
        var isImage = hasExt([".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp",
                              ".heic", ".heif", ".tiff", ".tif", ".svg"])
        if (isImage) {
            pageStack.push(Qt.resolvedUrl("pages/ImageViewerPage.qml"),
                           { items: [ { filePath: path,
                                        fileName: path.split('/').pop(),
                                        mimeType: "image/*" } ],
                             index: 0 })
        } else {
            pageStack.push(Qt.resolvedUrl("pages/PlayerPage.qml"),
                           { source: path })
        }
    }

    // Defer the open by one event-loop tick: Qt.callLater is unavailable on the
    // SailfishOS Qt (5.6), and at launch the open arrives before pageStack is
    // ready, so route through a 0-interval Timer instead.
    property string _pendingMedia: ""
    Timer {
        id: openTimer
        interval: 1
        repeat: false
        onTriggered: {
            var p = app._pendingMedia
            app._pendingMedia = ""
            app.openMedia(p)
        }
    }
    function scheduleOpen(path) {
        if (!path || path === "")
            return
        app._pendingMedia = path
        openTimer.restart()
    }

    Connections {
        target: openHandler
        onOpenRequested: app.scheduleOpen(path)
    }

    Connections {
        target: shareHandler
        onShareRequested: app.scheduleOpen(path)
    }

    Component.onCompleted: {
        // A file handed to us at launch is waiting in pendingUrl.
        if (openHandler.pendingUrl !== "")
            app.scheduleOpen(openHandler.pendingUrl)
    }
}
