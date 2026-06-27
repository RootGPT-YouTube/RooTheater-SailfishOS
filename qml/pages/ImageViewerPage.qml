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
    readonly property bool currentIsGif: currentItem
                                         && currentItem.filePath.toLowerCase().slice(-4) === ".gif"

    // Tap the image to toggle the chrome (counter + action bar).
    property bool chromeVisible: true

    // Transient view rotation for the current image (0/90/180/270), cycled by the
    // rotate button; reset whenever the user swipes to another photo.
    property int viewRotation: 0

    // Keep the app cover showing the current picture.
    function pushCover() {
        if (currentItem) {
            coverState.mode = "image"
            coverState.imagePath = currentItem.filePath
        }
    }
    onCurrentItemChanged: { pushCover(); viewRotation = 0 }
    Component.onCompleted: pushCover()
    Component.onDestruction: coverState.clear()

    FileOperations { id: fileOps }
    ShareAction { id: shareAction }
    RemorsePopup { id: remorse }

    // Open the current image in the editor; splice the saved copy in next to it.
    function editCurrent() {
        if (!currentItem) return
        var editor = pageStack.push(Qt.resolvedUrl("ImageEditorPage.qml"),
                                    { filePath: currentItem.filePath })
        editor.edited.connect(page.onEdited)
    }
    function onEdited(newPath) {
        if (!newPath) return
        var info = fileOps.fileInfo(newPath)
        if (!info || !info.filePath) return
        var arr = page.items.slice()
        var at = view.currentIndex + 1
        arr.splice(at, 0, info)
        page.items = arr
        view.currentIndex = at          // jump to the freshly edited copy
        if (page.owner && typeof page.owner.addItems === "function")
            page.owner.addItems([info])
    }

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

            // The rotate button only affects the photo on screen.
            readonly property int rot: index === view.currentIndex ? page.viewRotation : 0
            readonly property bool swap: rot % 180 !== 0

            // Two-finger pinch zooms; double tap restores 1×; single tap toggles
            // chrome. While zoomed the parent ListView swipe is disabled so the
            // one-finger drag pans the image instead of changing photo.
            PinchZoom {
                id: zoom
                anchors.fill: parent
                onClicked: page.chromeVisible = !page.chromeVisible
                onZoomedChanged: if (index === view.currentIndex) view.interactive = !zoomed

                Image {
                    id: still
                    anchors.centerIn: parent
                    // Swap the fit box when rotated 90°/270° so the photo still
                    // fills the screen instead of being letter-boxed sideways.
                    width: cell.swap ? parent.height : parent.width
                    height: cell.swap ? parent.width : parent.height
                    rotation: cell.rot
                    visible: !cell.isGif
                    source: cell.isGif ? "" : cell.filePath
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    autoTransform: true   // honour EXIF orientation (portrait photos)
                    sourceSize.width: view.width * 1.5
                    sourceSize.height: view.height * 1.5
                }
                AnimatedImage {
                    anchors.centerIn: parent
                    width: cell.swap ? parent.height : parent.width
                    height: cell.swap ? parent.width : parent.height
                    rotation: cell.rot
                    visible: cell.isGif
                    source: cell.isGif ? cell.filePath : ""
                    fillMode: Image.PreserveAspectFit
                    autoTransform: true
                    playing: cell.isGif
                    cache: false
                }
            }
            BusyIndicator {
                anchors.centerIn: parent
                size: BusyIndicatorSize.Medium
                running: !cell.isGif && still.status === Image.Loading
                visible: running
            }

            // Reset zoom when swiping away from this photo, and keep the ListView
            // swipe in sync with the now-current cell's zoom state.
            Connections {
                target: view
                onCurrentIndexChanged: {
                    if (view.currentIndex !== index) {
                        if (zoom.zoomed) zoom.reset()
                    } else {
                        view.interactive = !zoom.zoomed
                    }
                }
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
                // Gallery's image-rotate icon (distinct from the video player's
                // generic icon-m-rotate); turns the photo 90° clockwise per tap.
                icon.source: "image://theme/icon-m-rotate-right"
                enabled: page.currentItem
                highlighted: page.viewRotation !== 0
                onClicked: page.viewRotation = (page.viewRotation + 90) % 360
            }
            IconButton {
                icon.source: "image://theme/icon-m-edit"
                enabled: page.currentItem && !page.currentIsGif
                onClicked: page.editCurrent()
            }
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
