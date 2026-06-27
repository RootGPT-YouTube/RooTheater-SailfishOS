import QtQuick 2.6
import Sailfish.Silica 1.0
import QtGraphicalEffects 1.0

CoverBackground {
    id: cover

    // Idle and media share the same look: a title + subtitle at the top, and the
    // greyscale "RT" app icon filling the area below.
    readonly property bool branding: coverState.mode === "none" || coverState.mode === "media"
    // A track/playlist with embedded cover art → show it instead of the app icon.
    readonly property bool hasArt: coverState.mode === "media" && coverState.coverArt !== ""

    // ── Header: app name / track title + subtitle ────────────────────────────
    Column {
        id: header
        anchors {
            top: parent.top
            topMargin: Theme.paddingLarge
            left: parent.left; right: parent.right
            leftMargin: Theme.paddingMedium; rightMargin: Theme.paddingMedium
        }
        spacing: Theme.paddingSmall
        visible: cover.branding

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: coverState.mode === "media" ? coverState.title : "RooTheater"
            font.pixelSize: Theme.fontSizeLarge
            color: Theme.highlightColor
            wrapMode: Text.Wrap
            maximumLineCount: 2
            truncationMode: TruncationMode.Fade
        }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: coverState.mode === "media" ? coverState.subtitle : qsTr("Multimedia player")
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryColor
            wrapMode: Text.Wrap
            maximumLineCount: 1
            truncationMode: TruncationMode.Fade
        }
    }

    // ── Greyscale app icon filling the area below the header ──────────────────
    Item {
        id: iconArea
        visible: cover.branding
        clip: true
        anchors {
            top: header.bottom
            topMargin: Theme.paddingMedium
            left: parent.left; right: parent.right
            bottom: parent.bottom
        }

        Image {
            id: brandIcon
            anchors.centerIn: parent
            // Cover art fills the area; the app icon shows at 80% of the smaller side.
            width: cover.hasArt ? parent.width : Math.min(parent.width, parent.height) * 0.8
            height: cover.hasArt ? parent.height : width
            source: cover.hasArt ? coverState.coverArt
                                 : Qt.resolvedUrl("../images/harbour-rootheater.svg")
            sourceSize.width: width
            sourceSize.height: height
            fillMode: cover.hasArt ? Image.PreserveAspectCrop : Image.PreserveAspectFit
            smooth: true
            asynchronous: true
            cache: false
            // Greyscale only for the app icon (real cover art stays in colour).
            layer.enabled: !cover.hasArt
            layer.effect: Desaturate { desaturation: 1.0 }
        }
    }

    // ── Image open: show the picture preview (EXIF-corrected) ────────────────
    Image {
        anchors.fill: parent
        visible: coverState.mode === "image"
        source: coverState.mode === "image" ? coverState.imagePath : ""
        fillMode: Image.PreserveAspectCrop
        autoTransform: true        // honour EXIF orientation (portrait photos)
        sourceSize.width: width
        sourceSize.height: height
        clip: true
        asynchronous: true
        cache: false
    }

    // Media controls (Sailfish covers allow up to two): play/pause + next.
    CoverActionList {
        enabled: coverState.mode === "media"
        CoverAction {
            iconSource: coverState.playing ? "image://theme/icon-cover-pause"
                                           : "image://theme/icon-cover-play"
            onTriggered: coverState.requestPlayPause()
        }
        CoverAction {
            iconSource: "image://theme/icon-cover-next-song"
            onTriggered: coverState.requestNext()
        }
    }
}
