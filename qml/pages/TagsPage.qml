import QtQuick 2.6
import Sailfish.Silica 1.0
import RooTheater.Media 1.0

// Read-only metadata view for a single audio file: cover art + every tag the
// container/streams carry (title, artist, album, …), read asynchronously by the
// shared TagReader element.
Page {
    id: page
    allowedOrientations: Orientation.All

    property string filePath: ""
    property string fileName: ""

    // Flattened, sorted [{ key, value }] list built from TagReader.tags.
    property var rows: []

    // Friendlier labels for the common keys; anything else is shown capitalised.
    function friendly(key) {
        var m = {
            title: qsTr("Title"), artist: qsTr("Artist"), album: qsTr("Album"),
            album_artist: qsTr("Album artist"), composer: qsTr("Composer"),
            genre: qsTr("Genre"), date: qsTr("Year"), track: qsTr("Track"),
            disc: qsTr("Disc"), comment: qsTr("Comment"),
            publisher: qsTr("Publisher"), encoder: qsTr("Encoder"),
            copyright: qsTr("Copyright"), language: qsTr("Language")
        }
        return m[key] || (key.charAt(0).toUpperCase() + key.slice(1))
    }

    function buildRows() {
        var t = reader.tags
        var keys = Object.keys(t).sort()
        var r = []
        for (var i = 0; i < keys.length; ++i)
            r.push({ key: keys[i], value: t[keys[i]] })
        rows = r
    }

    TagReader {
        id: reader
        filePath: page.filePath
    }
    Connections {
        target: reader
        onTagsChanged: page.buildRows()
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: col.height + Theme.paddingLarge

        Column {
            id: col
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: reader.title !== "" ? reader.title : page.fileName
            }

            // Cover art (embedded), or a ♪ placeholder.
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(page.width, page.height) * 0.5
                height: width

                Label {
                    anchors.centerIn: parent
                    visible: cover.status !== Image.Ready
                    text: "♪"
                    color: Theme.secondaryColor
                    font.pixelSize: parent.height * 0.5
                }
                Image {
                    id: cover
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                    source: page.filePath !== ""
                            ? "image://rttrackcover/" + encodeURIComponent(page.filePath)
                            : ""
                }
            }

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                size: BusyIndicatorSize.Medium
                running: !reader.ready
                visible: running
            }

            Repeater {
                model: page.rows
                delegate: DetailItem {
                    label: page.friendly(modelData.key)
                    value: modelData.value
                }
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                topPadding: Theme.paddingLarge
                visible: reader.ready && page.rows.length === 0
                text: qsTr("No tags")
                color: Theme.secondaryColor
            }
        }

        VerticalScrollDecorator {}
    }
}
