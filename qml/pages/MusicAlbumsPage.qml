import QtQuick 2.6
import Sailfish.Silica 1.0
import "MusicQueries.js" as MusicQueries

// Album list from the system Tracker index. Each row carries a sample track
// url, so the cover shows that track's embedded art (rttrackcover provider).
Page {
    id: page
    allowedOrientations: Orientation.All

    property string rootPath: ""
    property string excludePath: ""
    property var artistFilter: undefined   // optional artist scope

    property string sortBy: "album"        // "album" | "artist"
    property bool sortDesc: false

    TrackerMusicModel {
        id: albumsModel
        query: MusicQueries.albumsQuery({
            rootPath: page.rootPath,
            excludePath: page.excludePath,
            unknownArtist: qsTr("Unknown artist"),
            unknownAlbum: qsTr("Unknown album"),
            multipleArtists: qsTr("Multiple artists"),
            artistFilter: page.artistFilter,
            sortBy: page.sortBy,
            sortDesc: page.sortDesc
        })
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: albumsModel

        header: PageHeader { title: qsTr("Albums") }

        PullDownMenu {
            MenuItem {
                text: qsTr("Sorting")
                onClicked: pageStack.push(sortDialog)
            }
        }

        delegate: ListItem {
            id: albumItem
            contentHeight: Theme.itemSizeLarge

            Item {
                id: albumCover
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
                    source: String(media.url) !== ""
                            ? "image://rttrackcover/"
                              + encodeURIComponent(MusicQueries.urlToPath(media.url))
                            : ""
                }
            }

            Column {
                anchors {
                    left: albumCover.right
                    leftMargin: Theme.paddingLarge
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    text: media.title
                    color: albumItem.highlighted ? Theme.highlightColor
                                                 : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    text: media.author + " · " + media.childCount + " "
                          + (media.childCount === 1 ? qsTr("song") : qsTr("songs"))
                    color: albumItem.highlighted ? Theme.secondaryHighlightColor
                                                 : Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            onClicked: pageStack.push(Qt.resolvedUrl("MusicSongsPage.qml"),
                                      { title: media.title,
                                        subtitle: media.author,
                                        rootPath: page.rootPath,
                                        excludePath: page.excludePath,
                                        albumId: media.id })
        }

        ViewPlaceholder {
            enabled: !albumsModel.fetching && albumsModel.count === 0
            text: qsTr("No albums")
            hintText: qsTr("Music indexed by the system appears here")
        }

        VerticalScrollDecorator {}
    }

    BusyIndicator {
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
        running: albumsModel.fetching && albumsModel.count === 0
        visible: running
    }

    Component {
        id: sortDialog
        Dialog {
            onAccepted: {
                page.sortBy = sortCombo.currentIndex === 1 ? "artist" : "album"
                page.sortDesc = orderCombo.currentIndex === 1
            }
            Column {
                width: parent.width
                spacing: Theme.paddingLarge

                DialogHeader { title: qsTr("Sorting") }

                ComboBox {
                    id: sortCombo
                    label: qsTr("Sort by")
                    currentIndex: page.sortBy === "artist" ? 1 : 0
                    menu: ContextMenu {
                        MenuItem { text: qsTr("Album") }
                        MenuItem { text: qsTr("Artist") }
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
