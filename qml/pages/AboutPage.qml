import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: aboutPage
    allowedOrientations: Orientation.All

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: aboutPage.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: qsTr("About RooTheater")
            }

            Label {
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                text: "RooTheater " + (typeof appVersion !== "undefined" ? appVersion : "")
                font.pixelSize: Theme.fontSizeExtraLarge
                color: Theme.primaryColor
            }

            Label {
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: qsTr("A multimedia player for Sailfish OS")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryColor
            }

            Label {
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: qsTr("Created by RootGPT alongside Claude Opus.")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.primaryColor
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "<a href=\"https://github.com/RootGPT-YouTube/RooTheater-SailfishOS\">" + qsTr("Source code on GitHub") + "</a>"
                font.pixelSize: Theme.fontSizeSmall
                linkColor: Theme.highlightColor
                onLinkActivated: Qt.openUrlExternally(link)
            }

            Separator {
                width: parent.width
                color: Theme.secondaryColor
                horizontalAlignment: Qt.AlignHCenter
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Licensed under GNU GPLv3")
                font.pixelSize: Theme.fontSizeSmall
            }

            // ── Open-source components & their licenses ──────────────────
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Open-source components")
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeSmall
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: qsTr("Built with Qt and Sailfish Silica.")
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: qsTr("Hardware-accelerated decoding uses the Sailfish OS droidmedia / gst-droid stack over the Android HAL (libhybris). Thanks for making it available under the LGPL v2.1+!")
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "<a href=\"https://github.com/sailfishos/droidmedia\">" + qsTr("Open droidmedia on GitHub") + "</a>"
                font.pixelSize: Theme.fontSizeSmall
                linkColor: Theme.highlightColor
                onLinkActivated: Qt.openUrlExternally(link)
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: qsTr("This app uses FFmpeg (libavformat / libavcodec) to demux and probe media and for software decoding. Thanks for making it available under the LGPL v2.1+ / GPL v2+!")
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "<a href=\"https://ffmpeg.org\">" + qsTr("Open FFmpeg website") + "</a>"
                font.pixelSize: Theme.fontSizeSmall
                linkColor: Theme.highlightColor
                onLinkActivated: Qt.openUrlExternally(link)
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: qsTr("This app uses libVLC by the VideoLAN project for broad format, codec and streaming support. Thanks for making it available under the LGPL v2.1+!")
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "<a href=\"https://www.videolan.org/vlc/libvlc.html\">" + qsTr("Open libVLC website") + "</a>"
                font.pixelSize: Theme.fontSizeSmall
                linkColor: Theme.highlightColor
                onLinkActivated: Qt.openUrlExternally(link)
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                text: qsTr("The full license texts are shipped in /usr/share/harbour-rootheater/licenses/.")
                font.pixelSize: Theme.fontSizeExtraSmall
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                text: "© 2026 RootGPT"
                font.pixelSize: Theme.fontSizeExtraSmall
            }
        }

        VerticalScrollDecorator {}
    }
}
