import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.WebView 1.0
import Sailfish.WebEngine 1.0

// In-app YouTube playback: the official m.youtube.com watch page in the
// Sailfish WebView (same Gecko engine as the system browser, so same legal,
// unmodified player — ads and all — with zero extraction code to maintain).
//
// Two things make this work where it previously failed:
//  1. Consent: a fresh WebView profile lacks Google's consent cookie and the
//     watch page dead-ends on the consent gate. We first load the /embed/ page
//     (a real youtube.com-origin document that loads fine), set SOCS/CONSENT
//     via document.cookie, then navigate to the watch page. The cookies
//     persist in the profile, so the detour costs ~1s once per install.
//  2. The old "WebView crashes on video pages" was OUR bug, not Gecko's: the
//     app exports its statically-linked ffmpeg symbols (-rdynamic, needed by
//     the booster) and Gecko's system libavcodec.so bound to them → ABI mix →
//     SIGSEGV. Fixed at link time with --exclude-libs (harbour-rootheater.pro).
//
// The /embed/ player itself stays unusable on this engine (YouTube requires a
// PoToken the old Gecko can't produce) — only the full watch page plays. The
// embed is loaded ONLY to seed the consent cookie, and is kept hidden behind a
// BusyIndicator so its "error 153" page never flashes on screen.
Page {
    id: page

    property string videoId: ""
    property string title: ""

    // false while the consent-bootstrap embed loads → WebView hidden, spinner
    // shown; flips true once the real watch page is up (so the user only ever
    // sees the working player, never the embed's error-153 page).
    property bool ready: false

    // Fullscreen orientation: 0 = not fullscreen (follow device), 1 = landscape
    // video (force landscape), 2 = portrait video (force portrait). Driven by the
    // page's own fullscreenchange listener (see watchInitJs) which reports the
    // video's aspect ratio. A landscape clip rotates to fill the screen; a
    // portrait clip (stories / vertical videos) stays upright but still fills it.
    property int fsMode: 0
    allowedOrientations: fsMode === 1 ? Orientation.Landscape
                       : fsMode === 2 ? Orientation.Portrait
                                      : Orientation.All

    readonly property string watchUrl: "https://m.youtube.com/watch?v=" + videoId
    readonly property string embedUrl: "https://www.youtube.com/embed/" + videoId
    // Per-site UA the system browser sends to youtube.com (its ua-update.json);
    // without the "like Chrome" token YouTube serves a degraded player.
    readonly property string youtubeUa:
        "Mozilla/5.0 (Sailfish 5.0; Mobile; rv:91.0) Gecko/91.0 Firefox/91.0 " +
        "like Chrome/135.0.0.0 Safari/537.36"

    // Injected once on the watch page. The desired UX — open a video straight
    // into a paused, correctly-oriented fullscreen with a centered play button,
    // tap to start — is delivered by four cooperating pieces (all the non-obvious
    // constraints were found the hard way on this Gecko/WebView; see below):
    //  • fullscreen-starter: enters fullscreen via requestFullscreen (a DIRECT API
    //    call — works without a user gesture; a synthetic .click() on YouTube's
    //    fullscreen button is ignored as untrusted). Targets the MOBILE player
    //    container #player-container-id (the element YouTube itself fullscreens →
    //    keeps its controls + proper layout), NOT #movie_player (inner player:
    //    hides controls, renders portrait videos tiny).
    //  • tap-to-play: the mobile watch page opens PAUSED (YT doesn't autoplay) and
    //    #player-control-container swallows taps until playback begins, so the
    //    FIRST real tap starts it via YouTube's player API playVideo() (a valid
    //    user gesture; raw video.play() fails — the media isn't attached until
    //    YT's own play, and autoplay-blocked play is re-paused once activation
    //    expires, hence media.autoplay.default=0 in the prefs below).
    //  • orientation reporter (portrait-safe): reports fullscreen state + the
    //    video orientation to QML via document.title ("RTFS:1:land"/":port"/
    //    "RTFS:0"), only claiming landscape once the video is proven wider than
    //    tall, so vertical videos/shorts are never rotated sideways.
    //  • orientation poller: the real dimensions usually arrive AFTER we're already
    //    fullscreen, so a 600ms poll re-reports until then and flips the page to
    //    landscape the moment they're known.
    readonly property string watchInitJs:
        "(function(){if(window.__rtInit)return;window.__rtInit=1;" +
        // orientation reporter (portrait-safe: landscape only when proven wider)
        "function report(){var fe=document.fullscreenElement||document.webkitFullscreenElement||document.mozFullScreenElement;" +
        "if(!fe){document.title='RTFS:0';return;}" +
        "var v=document.querySelector('video');var land=false;" +
        "if(v&&v.videoWidth&&v.videoHeight)land=(v.videoWidth>v.videoHeight);" +
        "document.title='RTFS:1:'+(land?'land':'port');}" +
        "['fullscreenchange','webkitfullscreenchange','mozfullscreenchange']" +
        ".forEach(function(e){document.addEventListener(e,report,true);});" +
        // The mobile watch page opens PAUSED (YouTube doesn't autoplay). We start
        // playback on the FIRST real tap via YouTube's player API playVideo() — a
        // valid user gesture, and with autoplay allowed it keeps playing (raw
        // video.play() fails: the media isn't attached until YT's own play). This
        // is the intended UX: fullscreen + paused + centered play, tap to start.
        // Turn captions OFF via the player API. YouTube auto-enables them because
        // playback starts muted (autoplay policy); it re-enables on the muted→audio
        // switch, so we fire this a few times right after the first play to catch
        // that — only in the opening window, so we never fight a later manual toggle.
        "function ccOff(){var p=document.getElementById('movie_player');if(!p)return;" +
        "try{p.setOption('captions','track',{});}catch(e){}" +
        "try{p.unloadModule('captions');}catch(e){}try{p.unloadModule('cc');}catch(e){}}" +
        "var started=false;['pointerdown','touchstart','mousedown'].forEach(function(ev){" +
        "document.addEventListener(ev,function(e){if(started)return;started=true;" +
        "var p=document.getElementById('movie_player');" +
        "if(p&&typeof p.playVideo==='function'){try{p.playVideo();}catch(x){}" +
        "[300,1000,2500,4500].forEach(function(d){setTimeout(ccOff,d);});return;}" +
        "var v=document.querySelector('video');if(v){try{v.play();}catch(x){}}" +
        "},true);});" +
        // re-report when real dimensions arrive (metadata / resize / playback)
        "function hookV(v){if(!v||v.__rtV)return;v.__rtV=1;" +
        "['loadedmetadata','resize','playing'].forEach(function(e){v.addEventListener(e,report);});}" +
        // Enter fullscreen via requestFullscreen (a direct API call — works
        // programmatically; a synthetic .click() on YouTube's button is ignored as
        // untrusted). Target YouTube's MOBILE player container #player-container-id
        // (the element YT itself fullscreens: keeps controls + proper layout), NOT
        // #movie_player (inner player: hides controls, renders portrait tiny).
        "function goFs(){var p=document.querySelector('#player-container-id')||document.querySelector('.player-container')||document.querySelector('#movie_player')||document.querySelector('video');" +
        "if(!p)return;var rq=p.requestFullscreen||p.webkitRequestFullscreen||p.mozRequestFullScreen;" +
        "if(rq){try{rq.call(p);}catch(e){}}}" +
        "var n=0;var k=setInterval(function(){n++;" +
        "var fe=document.fullscreenElement||document.webkitFullscreenElement||document.mozFullScreenElement;" +
        "if(fe){clearInterval(k);return;}" +          // fullscreen in → done
        "var v=document.querySelector('video');hookV(v);" +
        "goFs();" +
        "if(n>25){clearInterval(k);}" +
        "},400);" +
        // Poll orientation while fullscreen: the video's real size usually arrives
        // AFTER we're already fullscreen (unknown at FS time → stuck on the
        // portrait-safe default). Re-setting the same title does NOT re-emit the
        // change, so this is cheap; it flips the page to landscape the moment the
        // real dimensions are known (and handles ad→content aspect switches).
        "setInterval(function(){var fe=document.fullscreenElement||document.webkitFullscreenElement||document.mozFullScreenElement;if(fe)report();},600);" +
        "})()"

    Component.onCompleted: {
        // Browser-parity prefs the bare WebView misses (sailfish-browser data/prefs.js).
        WebEngineSettings.setPreference("apz.allow_zooming", true)
        WebEngineSettings.setPreference("dom.meta-viewport.enabled", true)
        // Allow autoplay so YouTube actually LOADS the media (with it blocked the
        // player stays an unloaded shell that swallows taps). Playback control is
        // layered on top once we confirm a loaded player behaves in fullscreen.
        WebEngineSettings.setPreference("media.autoplay.default", 0)
        WebEngineSettings.setPreference("media.autoplay.blocking_policy", 0)
        // Let the YouTube player's fullscreen button actually go fullscreen.
        WebEngineSettings.setPreference("full-screen-api.enabled", true)
        WebEngineSettings.setPreference("full-screen-api.allow-trusted-requests-only", false)
    }

    WebView {
        id: web
        anchors.fill: parent
        httpUserAgent: page.youtubeUa
        url: page.embedUrl                 // consent bootstrap (hidden)
        // Keep it rendering (so it loads) but invisible until the watch page is up
        // (so the embed's error-153 page is never seen). The watch page itself is
        // fine to show — it auto-goes fullscreen, and the plain page when not.
        opacity: page.ready ? 1.0 : 0.0
        Behavior on opacity { FadeAnimation {} }

        property bool consentDone: false
        onLoadingChanged: {
            if (loading) return
            if (!consentDone) {
                // Embed finished: seed consent cookies, then go to the watch page.
                consentDone = true
                runJavaScript(
                    "try{var e='; domain=.youtube.com; path=/; max-age=31536000';" +
                    "document.cookie='SOCS=CAI'+e;" +
                    "document.cookie='CONSENT=YES+1'+e;}catch(x){}")
                gotoWatch.start()
            } else if (url.toString().indexOf("/watch") >= 0) {
                // Real player is up: reveal it and run the fullscreen+report hook.
                page.ready = true
                runJavaScript(page.watchInitJs)
            }
        }
        // Fullscreen state/orientation pushed from the page via document.title.
        onTitleChanged: {
            var t = title
            if (t.indexOf("RTFS:") !== 0)
                return
            if (t === "RTFS:0")
                page.fsMode = 0
            else if (t.indexOf(":land") > 0)
                page.fsMode = 1
            else if (t.indexOf(":port") > 0)
                page.fsMode = 2
        }
        Timer { id: gotoWatch; interval: 400; onTriggered: web.url = page.watchUrl }

        PullDownMenu {
            MenuItem {
                text: qsTr("Open in browser")
                onClicked: Qt.openUrlExternally(page.watchUrl)
            }
            MenuItem {
                text: qsTr("Reload")
                onClicked: {
                    page.ready = false
                    page.fsMode = 0
                    web.consentDone = false
                    web.url = page.embedUrl
                }
            }
        }
    }

    // Loading overlay: covers the hidden embed (and its error-153 page) until the
    // watch page is up.
    Rectangle {
        anchors.fill: parent
        visible: !page.ready
        color: Theme.overlayBackgroundColor

        Column {
            anchors.centerIn: parent
            spacing: Theme.paddingLarge
            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                size: BusyIndicatorSize.Large
                running: !page.ready
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Loading…")
                color: Theme.highlightColor
            }
        }
    }
}
