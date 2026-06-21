import QtQuick 2.0
import Sailfish.Silica 1.0
import RooTheater.Media 1.0

Page {
    id: page
    allowedOrientations: Orientation.All

    // Discovered at startup: internal / Android / SD-card roots for the gallery.
    StorageRoots { id: storage }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                text: qsTr("About")
                onClicked: pageStack.push(Qt.resolvedUrl("AboutPage.qml"))
            }
            MenuItem {
                text: qsTr("Open network stream…")
                onClicked: page.openUrlDialog()
            }
        }

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: "RooTheater"
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                color: Theme.secondaryHighlightColor
                text: qsTr("Pull down to open a network stream.")
            }

            // Gallery: three storage categories. Each opens a folder-grouped grid
            // of the images and videos found under that storage root.
            Repeater {
                model: [
                    { title: qsTr("Internal memory"), icon: "image://theme/icon-m-device",
                      root: storage.internalRoot },
                    { title: qsTr("Android storage"), icon: "image://theme/icon-m-other",
                      root: storage.androidRoot },
                    { title: qsTr("SD card"), icon: "image://theme/icon-m-sd-card",
                      root: storage.sdcardRoots.length > 0 ? storage.sdcardRoots[0] : "" }
                ]
                delegate: BackgroundItem {
                    width: page.width
                    onClicked: pageStack.push(Qt.resolvedUrl("GalleryPage.qml"),
                                              { rootPath: modelData.root, title: modelData.title })
                    Row {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        height: parent.height
                        spacing: Theme.paddingLarge
                        Image {
                            anchors.verticalCenter: parent.verticalCenter
                            source: modelData.icon
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.title
                            color: highlighted ? Theme.highlightColor : Theme.primaryColor
                        }
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }

    function play(source) {
        if (!source || source === "")
            return
        pageStack.push(Qt.resolvedUrl("PlayerPage.qml"), { source: source })
    }

    function openUrlDialog() {
        var dialog = pageStack.push(urlDialog)
        dialog.accepted.connect(function() {
            page.play(dialog.url)
        })
    }

    Component {
        id: urlDialog
        Dialog {
            property alias url: urlField.text
            canAccept: urlField.text.length > 0

            Column {
                width: parent.width
                DialogHeader {
                    title: qsTr("Network stream")
                }
                TextField {
                    id: urlField
                    width: parent.width
                    inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                    placeholderText: qsTr("URL (http, https, rtsp, rtmp…)")
                    label: qsTr("Stream URL")
                    EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                    EnterKey.onClicked: parent.parent.accept()
                }
            }
        }
    }
}
