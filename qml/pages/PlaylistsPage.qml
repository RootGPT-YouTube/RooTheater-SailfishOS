import QtQuick 2.6
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import RooTheater.Media 1.0

// Lists the saved playlists (.m3u8/.m3u) of one folder. Tapping a playlist
// parses it into a queue of track paths and opens PlayerPage in album mode.
// Long-pressing a playlist offers a per-playlist cover image or deletion.
Page {
    id: page
    allowedOrientations: Orientation.All

    property string title: ""
    property var items: []   // [{ filePath, fileName, … }, …] of playlist files
    // "audio" → musical-note badge; "video" (future) → square play badge.
    property string kind: "audio"
    // GalleryPage, notified on delete so its cached model stays in sync.
    property QtObject owner

    // Long-press target: { filePath, fileName }, or null when the sheet is hidden.
    property var actionPlaylist: null

    FileOperations { id: fileOps }

    // ── Per-playlist cover choice (dconf JSON map filePath -> image url) ──────
    ConfigurationValue {
        id: playlistCoverConfig
        key: "/apps/harbour-rootheater/playlistCovers"
        defaultValue: "{}"
    }
    property int coverTick: 0   // bumped to refresh cover bindings after a change
    function coverFor(filePath) {
        coverTick                 // binding dependency
        var map = {}
        try { map = JSON.parse(playlistCoverConfig.value) } catch (e) { map = {} }
        return map[filePath] || ""
    }
    function setCover(filePath, url) {
        var map = {}
        try { map = JSON.parse(playlistCoverConfig.value) } catch (e) { map = {} }
        map[filePath] = url
        playlistCoverConfig.value = JSON.stringify(map)
        coverTick++
    }
    function clearCover(filePath) {
        var map = {}
        try { map = JSON.parse(playlistCoverConfig.value) } catch (e) { map = {} }
        if (map[filePath] !== undefined) {
            delete map[filePath]
            playlistCoverConfig.value = JSON.stringify(map)
            coverTick++
        }
    }
    // The chosen cover image for a playlist, or "" → musical-note placeholder.
    function coverSource(filePath) {
        var c = coverFor(filePath)
        if (c && c.length > 0)
            return c.indexOf("file://") === 0 ? c : "file://" + c
        return ""
    }

    function pickCover(filePath) {
        var picker = pageStack.push(Qt.resolvedUrl("CoverPickerPage.qml"),
                                    { caller: page })
        picker.coverSelected.connect(function(path) {
            page.setCover(filePath, path)
        })
    }

    function deletePlaylist(filePath) {
        if (!fileOps.remove(filePath))
            return
        page.clearCover(filePath)
        var arr = page.items.slice()
        for (var i = 0; i < arr.length; ++i) {
            if (arr[i].filePath === filePath) { arr.splice(i, 1); break }
        }
        page.items = arr
        // Keep the gallery's cached model in sync (folder count / row removal).
        if (page.owner && typeof page.owner.removePaths === "function")
            page.owner.removePaths([filePath])
    }

    // Pretty name: the file name without its .m3u8 / .m3u extension.
    function playlistName(fileName) {
        return fileName.replace(/\.(m3u8|m3u)$/i, "")
    }

    // Parse an .m3u/.m3u8 into absolute track paths. Lines starting with '#'
    // are directives (e.g. #EXTM3U, #EXTINF) and are skipped; relative entries
    // are resolved against the playlist's own directory.
    function parsePlaylist(playlistPath) {
        var text = fileOps.readTextFile(playlistPath)
        if (!text)
            return []
        var dir = playlistPath.substring(0, playlistPath.lastIndexOf("/"))
        var lines = text.split(/\r?\n/)
        var paths = []
        for (var i = 0; i < lines.length; ++i) {
            var line = lines[i].trim()
            if (line.length === 0 || line.charAt(0) === "#")
                continue
            if (line.indexOf("file://") === 0)
                line = line.substring(7)
            if (line.charAt(0) !== "/" && line.indexOf("://") < 0)
                line = dir + "/" + line
            paths.push(line)
        }
        return paths
    }

    function openPlaylist(playlistPath) {
        var paths = page.parsePlaylist(playlistPath)
        if (paths.length === 0) {
            emptyBanner.visible = true
            return
        }
        pageStack.push(Qt.resolvedUrl("PlayerPage.qml"),
                       { queue: paths, trackIndex: 0 })
    }

    RemorsePopup { id: remorse }

    SilicaListView {
        anchors.fill: parent
        model: page.items

        header: Column {
            width: page.width
            PageHeader { title: page.title }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                visible: emptyBanner.visible
                id: emptyBanner
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                bottomPadding: Theme.paddingMedium
                text: qsTr("This playlist is empty or could not be read")
            }
        }

        delegate: ListItem {
            id: row
            contentHeight: Theme.itemSizeLarge

            readonly property string coverUrl: page.coverSource(modelData.filePath)

            // Cover thumbnail: the chosen image, else a musical-note (audio) /
            // square-play (video) badge.
            Item {
                id: badge
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: Theme.itemSizeLarge - Theme.paddingMedium
                height: width

                Rectangle {
                    anchors.fill: parent
                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)
                    visible: cover.status !== Image.Ready
                }
                Label {
                    anchors.centerIn: parent
                    visible: cover.status !== Image.Ready && page.kind === "audio"
                    text: "♪"
                    color: Theme.secondaryColor
                    font.pixelSize: parent.height * 0.5
                }
                Image {
                    anchors.centerIn: parent
                    visible: cover.status !== Image.Ready && page.kind !== "audio"
                    source: "image://theme/icon-m-media-playlists?" + Theme.secondaryColor
                }
                Image {
                    id: cover
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    clip: true
                    asynchronous: true
                    cache: false
                    source: row.coverUrl
                }
            }

            Label {
                anchors {
                    left: badge.right
                    leftMargin: Theme.paddingLarge
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                truncationMode: TruncationMode.Fade
                text: page.playlistName(modelData.fileName)
                color: row.highlighted ? Theme.highlightColor : Theme.primaryColor
            }

            onClicked: page.openPlaylist(modelData.filePath)
            onPressAndHold: page.actionPlaylist = { filePath: modelData.filePath,
                                                    fileName: modelData.fileName }
        }

        ViewPlaceholder {
            enabled: page.items.length === 0
            text: qsTr("No playlists")
        }

        VerticalScrollDecorator {}
    }

    // ── Playlist long-press action sheet (slides up from the bottom) ─────────
    Item {
        id: actionOverlay
        anchors.fill: parent
        enabled: page.actionPlaylist !== null
        visible: opacity > 0
        opacity: page.actionPlaylist !== null ? 1.0 : 0.0
        Behavior on opacity { FadeAnimation { duration: 150 } }

        MouseArea {
            anchors.fill: parent
            onClicked: page.actionPlaylist = null
            Rectangle { anchors.fill: parent; color: Theme.rgba("black", 0.6) }
        }

        Rectangle {
            id: sheet
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            anchors.bottomMargin: page.actionPlaylist !== null ? 0 : -height
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
                    text: page.actionPlaylist
                          ? page.playlistName(page.actionPlaylist.fileName) : ""
                }

                Separator {
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: Theme.secondaryColor
                }

                Repeater {
                    model: [
                        { label: qsTr("Playlist cover"),  act: "cover",  icon: "icon-m-image" },
                        { label: qsTr("Delete playlist"), act: "delete", icon: "icon-m-delete" }
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
                            var pl = page.actionPlaylist
                            page.actionPlaylist = null
                            if (!pl) return
                            if (modelData.act === "cover") {
                                page.pickCover(pl.filePath)
                            } else {
                                remorse.execute(qsTr("Deleting"),
                                                function() { page.deletePlaylist(pl.filePath) })
                            }
                        }
                    }
                }
            }
        }
    }
}
