import QtQuick 2.6
import Sailfish.Silica 1.0

// "Options" hub reached from the Home pulldown: app permissions first
// (privacy front and centre), then the about page. "About RooTheater" is a
// brand label kept untranslated across the RooT* family.
Page {
    id: optionsPage
    allowedOrientations: Orientation.All

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: contentColumn.height

        VerticalScrollDecorator {}

        Column {
            id: contentColumn
            width: parent.width

            PageHeader {
                title: qsTr("Options")
            }

            Repeater {
                model: [
                    { label: qsTr("Permissions"),
                      sub: qsTr("Choose which resources RooTheater may use"),
                      icon: "icon-m-device-lock",
                      target: "AppPermissionsPage.qml" },
                    { label: "About RooTheater",
                      sub: qsTr("Version, license and credits"),
                      icon: "icon-m-about",
                      target: "AboutPage.qml" }
                ]
                delegate: BackgroundItem {
                    width: contentColumn.width
                    height: Theme.itemSizeMedium

                    Image {
                        id: rowIcon
                        x: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        source: "image://theme/" + modelData.icon + "?"
                                + (highlighted ? Theme.highlightColor : Theme.primaryColor)
                    }
                    Column {
                        anchors {
                            left: rowIcon.right
                            leftMargin: Theme.paddingLarge
                            right: parent.right
                            rightMargin: Theme.horizontalPageMargin
                            verticalCenter: parent.verticalCenter
                        }
                        Label {
                            width: parent.width
                            truncationMode: TruncationMode.Fade
                            text: modelData.label
                            color: highlighted ? Theme.highlightColor : Theme.primaryColor
                        }
                        Label {
                            width: parent.width
                            truncationMode: TruncationMode.Fade
                            text: modelData.sub
                            color: highlighted ? Theme.secondaryHighlightColor
                                               : Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                    onClicked: pageStack.push(Qt.resolvedUrl(modelData.target))
                }
            }
        }
    }
}
