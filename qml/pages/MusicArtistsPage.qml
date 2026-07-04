import QtQuick 2.6
import Sailfish.Silica 1.0
import "MusicQueries.js" as MusicQueries

// Artist list from the system Tracker index (album artist wins over track
// artist, like the stock Media app). Tapping an artist lists their songs.
Page {
    id: page
    allowedOrientations: Orientation.All

    property string rootPath: ""
    property string excludePath: ""

    property string sortBy: "name"         // "name" | "count"
    property bool sortDesc: false

    TrackerMusicModel {
        id: artistsModel
        query: MusicQueries.artistsQuery({
            rootPath: page.rootPath,
            excludePath: page.excludePath,
            unknownArtist: qsTr("Unknown artist"),
            sortBy: page.sortBy,
            sortDesc: page.sortDesc
        })
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: artistsModel

        header: PageHeader { title: qsTr("Artists") }

        PullDownMenu {
            MenuItem {
                text: qsTr("Sorting")
                onClicked: pageStack.push(sortDialog)
            }
        }

        delegate: ListItem {
            id: artistItem
            contentHeight: Theme.itemSizeMedium

            Image {
                id: artistIcon
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                source: "image://theme/icon-m-media-artists?"
                        + (artistItem.highlighted ? Theme.highlightColor
                                                  : Theme.primaryColor)
            }
            Column {
                anchors {
                    left: artistIcon.right
                    leftMargin: Theme.paddingLarge
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    text: media.title
                    color: artistItem.highlighted ? Theme.highlightColor
                                                  : Theme.primaryColor
                }
                Label {
                    text: media.childCount + " "
                          + (media.childCount === 1 ? qsTr("song") : qsTr("songs"))
                    color: artistItem.highlighted ? Theme.secondaryHighlightColor
                                                  : Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            onClicked: pageStack.push(Qt.resolvedUrl("MusicSongsPage.qml"),
                                      { title: media.title,
                                        rootPath: page.rootPath,
                                        excludePath: page.excludePath,
                                        artistFilter: media.id ? String(media.id) : "" })
        }

        ViewPlaceholder {
            enabled: !artistsModel.fetching && artistsModel.count === 0
            text: qsTr("No artists")
            hintText: qsTr("Music indexed by the system appears here")
        }

        VerticalScrollDecorator {}
    }

    BusyIndicator {
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
        running: artistsModel.fetching && artistsModel.count === 0
        visible: running
    }

    Component {
        id: sortDialog
        Dialog {
            onAccepted: {
                page.sortBy = sortCombo.currentIndex === 1 ? "count" : "name"
                page.sortDesc = orderCombo.currentIndex === 1
            }
            Column {
                width: parent.width
                spacing: Theme.paddingLarge

                DialogHeader { title: qsTr("Sorting") }

                ComboBox {
                    id: sortCombo
                    label: qsTr("Sort by")
                    currentIndex: page.sortBy === "count" ? 1 : 0
                    menu: ContextMenu {
                        MenuItem { text: qsTr("Name") }
                        MenuItem { text: qsTr("Songs") }
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
