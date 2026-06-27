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

    Connections {
        target: openHandler
        onOpenRequested: Qt.callLater(app.openMedia, path)
    }

    Component.onCompleted: {
        // A file passed at launch (Exec … %U) is waiting in pendingUrl.
        if (openHandler.pendingUrl !== "")
            Qt.callLater(app.openMedia, openHandler.pendingUrl)
    }
}
