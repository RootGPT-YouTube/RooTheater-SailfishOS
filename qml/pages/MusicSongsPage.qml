import QtQuick 2.6
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import "MusicQueries.js" as MusicQueries

// Track list backed by the system Tracker index: "All songs" of a storage,
// or the songs of one album / one artist (set albumId / artistFilter).
// Sorting runs server-side in SPARQL; unknown tags always sort last.
Page {
    id: page
    allowedOrientations: Orientation.All

    property string title: ""
    property string subtitle: ""          // e.g. the album's artist
    property string rootPath: ""
    property string excludePath: ""
    property string albumId: ""            // "" = no filter, "0" = unknown album, else urn
    property var artistFilter: undefined   // undefined = no filter, "" = unknown artist, else name

    // Default order: Track inside an album, Album otherwise (native behaviour).
    property string sortBy: albumId !== "" ? "track" : "album"
    property bool sortDesc: false

    readonly property var sortModes: ["title", "track", "artist", "album", "date"]

    // Persist the chosen sort for the plain "All songs" view of each storage.
    readonly property bool isAllSongs: albumId === "" && artistFilter === undefined
    ConfigurationValue {
        id: sortConfig
        key: "/apps/harbour-rootheater/musicSort"
        defaultValue: "{}"
    }
    function loadPrefs() {
        if (!isAllSongs)
            return
        try {
            var p = JSON.parse(sortConfig.value)[rootPath + "|songs"]
            if (p) { sortBy = p.s; sortDesc = p.d }
        } catch (e) {}
    }
    function savePrefs() {
        if (!isAllSongs)
            return
        var map = {}
        try { map = JSON.parse(sortConfig.value) } catch (e) { map = {} }
        map[rootPath + "|songs"] = { s: sortBy, d: sortDesc }
        sortConfig.value = JSON.stringify(map)
    }
    Component.onCompleted: loadPrefs()

    TrackerMusicModel {
        id: songsModel
        query: MusicQueries.songsQuery({
            rootPath: page.rootPath,
            excludePath: page.excludePath,
            unknownArtist: qsTr("Unknown artist"),
            unknownAlbum: qsTr("Unknown album"),
            albumId: page.albumId,
            artistFilter: page.artistFilter,
            sortBy: page.sortBy,
            sortDesc: page.sortDesc
        })
    }

    // Play the listed tracks as a queue starting at `idx`, handing the
    // Tracker metadata along so the player shows proper titles even for
    // files our own probe cannot parse.
    function playFrom(idx) {
        var paths = []
        var meta = ({})
        for (var i = 0; i < songsModel.count; ++i) {
            var m = songsModel.getMediaItem(i)
            var p = MusicQueries.urlToPath(m.url)
            paths.push(p)
            meta[p] = { title: m.title, artist: m.author, album: m.album }
        }
        if (paths.length === 0)
            return
        pageStack.push(Qt.resolvedUrl("PlayerPage.qml"),
                       { queue: paths, trackIndex: idx, queueMeta: meta })
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: songsModel

        header: PageHeader {
            title: page.title
            description: page.subtitle
        }

        PullDownMenu {
            MenuItem {
                text: qsTr("Sorting")
                onClicked: pageStack.push(sortDialog)
            }
            MenuItem {
                text: qsTr("Play all")
                enabled: songsModel.count > 0
                onClicked: page.playFrom(0)
            }
        }

        delegate: ListItem {
            id: songItem
            contentHeight: Theme.itemSizeMedium

            Label {
                id: durationLabel
                anchors {
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                text: media.duration > 0 ? MusicQueries.formatDuration(media.duration) : ""
                color: songItem.highlighted ? Theme.secondaryHighlightColor
                                            : Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
            Column {
                anchors {
                    left: parent.left
                    leftMargin: Theme.horizontalPageMargin
                    right: durationLabel.left
                    rightMargin: Theme.paddingMedium
                    verticalCenter: parent.verticalCenter
                }
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    text: media.title
                    color: songItem.highlighted ? Theme.highlightColor
                                                : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    // Inside an album the album name is redundant.
                    text: page.albumId !== "" ? media.author
                                              : media.author + " · " + media.album
                    color: songItem.highlighted ? Theme.secondaryHighlightColor
                                                : Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
            onClicked: page.playFrom(index)
        }

        ViewPlaceholder {
            enabled: !songsModel.fetching && songsModel.count === 0
            text: qsTr("No songs")
            hintText: qsTr("Music indexed by the system appears here")
        }

        VerticalScrollDecorator {}
    }

    BusyIndicator {
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
        running: songsModel.fetching && songsModel.count === 0
        visible: running
    }

    Component {
        id: sortDialog
        Dialog {
            onAccepted: {
                page.sortBy = page.sortModes[sortCombo.currentIndex]
                page.sortDesc = orderCombo.currentIndex === 1
                page.savePrefs()
            }
            Column {
                width: parent.width
                spacing: Theme.paddingLarge

                DialogHeader { title: qsTr("Sorting") }

                ComboBox {
                    id: sortCombo
                    label: qsTr("Sort by")
                    currentIndex: page.sortModes.indexOf(page.sortBy)
                    menu: ContextMenu {
                        MenuItem { text: qsTr("Title") }
                        MenuItem { text: qsTr("Track") }
                        MenuItem { text: qsTr("Artist") }
                        MenuItem { text: qsTr("Album") }
                        MenuItem { text: qsTr("Date") }
                    }
                }
                ComboBox {
                    id: orderCombo
                    label: qsTr("Order")
                    currentIndex: page.sortDesc ? 1 : 0
                    menu: ContextMenu {
                        MenuItem { text: qsTr("Ascending") }
                        MenuItem { text: qsTr("Descending") }
                    }
                }
            }
        }
    }
}
