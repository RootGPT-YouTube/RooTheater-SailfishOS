import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Pickers 1.0

// VLC-style track picker for the playing media: video track, audio track (or
// none), subtitles (off, a track inside the file, or an external file picked
// here). Every choice is applied at once by PlayerPage and lasts until the
// media is closed.
Page {
    id: tracksPage
    allowedOrientations: Orientation.All

    // The PlayerPage that opened us: owns the choices and applies them.
    property var player

    function tracksOf(type) {
        var out = []
        var all = player.engineTracks
        for (var i = 0; i < all.length; ++i)
            if (all[i].type === type)
                out.push(all[i])
        return out
    }
    function trackName(t) {
        if (t.title && t.title !== "")
            return t.language !== "" && t.title.indexOf(t.language) < 0
                   ? t.title + " (" + t.language + ")" : t.title
        if (t.language !== "")
            return t.language
        return qsTr("Track %1").arg(t.order + 1)
    }
    function trackDetail(t) {
        var parts = [t.codec.toUpperCase()]
        if (t.type === "video" && t.width > 0)
            parts.push(t.width + "×" + t.height)
        if (t.type === "audio" && t.channels > 0)
            parts.push(t.channels === 1 ? qsTr("mono")
                     : t.channels === 2 ? qsTr("stereo")
                     : t.channels === 6 ? "5.1" : t.channels === 8 ? "7.1"
                     : qsTr("%n channels", "", t.channels))
        if (t.forced)
            parts.push(qsTr("forced"))
        else if (t.isDefault)
            parts.push(qsTr("default"))
        return parts.join("  •  ")
    }
    function fileName(path) {
        return path.substring(path.lastIndexOf('/') + 1)
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width

            PageHeader { title: qsTr("Tracks") }

            // ── Video ────────────────────────────────────────────────────────
            SectionHeader {
                text: qsTr("Video")
                visible: videoRepeater.count > 0
            }
            Repeater {
                id: videoRepeater
                model: tracksPage.tracksOf("video")
                TrackItem {
                    text: tracksPage.trackName(modelData)
                    detail: tracksPage.trackDetail(modelData)
                    checked: player.videoTrack === modelData.index
                             || (player.videoTrack === -1 && modelData.index === player.defaultVideoIndex)
                    onClicked: player.chooseVideoTrack(modelData.index)
                }
            }

            // ── Audio ────────────────────────────────────────────────────────
            SectionHeader {
                text: qsTr("Audio")
                visible: audioRepeater.count > 0
            }
            Repeater {
                id: audioRepeater
                model: tracksPage.tracksOf("audio")
                TrackItem {
                    text: tracksPage.trackName(modelData)
                    detail: tracksPage.trackDetail(modelData)
                    checked: player.audioTrack === modelData.index
                             || (player.audioTrack === -1 && modelData.index === player.defaultAudioIndex)
                    onClicked: player.chooseAudioTrack(modelData.index)
                }
            }
            TrackItem {
                visible: audioRepeater.count > 0
                text: qsTr("No audio")
                checked: player.audioTrack === -2
                onClicked: player.chooseAudioTrack(-2)
            }

            // ── Subtitles ────────────────────────────────────────────────────
            SectionHeader { text: qsTr("Subtitles") }
            TrackItem {
                text: qsTr("Off")
                checked: player.subtitleTrack === -1 && player.subtitleFile === ""
                onClicked: player.chooseSubtitleTrack(-1)
            }
            Repeater {
                model: tracksPage.tracksOf("subtitle")
                TrackItem {
                    text: tracksPage.trackName(modelData)
                    detail: tracksPage.trackDetail(modelData)
                    checked: player.subtitleFile === "" && player.subtitleTrack === modelData.index
                    onClicked: player.chooseSubtitleTrack(modelData.index)
                }
            }
            TrackItem {
                visible: player.subtitleFile !== ""
                text: tracksPage.fileName(player.subtitleFile)
                detail: player.subtitlesFailed ? qsTr("No subtitles found in this file")
                                               : qsTr("External file")
                checked: true
            }
            BackgroundItem {
                width: parent.width
                onClicked: pageStack.push(subtitlePicker)
                Row {
                    x: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.paddingMedium
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        source: "image://theme/icon-m-add"
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Load subtitle file…")
                        color: parent.parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                    }
                }
            }
            Item { width: 1; height: Theme.paddingMedium }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                text: qsTr("SubRip (.srt), WebVTT (.vtt) and SubStation (.ass, .ssa) files. "
                           + "A file next to the video with the same name is loaded automatically.")
            }
        }
        VerticalScrollDecorator {}
    }

    Component {
        id: subtitlePicker
        FilePickerPage {
            title: qsTr("Select a subtitle file")
            nameFilters: ["*.srt", "*.vtt", "*.ass", "*.ssa", "*.SRT", "*.VTT", "*.ASS", "*.SSA"]
            onSelectedContentPropertiesChanged: {
                player.chooseSubtitleFile(selectedContentProperties.filePath)
            }
        }
    }
}
