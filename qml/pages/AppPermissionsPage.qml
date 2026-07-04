import QtQuick 2.6
import Sailfish.Silica 1.0

// Soft permission gate, modelled on RooTelegram's AppPermissionsPage:
// SailfishOS (Sailjail) grants all the permissions declared in the .desktop
// in one go at startup. This page does NOT revoke the system permission
// (only the SailfishOS Settings can): each switch is an app-side gate that
// RooTheater respects BEFORE using the resource. Default: all granted.
Page {
    id: appPermissionsPage
    allowedOrientations: Orientation.All

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: contentColumn.height

        VerticalScrollDecorator {}

        Column {
            id: contentColumn
            width: parent.width
            bottomPadding: Theme.paddingLarge

            PageHeader {
                title: qsTr("App permissions")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("Turn off the resources you don't want RooTheater to use. This only blocks the app internally — to fully revoke a system permission use the SailfishOS Settings.")
            }

            // --- Network ------------------------------------------------------
            SectionHeader {
                text: qsTr("Network")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                text: qsTr("Safe to turn off: RooTheater keeps working fully offline with your local media.")
            }

            PermissionSwitch {
                perm: "internet"
                text: qsTr("Internet")
                description: qsTr("YouTube (search, subscriptions, playback) and network streams. When off, those entries disappear from the Home page and the app makes no network connections.")
            }

            // --- Media library ------------------------------------------------
            SectionHeader {
                text: qsTr("Media library")
            }

            PermissionSwitch {
                perm: "medialibrary"
                text: qsTr("System media index")
                description: qsTr("The All songs / Albums / Artists views read the system media index (Tracker), the same source the stock Media app uses. When off, the Audio section only offers folder browsing.")
            }

            // --- Storages ------------------------------------------------------
            SectionHeader {
                text: qsTr("Storages")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                text: qsTr("A storage turned off is hidden from the Home page and never scanned.")
            }

            PermissionSwitch {
                perm: "android"
                text: qsTr("Android storage")
                description: qsTr("Media shared with Android App Support apps.")
            }
            PermissionSwitch {
                perm: "sdcard"
                text: qsTr("SD card")
                description: qsTr("Media on removable memory cards.")
            }

            // --- System permissions (informative, not gateable) ----------------
            SectionHeader {
                text: qsTr("System permissions")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                text: qsTr("Access to your files, audio playback and other low-level permissions are managed by SailfishOS. To revoke them, open the system Settings → Apps → RooTheater.")
            }
        }
    }
}
