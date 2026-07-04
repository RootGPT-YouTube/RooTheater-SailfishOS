import QtQuick 2.6
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0

// The classic folder-based audio view (one row per folder that holds audio),
// kept as a fallback beside the Tracker-backed library categories: it also
// reaches files living outside the directories the system indexer watches.
// Moved here from GalleryPage when the Audio section became category rows.
Page {
    id: page
    allowedOrientations: Orientation.All

    property string title: ""
    property QtObject owner        // GalleryPage (kept in sync on deletes)
    property var galleryModel      // its MediaGalleryModel (audioFolders source)

    // Long-press target: the audio album row's model data, or null when hidden.
    // ({ folderName, folderPath, items })
    property var actionAlbum: null

    // ── Per-album cover choice (dconf JSON map folderPath -> image url) ───────
    ConfigurationValue {
        id: albumCoverConfig
        key: "/apps/harbour-rootheater/albumCovers"
        defaultValue: "{}"
    }
    property int coverTick: 0   // bumped to refresh cover bindings after a change
    function coverFor(folderPath) {
        coverTick                 // binding dependency
        var map = {}
        try { map = JSON.parse(albumCoverConfig.value) } catch (e) { map = {} }
        return map[folderPath] || ""
    }
    function setCover(folderPath, url) {
        var map = {}
        try { map = JSON.parse(albumCoverConfig.value) } catch (e) { map = {} }
        map[folderPath] = url
        albumCoverConfig.value = JSON.stringify(map)
        coverTick++
    }
    // Cover to show for an audio album row: the chosen image, else the embedded
    // art of the first track (lazy via rttrackcover), else "" → ♪ placeholder.
    function albumCoverSource(folderPath, firstPath) {
        var c = coverFor(folderPath)
        if (c && c.length > 0)
            return c.indexOf("file://") === 0 ? c : "file://" + c
        return firstPath ? "image://rttrackcover/" + encodeURIComponent(firstPath) : ""
    }

    function pickCover(folderPath) {
        var picker = pageStack.push(Qt.resolvedUrl("CoverPickerPage.qml"),
                                    { caller: page })
        picker.coverSelected.connect(function(path) {
            page.setCover(folderPath, path)
        })
    }

    function playAlbum(items) {
        if (!items || items.length === 0)
            return
        var paths = []
        for (var i = 0; i < items.length; ++i)
            paths.push(items[i].filePath)
        pageStack.push(Qt.resolvedUrl("PlayerPage.qml"), { queue: paths, trackIndex: 0 })
    }

    // FolderContentPage owner-callback: forward so the shared gallery model
    // (and this page's rows, bound to its audioFolders) stay in sync.
    function removePaths(paths) {
        if (owner && typeof owner.removePaths === "function")
            owner.removePaths(paths)
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: page.galleryModel ? page.galleryModel.audioFolders : []

        header: PageHeader {
            title: qsTr("Folders")
            description: page.title
        }

        delegate: ListItem {
            id: row
            contentHeight: Theme.itemSizeLarge

            // Album cover (chosen / embedded), with a ♪ placeholder.
            Item {
                id: audioCover
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: Theme.itemSizeLarge - Theme.paddingMedium
                height: width

                Rectangle {
                    anchors.fill: parent
                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)
                    visible: coverImage.status !== Image.Ready
                }
                Label {
                    anchors.centerIn: parent
                    visible: coverImage.status !== Image.Ready
                    text: "♪"
                    color: Theme.secondaryColor
                    font.pixelSize: parent.height * 0.5
                }
                Image {
                    id: coverImage
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    clip: true
                    asynchronous: true
                    cache: false
                    source: page.albumCoverSource(modelData.folderPath,
                                modelData.items.length > 0
                                    ? modelData.items[0].filePath : "")
                }
            }

            Column {
                anchors {
                    left: audioCover.right
                    leftMargin: Theme.paddingLarge
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    text: modelData.folderName
                    color: row.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    text: modelData.items.length + " "
                          + (modelData.items.length === 1 ? qsTr("item") : qsTr("items"))
                    color: row.highlighted ? Theme.secondaryHighlightColor
                                           : Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            onClicked: pageStack.push(Qt.resolvedUrl("FolderContentPage.qml"),
                                      { title: modelData.folderName, kind: "audio",
                                        folderPath: modelData.folderPath,
                                        items: modelData.items, owner: page })
            onPressAndHold: page.actionAlbum = { folderName: modelData.folderName,
                                                 folderPath: modelData.folderPath,
                                                 items: modelData.items }
        }

        ViewPlaceholder {
            enabled: listView.count === 0
            text: qsTr("No media found")
        }

        VerticalScrollDecorator {}
    }

    // ── Album long-press action sheet (slides up from the bottom) ────────────
    Item {
        id: actionOverlay
        anchors.fill: parent
        enabled: page.actionAlbum !== null
        visible: opacity > 0
        opacity: page.actionAlbum !== null ? 1.0 : 0.0
        Behavior on opacity { FadeAnimation { duration: 150 } }

        MouseArea {
            anchors.fill: parent
            onClicked: page.actionAlbum = null
            Rectangle { anchors.fill: parent; color: Theme.rgba("black", 0.6) }
        }

        Rectangle {
            id: sheet
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            anchors.bottomMargin: page.actionAlbum !== null ? 0 : -height
            height: sheetCol.height
            color: Theme.rgba(Theme.overlayBackgroundColor, 1.0)
            Behavior on anchors.bottomMargin {
                NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
            }

            MouseArea { anchors.fill: parent }

            Column {
                id: sheetCol
                width: parent.width

                Label {
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    x: Theme.horizontalPageMargin
                    topPadding: Theme.paddingLarge
                    bottomPadding: Theme.paddingMedium
                    truncationMode: TruncationMode.Fade
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeSmall
                    text: page.actionAlbum ? page.actionAlbum.folderName : ""
                }

                Separator {
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: Theme.secondaryColor
                }

                Repeater {
                    model: [
                        { label: qsTr("Album cover"), act: "cover", icon: "icon-m-image" },
                        { label: qsTr("Play album"),  act: "play",  icon: "icon-m-play" }
                    ]
                    delegate: BackgroundItem {
                        width: sheetCol.width
                        Row {
                            x: Theme.horizontalPageMargin
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.paddingLarge
                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                source: "image://theme/" + modelData.icon + "?"
                                        + (highlighted ? Theme.highlightColor : Theme.primaryColor)
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                color: highlighted ? Theme.highlightColor : Theme.primaryColor
                            }
                        }
                        onClicked: {
                            var al = page.actionAlbum
                            page.actionAlbum = null
                            if (!al) return
                            if (modelData.act === "cover")
                                page.pickCover(al.folderPath)
                            else
                                page.playAlbum(al.items)
                        }
                    }
                }
            }
        }
    }
}
