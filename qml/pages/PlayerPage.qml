import QtQuick 2.0
import Sailfish.Silica 1.0
import QtMultimedia 5.6

Page {
    id: page
    allowedOrientations: Orientation.All
    backNavigation: controls.visible

    // Media source (local file path or network URL) passed in from MainPage.
    property string source: ""

    // Auto-hide the controls during playback; tap toggles them.
    property bool controlsVisible: true

    onStatusChanged: {
        if (status === PageStatus.Active && source !== "") {
            player.source = source
            player.play()
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    MediaPlayer {
        id: player
        autoPlay: false
        // On SFOS QtMultimedia is backed by GStreamer/gst-droid → hardware
        // decode for common codecs. Later versions add a libvlc backend and a
        // direct droidmedia HW path behind a C++ facade.
        onError: {
            controls.visible = true
            errorLabel.text = errorString
        }
    }

    VideoOutput {
        id: videoOutput
        anchors.fill: parent
        source: player
        fillMode: VideoOutput.PreserveAspectFit
    }

    BusyIndicator {
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
        running: player.status === MediaPlayer.Loading
                 || player.status === MediaPlayer.Buffering
        visible: running
    }

    Label {
        id: errorLabel
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.horizontalPageMargin
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        color: Theme.errorColor
        visible: text.length > 0
    }

    MouseArea {
        anchors.fill: parent
        onClicked: controls.visible = !controls.visible
    }

    // Playback controls overlay.
    Item {
        id: controls
        anchors.fill: parent
        visible: page.controlsVisible

        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: controlsColumn.height + 2 * Theme.paddingLarge
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.7) }
            }
        }

        Column {
            id: controlsColumn
            anchors {
                left: parent.left; right: parent.right
                bottom: parent.bottom; bottomMargin: Theme.paddingLarge
            }

            Slider {
                id: seekSlider
                width: parent.width
                minimumValue: 0
                maximumValue: player.duration > 0 ? player.duration : 1
                value: player.position
                enabled: player.seekable
                valueText: page.formatTime(value)
                onReleased: player.seek(value)
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingLarge

                IconButton {
                    icon.source: "image://theme/icon-m-previous"
                    onClicked: player.seek(Math.max(0, player.position - 10000))
                }
                IconButton {
                    icon.source: player.playbackState === MediaPlayer.PlayingState
                                 ? "image://theme/icon-l-pause"
                                 : "image://theme/icon-l-play"
                    onClicked: player.playbackState === MediaPlayer.PlayingState
                               ? player.pause() : player.play()
                }
                IconButton {
                    icon.source: "image://theme/icon-m-next"
                    onClicked: player.seek(Math.min(player.duration, player.position + 10000))
                }
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                text: page.formatTime(player.position) + " / " + page.formatTime(player.duration)
            }
        }
    }

    function formatTime(ms) {
        if (isNaN(ms) || ms < 0)
            ms = 0
        var total = Math.floor(ms / 1000)
        var s = total % 60
        var m = Math.floor(total / 60) % 60
        var h = Math.floor(total / 3600)
        function pad(n) { return n < 10 ? "0" + n : "" + n }
        return (h > 0 ? h + ":" + pad(m) : m) + ":" + pad(s)
    }

    Component.onDestruction: player.stop()
}
