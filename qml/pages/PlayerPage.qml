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

    // Optional queue metadata from the Tracker-backed music pages
    // (path → { title, artist, album }). Preferred over the ffmpeg TagReader,
    // which cannot interpret every file the system indexer can.
    property var queueMeta: ({})
    function metaFor() {
        return (queueMeta && queueMeta[source]) ? queueMeta[source] : null
    }

    // Optional cover image for the whole queue (a playlist's chosen cover). Takes
    // priority over a track's embedded art on the app cover. "" = none.
    property string playlistCover: ""

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

    // Manual decode override (additive — the default is the engine's auto pick).
    // "" = automatic, "hw" = force droidmedia HW, "sw" = force libVLC software.
    // Deliberately NOT persistent: it lives on this page instance, so it resets to
    // automatic when the video is closed (a fresh PlayerPage), but is kept across
    // loops and album tracks. The engine's auto choice is remembered here so
    // switching back to "Automatic" can restore it without re-probing.
    property string decodeOverride: ""
    property string recommendedBackendStr: "qt"   // "qt" | "vlc" | "droid" (auto pick)

    // Set once we've auto-fallen-back from the HW (droid) path to software (libVLC)
    // for the current source, so a second droid failure can't loop. Reset by
    // routeAndPlay() on every fresh start/probe/track. The fallback is suppressed
    // when the user explicitly forced "Hardware" in the Decoding selector.
    property bool autoFellBack: false

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

    // ── App cover (audio/video): title from metadata, fallback to file name ──
    // Tracker metadata (queueMeta) wins, then the file's own tags (TagReader).
    function coverDisplayTitle() {
        var m = metaFor()
        if (m && m.title && m.title !== "")
            return m.title
        if (coverTag.title && coverTag.title !== "")
            return coverTag.title
        var s = page.source
        var n = s.substring(s.lastIndexOf('/') + 1)
        var dot = n.lastIndexOf('.')
        return dot > 0 ? n.substring(0, dot) : n
    }
    // Subtitle: album/playlist name when known, else just the media kind.
    function coverDisplaySubtitle() {
        var m = metaFor()
        if (m && m.album && m.album !== "")
            return m.album
        if (coverTag.album && coverTag.album !== "")
            return coverTag.album
        return engine.hasVideo ? qsTr("Video") : qsTr("Audio")
    }
    function pushCover() {
        coverState.mode = "media"
        coverState.title = coverDisplayTitle()
        coverState.subtitle = coverDisplaySubtitle()
        coverState.coverArt = page.playlistCover !== ""
            ? page.playlistCover
            : ((engine.valid && engine.hasCover) ? engine.coverSource : "")
        coverState.playing = page.isPlaying
    }

    // Metadata reader feeding the cover title/subtitle.
    TagReader { id: coverTag; filePath: page.source }
    Connections {
        target: coverTag
        onTagsChanged: if (coverState.mode === "media") {
            coverState.title = page.coverDisplayTitle()
            coverState.subtitle = page.coverDisplaySubtitle()
        }
    }
    // Cover CoverAction taps routed back to the live player.
    Connections {
        target: coverState
        onPlayPauseRequested: page.togglePlay()
        onNextRequested: page.albumMode ? page.playNext() : page.step(10000)
    }
    onIsPlayingChanged: if (coverState.mode === "media") coverState.playing = page.isPlaying
    onSourceChanged: pushCover()

    // Resolve the backend to actually use: the manual override if set, else the
    // engine's auto pick. Forcing HW falls back to the QtMultimedia baseline when
    // the direct droid path is disabled.
    function targetBackend() {
        if (page.decodeOverride === "hw")
            return page.droidEnabled ? "droid" : "qt"
        if (page.decodeOverride === "sw")
            return "vlc"
        return page.recommendedBackendStr
    }

    // Friendly name of the backend ACTUALLY playing (page.backend) — not the engine's
    // original pick — so the header reflects an auto fallback (droid→vlc) or a manual
    // Decoding override. Names match MediaEngine::recommendedBackendName().
    function activeBackendName() {
        return page.backend === "droid" ? "droidmedia (HW)"
             : page.backend === "vlc" ? "libVLC"
             : "QtMultimedia"
    }

    // Stop whatever is playing and (re)start the current source on the resolved
    // backend. Used by the engine probe and by the decode-mode selector.
    // A droidmedia failure carries an ErrorKind; turn it into an accurate message
    // instead of always blaming the hardware decoder (the old behaviour hid network
    // and demux faults behind "Hardware decode error").
    function decodeErrorText(kind) {
        switch (kind) {
        case DroidCodecBackend.ErrNetwork:
            return qsTr("Network error: can't reach the stream")
        case DroidCodecBackend.ErrDemux:
            return qsTr("Can't read this media (unsupported or corrupt container)")
        case DroidCodecBackend.ErrUnsupported:
            return qsTr("Unsupported format")
        case DroidCodecBackend.ErrDecode:
            return qsTr("Hardware decode error")
        default:
            return qsTr("Playback error")
        }
    }

    // Auto HW→SW fallback: when the droid HW decoder can't handle a stream (a profile
    // it rejects, or a container quirk), retry once on libVLC before showing an error.
    function fallbackToSoftware() {
        page.autoFellBack = true
        player.stop(); vlc.stop(); droid.stop()
        errorLabel.text = ""
        page.backend = "vlc"
        page.videoRotation = 0
        vlc.play(page.source)
    }

    function routeAndPlay() {
        var b = targetBackend()
        player.stop(); vlc.stop(); droid.stop()
        errorLabel.text = ""
        page.autoFellBack = false   // fresh start: allow a fallback again
        page.backend = b
        // qt/vlc honour the container's display rotation; the raw HW droid path
        // doesn't, so apply it ourselves there. Others start upright.
        page.videoRotation = (b === "droid") ? engine.rotation : 0
        if (b === "vlc")
            vlc.play(page.source)
        else if (b === "droid")
            droid.play(page.source)
        else {
            player.source = page.source
            player.play()
        }
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
        if (status === PageStatus.Active && source !== "") {
            engine.probe(source) // playback starts in engine.onProbed
            pushCover()
        }
    }

    // C++ media-engine facade: ffmpeg demux/probe + capability-driven backend pick.
    MediaEngine {
        id: engine
        onProbed: {
            // Remember the engine's auto pick, then route via routeAndPlay() so a
            // manual decode override (if any) is honoured. (e.g. phone-camera clips
            // tagged -90 get their rotation applied on the raw HW droid path there.)
            if (recommendedBackend === MediaEngine.Libvlc)
                page.recommendedBackendStr = "vlc"
            else if (recommendedBackend === MediaEngine.Droidmedia && page.droidEnabled)
                page.recommendedBackendStr = "droid"
            else
                page.recommendedBackendStr = "qt"
            page.routeAndPlay()
            page.pushCover()   // refresh cover subtitle now hasVideo is known
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
    // Two-finger pinch zooms the video, a one-finger drag then pans it and a
    // double tap restores 1×; a single tap toggles the controls. Wraps all three
    // render surfaces so zoom works whichever backend is active.
    PinchZoom {
        id: zoom
        anchors.fill: parent
        onClicked: controls.visible = !controls.visible

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
                    // Recoverable HW fault (rejected profile, TS quirk) → silently
                    // retry on libVLC software, unless the user forced HW or we've
                    // already fallen back once for this source.
                    var k = droid.errorKind
                    if (!page.autoFellBack && page.decodeOverride !== "hw"
                            && (k === DroidCodecBackend.ErrDecode
                                || k === DroidCodecBackend.ErrUnsupported)) {
                        page.fallbackToSoftware()
                        return
                    }
                    controls.visible = true
                    errorLabel.text = page.decodeErrorText(k)
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
    }   // PinchZoom

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
                         ? qsTr("Backend: %1").arg(page.activeBackendName())
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

            // Manual decode-mode selector (additive; default = Automatic). Picking a
            // mode reloads the current source on that backend. Not persistent: resets
            // to Automatic when the video is closed, kept across loops/tracks.
            ComboBox {
                width: parent.width
                visible: engine.valid
                label: qsTr("Decoding")
                currentIndex: 0   // 0 = Automatic, 1 = Hardware, 2 = Software
                menu: ContextMenu {
                    MenuItem { text: qsTr("Automatic") }
                    MenuItem { text: qsTr("Hardware (droidmedia)") }
                    MenuItem { text: qsTr("Software (libVLC)") }
                }
                onCurrentIndexChanged: {
                    var ov = currentIndex === 1 ? "hw"
                           : (currentIndex === 2 ? "sw" : "")
                    if (ov === page.decodeOverride)
                        return
                    page.decodeOverride = ov
                    if (engine.valid)
                        page.routeAndPlay()
                }
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
        coverState.clear()
    }
}
