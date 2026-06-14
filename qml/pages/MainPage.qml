import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Pickers 1.0

Page {
    id: page
    allowedOrientations: Orientation.All

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
            MenuItem {
                text: qsTr("Open file…")
                onClicked: page.openFilePicker()
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
                text: qsTr("Pull down to open a local file or a network stream.")
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Open file")
                onClicked: page.openFilePicker()
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Open network stream")
                onClicked: page.openUrlDialog()
            }
        }

        VerticalScrollDecorator {}
    }

    function play(source) {
        if (!source || source === "")
            return
        pageStack.push(Qt.resolvedUrl("PlayerPage.qml"), { source: source })
    }

    function openFilePicker() {
        var picker = pageStack.push("Sailfish.Pickers.FilePickerPage", {
            title: qsTr("Select media file")
        })
        picker.selectedContentPropertiesChanged.connect(function() {
            page.play(picker.selectedContentProperties.filePath)
        })
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
