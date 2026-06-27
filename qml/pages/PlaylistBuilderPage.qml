import QtQuick 2.6
import Sailfish.Silica 1.0
import RooTheater.Media 1.0

// Build a playlist by picking tracks file-by-file from every storage. Sections
// are the folders of the chosen media type (across internal / Android / SD); the
// saved .m3u8 lands in the Music (audio) / Videos (video) folder of the tracks'
// storage, or — when the picks span several storages — in internal memory.
Page {
    id: page
    allowedOrientations: Orientation.All

    // "audio" → audio folders, saved under Music/; "video" → video folders,
    // saved under Videos/. Same rules either way.
    property string mediaType: "audio"
    readonly property bool isVideo: mediaType === "video"

    // GalleryPage, refreshed after a save so the new playlist shows up at once.
    property QtObject owner

    StorageRoots { id: storage }
    FileOperations { id: fileOps }

    // [{ label, path }] for every existing storage root.
    readonly property var rootsList: {
        var r = []
        if (storage.internalRoot)
            r.push({ label: qsTr("Internal memory"), path: storage.internalRoot })
        if (storage.androidRoot)
            r.push({ label: qsTr("Android storage"), path: storage.androidRoot })
        for (var i = 0; i < storage.sdcardRoots.length; ++i)
            r.push({ label: qsTr("SD card"), path: storage.sdcardRoots[i] })
        return r
    }

    // Selection: filePath -> true.
    property var selected: ({})
    property int selectedCount: 0
    property int selectionTick: 0   // bump to refresh delegate check bindings

    function isSelected(fp) {
        selectionTick
        return selected[fp] === true
    }
    function toggle(fp) {
        if (selected[fp]) { delete selected[fp]; selectedCount-- }
        else { selected[fp] = true; selectedCount++ }
        selectionTick++
    }
    function selectedPaths() {
        selectionTick
        return Object.keys(selected)
    }

    // Longest matching root prefix → the storage a file lives in.
    function storageOf(filePath) {
        var best = ""
        for (var i = 0; i < rootsList.length; ++i) {
            var p = rootsList[i].path
            if (p && filePath.indexOf(p) === 0 && p.length > best.length)
                best = p
        }
        return best
    }
    // Where to save: the common storage's media folder (Music/audio, Videos/video),
    // else internal memory's.
    function targetDir(paths) {
        var set = {}
        for (var i = 0; i < paths.length; ++i)
            set[storageOf(paths[i])] = true
        var keys = Object.keys(set)
        var base = (keys.length === 1 && keys[0] !== "") ? keys[0] : storage.internalRoot
        return base + (page.isVideo ? "/Videos" : "/Music")
    }

    function savePlaylist(name) {
        var paths = selectedPaths()
        if (paths.length === 0)
            return
        var file = targetDir(paths) + "/" + name + ".m3u8"
        var content = "#EXTM3U\n" + paths.join("\n") + "\n"
        if (fileOps.writeTextFile(file, content)) {
            savedBanner.text = qsTr("Saved: %1").arg(file)
            savedBanner.visible = true
            page.selected = ({}); page.selectedCount = 0; page.selectionTick++
            // Make the new playlist appear in the gallery without a manual reload.
            if (page.owner && typeof page.owner.refresh === "function")
                page.owner.refresh()
        } else {
            savedBanner.text = qsTr("Could not save the playlist")
            savedBanner.visible = true
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                text: qsTr("Save playlist (%1)").arg(page.selectedCount)
                enabled: page.selectedCount > 0
                onClicked: pageStack.push(nameDialog)
            }
        }

        Column {
            id: column
            width: page.width

            PageHeader {
                title: page.selectedCount > 0
                       ? qsTr("%1 selected").arg(page.selectedCount)
                       : (page.isVideo ? qsTr("Create video playlist")
                                       : qsTr("Create audio playlist"))
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                visible: savedBanner.visible
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                bottomPadding: Theme.paddingMedium
                id: savedBanner
            }

            // One scanning model per storage root; each contributes its audio
            // folders as sections of selectable tracks.
            Repeater {
                model: page.rootsList

                delegate: Column {
                    width: column.width
                    readonly property string storageLabel: modelData.label

                    MediaGalleryModel {
                        id: rootModel
                        rootPath: modelData.path
                    }

                    Repeater {
                        model: rootModel

                        delegate: Column {
                            width: column.width
                            visible: typeKey === page.mediaType

                            SectionHeader {
                                text: folderName + " · " + storageLabel
                            }

                            Repeater {
                                model: items
                                delegate: BackgroundItem {
                                    id: trackRow
                                    width: column.width
                                    readonly property bool sel: page.isSelected(modelData.filePath)
                                    highlighted: down || sel

                                    Row {
                                        x: Theme.horizontalPageMargin
                                        width: parent.width - 2 * Theme.horizontalPageMargin
                                        height: parent.height
                                        spacing: Theme.paddingLarge

                                        Image {
                                            anchors.verticalCenter: parent.verticalCenter
                                            source: "image://theme/"
                                                    + (trackRow.sel ? "icon-m-acknowledge?" + Theme.highlightColor
                                                                    : "icon-m-add")
                                        }
                                        Label {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - Theme.iconSizeMedium - Theme.paddingLarge
                                            truncationMode: TruncationMode.Fade
                                            text: modelData.fileName
                                            color: trackRow.highlighted ? Theme.highlightColor
                                                                        : Theme.primaryColor
                                        }
                                    }

                                    onClicked: page.toggle(modelData.filePath)
                                }
                            }
                        }
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }

    Component {
        id: nameDialog
        Dialog {
            property alias name: nameField.text
            canAccept: nameField.text.trim().length > 0
            onAccepted: page.savePlaylist(nameField.text.trim())

            Column {
                width: parent.width
                DialogHeader { title: qsTr("Playlist name") }
                TextField {
                    id: nameField
                    width: parent.width
                    text: qsTr("Playlist")
                    label: qsTr("Name")
                    inputMethodHints: Qt.ImhNoAutoUppercase
                    EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                    EnterKey.onClicked: parent.parent.accept()
                }
            }
        }
    }
}
