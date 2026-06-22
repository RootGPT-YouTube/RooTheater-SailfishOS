import QtQuick 2.6
import Sailfish.Silica 1.0
import Nemo.Thumbnailer 1.0
import RooTheater.Media 1.0

// In-app image picker built on the gallery's own MediaGalleryModel, so it works
// without the system content-pickers / tracker indexer. Lists the image folders
// of every storage; tapping a folder shows its thumbnail grid; tapping an image
// emits coverSelected(absolutePath) and returns to the caller page.
Page {
    id: pickerPage
    allowedOrientations: Orientation.All

    property var caller            // page to return to after a pick (pop target)
    signal coverSelected(string path)

    StorageRoots { id: storage }

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

    function choose(path) {
        pickerPage.coverSelected(path)
        if (caller)
            pageStack.pop(caller)
        else
            pageStack.pop()
    }

    // Thumbnail grid for one image folder.
    Component {
        id: gridComp
        Page {
            allowedOrientations: Orientation.All
            property string folderTitle: ""
            property var items: []

            SilicaGridView {
                anchors.fill: parent
                header: PageHeader { title: folderTitle }

                property int columns: Math.max(3, Math.floor(width / Theme.itemSizeExtraLarge))
                cellWidth: width / columns
                cellHeight: cellWidth

                model: items
                delegate: BackgroundItem {
                    width: GridView.view.cellWidth
                    height: GridView.view.cellHeight
                    Thumbnail {
                        anchors.fill: parent
                        anchors.margins: Theme.paddingSmall
                        source: modelData.filePath
                        mimeType: modelData.mimeType || ""
                        sourceSize.width: width
                        sourceSize.height: height
                        fillMode: Thumbnail.PreserveAspectCrop
                        clip: true
                    }
                    onClicked: pickerPage.choose(modelData.filePath)
                }

                ViewPlaceholder {
                    enabled: items.length === 0
                    text: qsTr("No images")
                }
                VerticalScrollDecorator {}
            }
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: col.height + Theme.paddingLarge

        Column {
            id: col
            width: pickerPage.width

            PageHeader { title: qsTr("Choose image") }

            Repeater {
                model: pickerPage.rootsList
                delegate: Column {
                    width: col.width
                    readonly property string storageLabel: modelData.label

                    MediaGalleryModel {
                        id: rootModel
                        rootPath: modelData.path
                    }

                    Repeater {
                        model: rootModel
                        delegate: BackgroundItem {
                            id: folderRow
                            width: col.width
                            height: Theme.itemSizeLarge
                            visible: typeKey === "image"

                            Thumbnail {
                                id: prev
                                x: Theme.horizontalPageMargin
                                anchors.verticalCenter: parent.verticalCenter
                                width: Theme.itemSizeLarge - Theme.paddingMedium
                                height: width
                                source: items.length > 0 ? items[0].filePath : ""
                                mimeType: items.length > 0 ? (items[0].mimeType || "") : ""
                                sourceSize.width: width
                                sourceSize.height: height
                                fillMode: Thumbnail.PreserveAspectCrop
                                clip: true
                            }

                            Column {
                                anchors {
                                    left: prev.right
                                    leftMargin: Theme.paddingLarge
                                    right: parent.right
                                    rightMargin: Theme.horizontalPageMargin
                                    verticalCenter: parent.verticalCenter
                                }
                                Label {
                                    width: parent.width
                                    truncationMode: TruncationMode.Fade
                                    text: folderName + " · " + storageLabel
                                    color: folderRow.highlighted ? Theme.highlightColor
                                                                 : Theme.primaryColor
                                }
                                Label {
                                    text: count + " " + (count === 1 ? qsTr("item") : qsTr("items"))
                                    color: folderRow.highlighted ? Theme.secondaryHighlightColor
                                                                 : Theme.secondaryColor
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }

                            onClicked: pageStack.push(gridComp,
                                                      { folderTitle: folderName, items: items })
                        }
                    }
                }
            }
        }

        ViewPlaceholder {
            // Shown only when no storage has any images at all.
            enabled: false
            text: qsTr("No images")
        }
        VerticalScrollDecorator {}
    }
}
