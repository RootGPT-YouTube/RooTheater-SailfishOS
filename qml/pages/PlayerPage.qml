import QtQuick 2.0
import Sailfish.Silica 1.0
import QtMultimedia 5.6
import RooTheater.Media 1.0

Page {
    id: page
    allowedOrientations: Orientation.All
    backNavigation: controls.visible

    // Media source (local file path or network URL) passed in from MainPage.
    property string source: ""

    // Album playback: an ordered queue of file paths plus the playing index.
    // When the queue holds more than one track ("album mode") the prev/next
    // buttons skip tracks and playback auto-advances at end-of-track; a single
    // source keeps the prev/next buttons as ±10s seek.
    property var queue: []
    property int trackIndex: 0
    readonly property bool albumMode: queue.length > 1

    // Auto-hide the controls during playback; tap toggles them.
    property bool controlsVisible: true

    // Backend routing: the engine facade probes the source, then plays it on the
    // backend it picked — droidmedia (direct HW, v0.3), libVLC (exotic coverage)
    // or the QtMultimedia baseline. Decided in engine.onProbed.
    property string backend: "qt"   // "qt" | "vlc" | "droid"

    // v0.3.3: route Droidmedia-selected codecs (per the capability query) through
    // the direct zero-copy HW decode path (DroidCodecBackend + DroidVideoSink).
    // Set false to fall back to the QtMultimedia baseline for those files.
    property bool droidEnabled: true

    // ── Unified control surface over whichever backend is active ─────────────
    readonly property bool isPlaying: backend === "vlc" ? vlc.playing
        : backend === "droid" ? droid.playing
        : (player.playbackState === MediaPlayer.PlayingState)
    readonly property int positionMs: backend === "vlc" ? vlc.position
        : backend === "droid" ? droid.position : player.position
    readonly property int durationMs: backend === "vlc" ? vlc.duration
        : backend === "droid" ? droid.duration : player.duration
    readonly property bool canSeek: backend === "vlc" ? vlc.seekable
        : backend === "droid" ? droid.seekable : player.seekable
    // Playback finished (reached the end) — Play then restarts from the start.
    readonly property bool isEnded: backend === "vlc" ? vlc.state === VlcBackend.Ended
        : backend === "droid" ? droid.state === DroidCodecBackend.Ended
        : player.status === MediaPlayer.EndOfMedia
    // Loop the current media: when it ends, start it again automatically.
    property bool loopEnabled: false
    // Display rotation in degrees, cycled 0 → 90 → 180 → 270 by the rotate button.
    property int videoRotation: 0
    // Rotated 90/270 swaps the video item's width/height so it still fits the area.
    readonly property bool videoTurned: videoRotation % 180 !== 0

    function restart() {
        if (backend === "vlc")
            vlc.play(page.source)
        else if (backend === "droid")
            droid.play(page.source)
        else {
            player.seek(0)
            player.play()
        }
    }
    function togglePlay() {
        if (isEnded) {          // finished → Play restarts from the beginning
            restart()
            return
        }
        if (backend === "vlc")
            vlc.togglePause()
        else if (backend === "droid")
            droid.togglePause()
        else
            player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
    }
    function seekTo(ms) {
        if (backend === "vlc")
            vlc.seek(ms)
        else if (backend === "droid")
            droid.seek(ms)
        else
            player.seek(ms)
    }
    function step(deltaMs) {
        seekTo(Math.max(0, Math.min(durationMs, positionMs + deltaMs)))
    }

    // Album mode: switch to track `i`, tear down the current backend and re-probe
    // so engine.onProbed routes + starts it like any fresh source.
    function loadTrack(i) {
        if (i < 0 || i >= queue.length)
            return
        trackIndex = i
        player.stop(); vlc.stop(); droid.stop()
        errorLabel.text = ""
        source = queue[trackIndex]
        engine.probe(source)
    }
    function playNext() { if (trackIndex < queue.length - 1) loadTrack(trackIndex + 1) }
    function playPrev() { if (trackIndex > 0) loadTrack(trackIndex - 1) }

    // Auto-advance to the next track when one ends (unless looping a single track).
    onIsEndedChanged: {
        if (isEnded && albumMode && !loopEnabled)
            playNext()
    }

    Component.onCompleted: {
        if (queue.length > 0)
            source = queue[trackIndex]
    }

    onStatusChanged: {
        if (status === PageStatus.Active && source !== "")
            engine.probe(source) // playback starts in engine.onProbed
    }

    // C++ media-engine facade: ffmpeg demux/probe + capability-driven backend pick.
    MediaEngine {
        id: engine
        onProbed: {
            if (recommendedBackend === MediaEngine.Libvlc)
                page.backend = "vlc"
            else if (recommendedBackend === MediaEngine.Droidmedia && page.droidEnabled)
                page.backend = "droid"
            else
                page.backend = "qt"
            // qt/vlc already honour the container's display rotation; the raw HW
            // droid path doesn't, so apply it ourselves there (e.g. phone-camera
            // clips tagged -90). Other backends start upright.
            page.videoRotation = (page.backend === "droid") ? engine.rotation : 0

            if (page.backend === "vlc") {
                vlc.play(page.source)
            } else if (page.backend === "droid") {
                droid.play(page.source)
            } else {
                player.source = page.source
                player.play()
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    // ── Backend 1: QtMultimedia baseline (gst-droid) ─────────────────────────
    MediaPlayer {
        id: player
        autoPlay: false
        loops: page.loopEnabled ? MediaPlayer.Infinite : 1
        onError: {
            controls.visible = true
            errorLabel.text = errorString
        }
    }
    VideoOutput {
        id: videoOutput
        anchors.centerIn: parent
        width: page.videoTurned ? parent.height : parent.width
        height: page.videoTurned ? parent.width : parent.height
        rotation: page.videoRotation
        source: player
        fillMode: VideoOutput.PreserveAspectFit
        visible: page.backend === "qt"
    }

    // ── Backends 2 & 3: libVLC (Layer 3) and droidmedia (Layer 1) both render
    // their CPU-decoded frames into the shared VideoSurface. ─────────────────
    VlcBackend {
        id: vlc
        videoOutput: frameSurface
        onStateChanged: {
            if (state === VlcBackend.Error) {
                controls.visible = true
                errorLabel.text = qsTr("libVLC playback error")
            } else if (state === VlcBackend.Ended && page.loopEnabled) {
                page.restart()
            }
        }
    }
    DroidCodecBackend {
        id: droid
        videoSink: droidSink
        loop: page.loopEnabled    // looped in-pipeline (no teardown) by the backend
        onStateChanged: {
            if (state === DroidCodecBackend.Error) {
                controls.visible = true
                errorLabel.text = qsTr("Hardware decode error")
            }
        }
    }
    // libVLC (CPU frames) renders here.
    VideoSurface {
        id: frameSurface
        anchors.centerIn: parent
        width: page.videoTurned ? parent.height : parent.width
        height: page.videoTurned ? parent.width : parent.height
        rotation: page.videoRotation
        visible: page.backend === "vlc"
    }
    // droidmedia zero-copy (EGLImage → GL_TEXTURE_EXTERNAL_OES) renders here.
    DroidVideoSink {
        id: droidSink
        anchors.centerIn: parent
        width: page.videoTurned ? parent.height : parent.width
        height: page.videoTurned ? parent.width : parent.height
        rotation: page.videoRotation
        visible: page.backend === "droid"
    }

    // Audio-only media: show the embedded cover art, or a ♪ placeholder when the
    // file has none. (The cover is served in-memory via the rtcover provider.)
    Item {
        anchors.fill: parent
        visible: engine.valid && !engine.hasVideo
        Image {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) * 0.72
            height: width
            fillMode: Image.PreserveAspectFit
            source: engine.coverSource
            visible: engine.hasCover
            cache: false
            asynchronous: true
        }
        Label {
            anchors.centerIn: parent
            visible: !engine.hasCover
            text: "♪"
            color: Theme.secondaryColor
            font.pixelSize: Math.min(parent.width, parent.height) * 0.4
        }
    }

    BusyIndicator {
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
        running: engine.probing
                 || (page.backend === "qt" && (player.status === MediaPlayer.Loading
                                      || player.status === MediaPlayer.Buffering))
                 || (page.backend === "vlc" && (vlc.state === VlcBackend.Opening
                                     || vlc.state === VlcBackend.Buffering))
                 || (page.backend === "droid" && droid.state === DroidCodecBackend.Opening)
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

        // Engine probe info: what ffmpeg detected and which backend the facade
        // routed to. Surfaces the capability-driven selection to the user.
        Column {
            id: infoColumn
            anchors {
                left: parent.left; right: parent.right
                top: parent.top; topMargin: Theme.paddingLarge
                leftMargin: Theme.horizontalPageMargin
                rightMargin: Theme.horizontalPageMargin
            }
            spacing: Theme.paddingSmall
            visible: engine.probing || engine.valid || engine.errorString.length > 0

            Label {
                width: parent.width
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.highlightColor
                text: engine.probing
                      ? qsTr("Analyzing…")
                      : (engine.valid
                         ? qsTr("Backend: %1").arg(engine.recommendedBackendName)
                         : qsTr("Probe failed: %1").arg(engine.errorString))
            }
            Label {
                width: parent.width
                visible: engine.valid
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                text: {
                    if (!engine.valid)
                        return ""
                    var parts = []
                    if (engine.hasVideo)
                        parts.push(engine.videoCodec
                                   + " " + engine.width + "×" + engine.height)
                    if (engine.hasAudio)
                        parts.push(engine.audioCodec)
                    if (engine.container.length > 0)
                        parts.push(engine.container)
                    return parts.join("  •  ")
                }
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
                maximumValue: page.durationMs > 0 ? page.durationMs : 1
                value: page.positionMs
                enabled: page.canSeek
                valueText: page.formatTime(value)
                onReleased: page.seekTo(value)

                // Dragging assigns `value` imperatively, which breaks the
                // `value: positionMs` binding; re-track the playhead whenever the
                // user is NOT dragging (otherwise the handle freezes where dropped).
                Connections {
                    target: page
                    onPositionMsChanged: if (!seekSlider.down) seekSlider.value = page.positionMs
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingLarge

                IconButton {
                    icon.source: "image://theme/icon-m-previous"
                    enabled: !page.albumMode || page.trackIndex > 0
                    onClicked: page.albumMode ? page.playPrev() : page.step(-10000)
                }
                IconButton {
                    icon.source: page.isPlaying
                                 ? "image://theme/icon-l-pause"
                                 : "image://theme/icon-l-play"
                    onClicked: page.togglePlay()
                }
                IconButton {
                    icon.source: "image://theme/icon-m-next"
                    enabled: !page.albumMode || page.trackIndex < page.queue.length - 1
                    onClicked: page.albumMode ? page.playNext() : page.step(10000)
                }
                IconButton {
                    icon.source: "image://theme/icon-m-repeat"
                    highlighted: page.loopEnabled
                    onClicked: page.loopEnabled = !page.loopEnabled
                }
                IconButton {
                    icon.source: "image://theme/icon-m-rotate"
                    highlighted: page.videoRotation !== 0
                    onClicked: page.videoRotation = (page.videoRotation + 90) % 360
                }
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: page.albumMode
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                text: qsTr("Track %1 / %2").arg(page.trackIndex + 1).arg(page.queue.length)
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                text: page.formatTime(page.positionMs) + " / " + page.formatTime(page.durationMs)
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

    Component.onDestruction: {
        player.stop()
        vlc.stop()
        droid.stop()
    }
}
