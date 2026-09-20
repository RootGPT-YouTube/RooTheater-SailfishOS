import QtQuick 2.6
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0

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

            // ── YouTube ───────────────────────────────────────────────────────
            // Measured on a POCO M4 Pro on 2026-09-20, same video, minutes apart:
            // in VP9 the picture stalled over and over — 1437 frames thrown away,
            // the decoder stopping dead for seconds at a time with the data already
            // buffered — while in H.264 it ran two and a half minutes without
            // losing a single frame. Hence ON by default.
            //
            // What we deliberately do NOT claim here is that H.264 looks worse. It
            // played at 640x360 where VP9 had been at 1280x720, which is tempting
            // to write down as the price of the switch, but the same afternoon a
            // hand-picked 1080p was served in H.264 too (1920x1080, confirmed by
            // the decoder itself). So the lower resolution was ABR's choice in that
            // moment, not a property of the codec, and the description must not
            // turn an unverified impression into a promise to the user.
            SectionHeader {
                text: qsTr("YouTube")
            }
            TextSwitch {
                width: parent.width
                automaticCheck: false
                checked: ytH264.value !== false && ytH264.value !== "false"
                text: qsTr("Use H.264 for YouTube")
                description: qsTr("Play YouTube videos in H.264 instead of VP9. On some phones the VP9 decoder stops delivering frames and the picture freezes while the sound carries on; H.264 goes through a different decoder that does not suffer from it. Takes effect on the next video.")
                onClicked: ytH264.value = !checked

                ConfigurationValue {
                    id: ytH264
                    key: "/apps/harbour-rootheater/yt/forceH264"
                    defaultValue: true
                }
            }
        }
    }
}
