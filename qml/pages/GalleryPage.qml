import QtQuick 2.6
import Sailfish.Silica 1.0
import Nemo.Thumbnailer 1.0
import Nemo.Configuration 1.0
import RooTheater.Media 1.0
import "MusicQueries.js" as MusicQueries

Page {
    id: page
    allowedOrientations: Orientation.All

    property string rootPath: ""
    property string title: ""

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

    // ── Music library categories (Tracker-backed, like the stock Media app) ──
    // The internal storage excludes android_storage, which is its own entry.
    readonly property string excludePath:
        rootPath.indexOf("android_storage") >= 0 ? "" : rootPath + "/android_storage"
    readonly property var libraryOpts: ({ rootPath: rootPath, excludePath: excludePath })

    // Soft permission gate (Options → Permissions): with the media index off,
    // no Tracker query runs and the Audio section only offers folder browsing.
    ConfigurationValue {
        id: permMediaLibrary
        key: "/apps/harbour-rootheater/perm/medialibrary"
        defaultValue: true
    }
    readonly property bool libraryAllowed:
        permMediaLibrary.value !== false && permMediaLibrary.value !== "false"

    // -1 = not fetched yet (subtitle stays empty until Tracker answers).
    property int songCount: -1
    property int albumCount: -1
    property int artistCount: -1

    TrackerMusicModel {
        id: songsCountModel
        query: page.rootPath !== "" && page.libraryAllowed
               ? MusicQueries.songsCountQuery(page.libraryOpts) : ""
        onFinished: page.songCount = count > 0 ? getMediaItem(0).childCount : 0
    }
    TrackerMusicModel {
        id: albumsCountModel
        query: page.rootPath !== "" && page.libraryAllowed
               ? MusicQueries.albumsCountQuery(page.libraryOpts) : ""
        onFinished: page.albumCount = count > 0 ? getMediaItem(0).childCount : 0
    }
    TrackerMusicModel {
        id: artistsCountModel
        query: page.rootPath !== "" && page.libraryAllowed
               ? MusicQueries.artistsCountQuery(page.libraryOpts) : ""
        onFinished: page.artistCount = count > 0 ? getMediaItem(0).childCount : 0
    }

    function openCategory(act) {
        if (act === "songs")
            pageStack.push(Qt.resolvedUrl("MusicSongsPage.qml"),
                           { title: qsTr("All songs"),
                             rootPath: rootPath, excludePath: excludePath })
        else if (act === "albums")
            pageStack.push(Qt.resolvedUrl("MusicAlbumsPage.qml"),
                           { rootPath: rootPath, excludePath: excludePath })
        else if (act === "artists")
            pageStack.push(Qt.resolvedUrl("MusicArtistsPage.qml"),
                           { rootPath: rootPath, excludePath: excludePath })
        else
            pageStack.push(Qt.resolvedUrl("AudioFoldersPage.qml"),
                           { owner: page, galleryModel: galleryModel,
                             title: page.title })
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

        delegate: Item {
            id: row
            width: listView.width
            height: isAudio ? categoryColumn.height : Theme.itemSizeLarge

            readonly property bool isAudio: typeKey === "audio"
            readonly property bool isPlaylist: typeKey === "playlist"

            // ── Audio: library categories (songs / albums / artists / folders),
            // Tracker-backed like the stock Media app, instead of folder rows.
            Column {
                id: categoryColumn
                width: parent.width
                visible: row.isAudio

                Repeater {
                    model: {
                        if (!row.isAudio)
                            return []
                        var m = []
                        if (page.libraryAllowed) {
                            m.push({ act: "songs", icon: "icon-m-media-songs",
                                     label: qsTr("All songs"),
                                     sub: page.songCount < 0 ? ""
                                          : page.songCount + " " + (page.songCount === 1
                                                ? qsTr("song") : qsTr("songs")) })
                            m.push({ act: "albums", icon: "icon-m-media-albums",
                                     label: qsTr("Albums"),
                                     sub: page.albumCount < 0 ? ""
                                          : page.albumCount + " " + (page.albumCount === 1
                                                ? qsTr("album") : qsTr("albums")) })
                            m.push({ act: "artists", icon: "icon-m-media-artists",
                                     label: qsTr("Artists"),
                                     sub: page.artistCount < 0 ? ""
                                          : page.artistCount + " " + (page.artistCount === 1
                                                ? qsTr("artist") : qsTr("artists")) })
                        }
                        m.push({ act: "folders", icon: "icon-m-file-folder",
                                 label: qsTr("Folders"),
                                 sub: galleryModel.audioFolders.length + " "
                                      + (galleryModel.audioFolders.length === 1
                                            ? qsTr("folder") : qsTr("folders")) })
                        return m
                    }
                    delegate: BackgroundItem {
                        width: categoryColumn.width
                        height: Theme.itemSizeMedium

                        Image {
                            id: categoryIcon
                            x: Theme.horizontalPageMargin
                            anchors.verticalCenter: parent.verticalCenter
                            source: "image://theme/" + modelData.icon + "?"
                                    + (highlighted ? Theme.highlightColor
                                                   : Theme.primaryColor)
                        }
                        Column {
                            anchors {
                                left: categoryIcon.right
                                leftMargin: Theme.paddingLarge
                                right: parent.right
                                rightMargin: Theme.horizontalPageMargin
                                verticalCenter: parent.verticalCenter
                            }
                            Label {
                                width: parent.width
                                truncationMode: TruncationMode.Fade
                                text: modelData.label
                                color: highlighted ? Theme.highlightColor
                                                   : Theme.primaryColor
                            }
                            Label {
                                visible: text !== ""
                                text: modelData.sub
                                color: highlighted ? Theme.secondaryHighlightColor
                                                   : Theme.secondaryColor
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }
                        onClicked: page.openCategory(modelData.act)
                    }
                }
            }

            // ── Image / video / playlist: folder row (unchanged behaviour) ──
            ListItem {
                id: folderRow
                width: parent.width
                contentHeight: Theme.itemSizeLarge
                visible: !row.isAudio

                // Thumbnail of the item shown first when opening the folder
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
                    visible: !row.isPlaylist
                    source: folderRow.firstItem ? folderRow.firstItem.filePath : ""
                    mimeType: folderRow.firstItem ? (folderRow.firstItem.mimeType || "") : ""
                    sourceSize.width: width
                    sourceSize.height: height
                    fillMode: Thumbnail.PreserveAspectCrop
                    clip: true
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
                        color: folderRow.highlighted ? Theme.highlightColor : Theme.primaryColor
                    }
                    Label {
                        text: row.isPlaylist
                              ? count + " " + (count === 1 ? qsTr("playlist") : qsTr("playlists"))
                              : count + " " + (count === 1 ? qsTr("item") : qsTr("items"))
                        color: folderRow.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
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
}
