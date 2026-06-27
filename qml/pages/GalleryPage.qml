import QtQuick 2.6
import Sailfish.Silica 1.0
import Nemo.Thumbnailer 1.0
import Nemo.Configuration 1.0
import RooTheater.Media 1.0

Page {
    id: page
    allowedOrientations: Orientation.All

    property string rootPath: ""
    property string title: ""

    // Long-press target: the audio album row's model data, or null when hidden.
    // ({ folderName, folderPath, items })
    property var actionAlbum: null

    // A playlist's kind follows where the builder saved it: Videos/ → video
    // (square play badge), otherwise audio (musical-note badge).
    function playlistKind(folderPath) {
        return /\/Videos\/?$/.test(folderPath) ? "video" : "audio"
    }

    function typeLabel(key) {
        if (key === "image") return qsTr("Images")
        if (key === "video") return qsTr("Videos")
        if (key === "audio") return qsTr("Audio")
        if (key === "playlist") return qsTr("Playlists")
        return key
    }

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

    // ── Row preview honouring the per-folder sort ────────────────────────────
    // FolderContentPage persists each folder's sort in this same dconf map; the
    // preview should show whatever item would be first there (default: Date desc).
    ConfigurationValue {
        id: sortConfig
        key: "/apps/harbour-rootheater/gallerySort"
        defaultValue: "{}"
    }
    function firstItem(folderPath, typeKey, list) {
        if (!list || list.length === 0)
            return null
        var sortBy = 2, sortDesc = true   // defaults match FolderContentPage
        try {
            var map = JSON.parse(sortConfig.value)
            var p = map[folderPath + "|" + typeKey]
            if (p) { sortBy = p.s; sortDesc = p.d }
        } catch (e) {}
        var arr = list.slice()
        arr.sort(function(a, b) {
            var r = 0
            if (sortBy === 1) r = (a.size || 0) - (b.size || 0)
            else if (sortBy === 2) r = (a.modified || 0) - (b.modified || 0)
            if (r === 0) {   // tie-break (and Name sort) by file name
                var an = (a.fileName || "").toLowerCase()
                var bn = (b.fileName || "").toLowerCase()
                r = an < bn ? -1 : (an > bn ? 1 : 0)
            }
            return sortDesc ? -r : r
        })
        return arr[0]
    }

    // Keep the gallery model in sync when files are deleted inside a folder, so
    // re-entering the folder doesn't resurrect them (FolderContentPage notifies
    // us as its `owner`).
    function removePaths(paths) {
        galleryModel.removePaths(paths)
    }
    // Re-scan this storage (e.g. after the builder saves a new playlist here).
    function refresh() {
        galleryModel.refresh()
    }

    MediaGalleryModel {
        id: galleryModel
        rootPath: page.rootPath
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: galleryModel

        header: PageHeader { title: page.title }

        PullDownMenu {
            MenuItem {
                text: qsTr("Create video playlist")
                onClicked: pageStack.push(Qt.resolvedUrl("PlaylistBuilderPage.qml"),
                                          { owner: page, mediaType: "video" })
            }
            MenuItem {
                text: qsTr("Create audio playlist")
                onClicked: pageStack.push(Qt.resolvedUrl("PlaylistBuilderPage.qml"),
                                          { owner: page, mediaType: "audio" })
            }
        }

        // Group the folders by media type → "Images / Videos / Audio" sections.
        section.property: "typeKey"
        section.delegate: SectionHeader { text: page.typeLabel(section) }

        delegate: ListItem {
            id: row
            contentHeight: Theme.itemSizeLarge

            readonly property bool isAudio: typeKey === "audio"
            readonly property bool isPlaylist: typeKey === "playlist"

            // Non-audio: thumbnail of the item shown first when opening the folder
            // (i.e. honouring that folder's saved sort), not a fixed one.
            readonly property var firstItem: (!row.isAudio && !row.isPlaylist)
                                             ? page.firstItem(folderPath, typeKey, items)
                                             : null
            Thumbnail {
                id: preview
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: Theme.itemSizeLarge - Theme.paddingMedium
                height: width
                visible: !row.isAudio && !row.isPlaylist
                source: row.firstItem ? row.firstItem.filePath : ""
                mimeType: row.firstItem ? (row.firstItem.mimeType || "") : ""
                sourceSize.width: width
                sourceSize.height: height
                fillMode: Thumbnail.PreserveAspectCrop
                clip: true
            }

            // Audio: album cover (chosen / embedded), with a ♪ placeholder.
            Item {
                id: audioCover
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: Theme.itemSizeLarge - Theme.paddingMedium
                height: width
                visible: row.isAudio

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
                    source: row.isAudio
                            ? page.albumCoverSource(folderPath,
                                  items.length > 0 ? items[0].filePath : "")
                            : ""
                }
            }

            // Playlist folder badge: musical note for audio, square play for video.
            Item {
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: Theme.itemSizeLarge - Theme.paddingMedium
                height: width
                visible: row.isPlaylist

                readonly property bool isVideoPlaylist:
                    row.isPlaylist && page.playlistKind(folderPath) === "video"

                Rectangle {
                    anchors.fill: parent
                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)
                }
                Label {
                    anchors.centerIn: parent
                    visible: !parent.isVideoPlaylist
                    text: "♪"
                    color: Theme.secondaryColor
                    font.pixelSize: parent.height * 0.5
                }
                Image {
                    anchors.centerIn: parent
                    visible: parent.isVideoPlaylist
                    source: "image://theme/icon-m-media-playlists?" + Theme.secondaryColor
                }
            }

            Column {
                anchors {
                    left: preview.right
                    leftMargin: Theme.paddingLarge
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    text: folderName
                    color: row.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    text: row.isPlaylist
                          ? count + " " + (count === 1 ? qsTr("playlist") : qsTr("playlists"))
                          : count + " " + (count === 1 ? qsTr("item") : qsTr("items"))
                    color: row.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            onClicked: {
                if (row.isPlaylist)
                    pageStack.push(Qt.resolvedUrl("PlaylistsPage.qml"),
                                   { title: folderName, items: items, owner: page,
                                     kind: page.playlistKind(folderPath) })
                else
                    pageStack.push(Qt.resolvedUrl("FolderContentPage.qml"),
                                   { title: folderName, kind: typeKey,
                                     folderPath: folderPath, items: items,
                                     owner: page })
            }
            onPressAndHold: {
                if (row.isAudio)
                    page.actionAlbum = { folderName: folderName,
                                         folderPath: folderPath, items: items }
            }
        }

        ViewPlaceholder {
            enabled: !galleryModel.scanning && galleryModel.count === 0
            text: page.rootPath === "" ? qsTr("Storage not available")
                                       : qsTr("No media found")
        }

        VerticalScrollDecorator {}
    }

    BusyIndicator {
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
        running: galleryModel.scanning
        visible: running
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
