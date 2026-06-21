import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.Share 1.0
import RooTheater.Media 1.0

Page {
    id: page
    allowedOrientations: Orientation.All

    property var items: []     // [{ filePath, fileName, mimeType, … }, …] (one folder)
    property int index: 0
    property QtObject owner    // FolderContentPage to notify on delete (optional)

    readonly property var currentItem: (view.currentIndex >= 0 && view.currentIndex < items.length)
                                       ? items[view.currentIndex] : null

    // Tap the image to toggle the chrome (counter + action bar).
    property bool chromeVisible: true

    FileOperations { id: fileOps }
    ShareAction { id: shareAction }
    RemorsePopup { id: remorse }

    function shareCurrent() {
        if (!currentItem) return
        var p = currentItem.filePath
        shareAction.mimeType = currentItem.mimeType ? currentItem.mimeType : "image/*"
        shareAction.resources = [p.indexOf("file://") === 0 ? p : "file://" + p]
        shareAction.trigger()
    }

    function deleteCurrent() {
        if (!currentItem) return
        var fp = currentItem.filePath
        remorse.execute(qsTr("Deleting"), function() {
            fileOps.remove(fp)
            if (page.owner && typeof page.owner.removePaths === "function")
                page.owner.removePaths([fp])
            // Drop it from this viewer's own list.
            var arr = []
            for (var i = 0; i < page.items.length; ++i)
                if (page.items[i].filePath !== fp) arr.push(page.items[i])
            if (arr.length === 0) {
                pageStack.pop()
                return
            }
            var keep = Math.min(view.currentIndex, arr.length - 1)
            page.items = arr
            view.currentIndex = keep
        })
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    SilicaListView {
        id: view
        anchors.fill: parent
        model: page.items
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        highlightMoveDuration: 0   // jump straight to the tapped image, no scroll
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: width         // keep ~one neighbour each side ready
        currentIndex: page.index   // initial position (broken once the user swipes)

        delegate: Item {
            id: cell
            width: view.width
            height: view.height

            readonly property string filePath: modelData.filePath
            // GIFs must animate (the stock SFOS gallery shows them static); use
            // AnimatedImage for them, a plain (async) Image for everything else.
            readonly property bool isGif: filePath.toLowerCase().slice(-4) === ".gif"

            Image {
                id: still
                anchors.fill: parent
                visible: !cell.isGif
                source: cell.isGif ? "" : cell.filePath
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                autoTransform: true   // honour EXIF orientation (portrait photos)
                sourceSize.width: view.width * 1.5
                sourceSize.height: view.height * 1.5
            }
            AnimatedImage {
                anchors.fill: parent
                visible: cell.isGif
                source: cell.isGif ? cell.filePath : ""
                fillMode: Image.PreserveAspectFit
                autoTransform: true
                playing: cell.isGif
                cache: false
            }
            BusyIndicator {
                anchors.centerIn: parent
                size: BusyIndicatorSize.Medium
                running: !cell.isGif && still.status === Image.Loading
                visible: running
            }
            MouseArea {
                anchors.fill: parent
                onClicked: page.chromeVisible = !page.chromeVisible
            }
        }
    }

    // Position counter (e.g. "3 / 27").
    Label {
        anchors {
            top: parent.top
            topMargin: Theme.paddingLarge
            horizontalCenter: parent.horizontalCenter
        }
        visible: page.chromeVisible
        color: Theme.highlightColor
        font.pixelSize: Theme.fontSizeSmall
        text: page.items.length > 1 ? (view.currentIndex + 1) + " / " + page.items.length : ""
    }

    // Bottom action bar: share + delete for the current image.
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: Theme.itemSizeLarge
        visible: page.chromeVisible
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: Theme.rgba("black", 0.6) }
        }

        Row {
            anchors.centerIn: parent
            spacing: Theme.paddingLarge * 2

            IconButton {
                icon.source: "image://theme/icon-m-share"
                onClicked: page.shareCurrent()
            }
            IconButton {
                icon.source: "image://theme/icon-m-delete"
                onClicked: page.deleteCurrent()
            }
        }
    }
}
