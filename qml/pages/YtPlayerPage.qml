import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.WebView 1.0
import Sailfish.WebEngine 1.0
import Nemo.KeepAlive 1.2

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
    //  • quality cap: pins the best level up to 720p instead of letting YouTube's
    //    ABR drift with the bandwidth (see the block below for why it retries).
    // Background playback (cover / blank screen) is not handled here but by the
    // `active` override on the WebView below.
    readonly property string watchInitJs:
        "(function(){if(window.__rtInit)return;window.__rtInit=1;" +
        // Diagnostic payload, piggybacked on the document.title channel below.
        // (runJavaScript's return value never reaches its callback on this
        // WebView, so the title is the only way back to QML.) It is what makes
        // a frozen picture legible in the journal: `total` counts decoded
        // frames, `drop` the ones thrown away before they could be painted.
        "function diag(){try{var v=document.querySelector('video');if(!v)return 'novideo';" +
        "var q={};try{if(v.getVideoPlaybackQuality)q=v.getVideoPlaybackQuality()||{};}catch(e){}" +
        "return ['t='+(v.currentTime||0).toFixed(2),'pause='+(v.paused?1:0)," +
        "'rs='+v.readyState,'size='+v.videoWidth+'x'+v.videoHeight," +
        "'total='+(q.totalVideoFrames===undefined?'NA':q.totalVideoFrames)," +
        "'drop='+(q.droppedVideoFrames===undefined?'NA':q.droppedVideoFrames)," +
        "'buf='+(v.buffered.length?v.buffered.end(v.buffered.length-1).toFixed(1):'-')," +
        "'q='+(window.__rtQSet||'?'),'err='+(v.error?v.error.code:0)," +
        "(window.__rtWdMsg?'wd='+window.__rtWdMsg:'')].join(' ');" +
        "}catch(e){return 'diagerr';}}" +
        // orientation reporter (portrait-safe: landscape only when proven wider)
        "function report(){var fe=document.fullscreenElement||document.webkitFullscreenElement||document.mozFullScreenElement;" +
        "if(!fe){document.title='RTFS:0|'+diag();return;}" +
        "var v=document.querySelector('video');var land=false;" +
        "if(v&&v.videoWidth&&v.videoHeight)land=(v.videoWidth>v.videoHeight);" +
        "document.title='RTFS:1:'+(land?'land':'port')+'|'+diag();}" +
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
        // Quality cap: YouTube's ABR otherwise picks by bandwidth and player
        // viewport and drifts around (360p on a slow moment, and it rarely climbs
        // back). We pin the best level up to 720p, stepping down the ladder to
        // whatever this video actually offers. 1080p is deliberately NOT in the
        // ladder: on older devices FHD decoding/scaling can't keep up and the
        // playback stutters, so 720p is the ceiling. setPlaybackQualityRange is the
        // sticky one (ABR does not immediately override it); setPlaybackQuality is
        // fired too since older player builds only honour that. The level list is
        // empty until the player has media attached, so we retry until it answers,
        // and re-apply on every "playing" (an ad and the content that follows are
        // separate media with separate ladders).
        "var RTQ=['hd720','large','medium','small','tiny'];" +
        "window.__rtQSet='';" +
        "function setQ(){var p=document.getElementById('movie_player');" +
        "if(!p||typeof p.getAvailableQualityLevels!=='function')return false;" +
        "var av=[];try{av=p.getAvailableQualityLevels()||[];}catch(e){return false;}" +
        "if(!av.length)return false;" +
        "for(var i=0;i<RTQ.length;i++){if(av.indexOf(RTQ[i])<0)continue;" +
        "try{p.setPlaybackQualityRange(RTQ[i],RTQ[i]);}catch(e){}" +
        "try{p.setPlaybackQuality(RTQ[i]);}catch(e){}" +
        "window.__rtQSet=RTQ[i];return true;}return false;}" +
        "var qn=0;var qk=setInterval(function(){qn++;if(setQ()||qn>60)clearInterval(qk);},500);" +
        // Background economy. Keeping the WebView alive is what lets the audio
        // play on with the app minimised or the display off (see the `active`
        // override below), but it also keeps Gecko decoding and compositing
        // every frame at full resolution for nobody: measured on a POCO M4 Pro,
        // a backgrounded 720p watch page still held the GPU at ~70% and drew
        // ~2.8W — as much as with the screen on. So drop to the lowest quality
        // on the way out and restore it on the way back. The audio track is
        // untouched (it is a separate stream, and its bitrate does not follow
        // the video ladder), so this costs the listener nothing. What was
        // playing is remembered from the player itself, not from our own cap,
        // so a quality the user picked by hand survives the round trip.
        "function lowestQ(p){try{var av=p.getAvailableQualityLevels()||[];" +
        "for(var i=RTQ.length-1;i>=0;i--)if(av.indexOf(RTQ[i])>=0)return RTQ[i];}catch(e){}return 'tiny';}" +
        "window.__rtBg=function(on){var p=document.getElementById('movie_player');" +
        "if(!p||typeof p.setPlaybackQualityRange!=='function')return;var q;" +
        "if(on){if(!window.__rtQPrev){var cur='';" +
        "try{cur=p.getPlaybackQuality();}catch(e){}" +
        "window.__rtQPrev=cur||window.__rtQSet||'hd720';}" +
        "q=lowestQ(p);}else{q=window.__rtQPrev||'hd720';window.__rtQPrev='';}" +
        "try{p.setPlaybackQualityRange(q,q);}catch(e){}" +
        "try{p.setPlaybackQuality(q);}catch(e){}window.__rtQSet=q;};" +
        // Frozen-picture watchdog. On this engine the video decoder can end up
        // starved of graphic buffers at high resolution: it keeps decoding at
        // full rate, but the frames come back too late to be painted, so Gecko
        // drops every one of them — the picture freezes while the audio (a
        // separate, software-decoded track) plays on, and the pipeline never
        // recovers by itself. Measured on a POCO M4 Pro at 1080p60: the MTK
        // decoder logged `last successful dequeue was 3491356 us ago` while
        // droppedVideoFrames grew exactly as fast as totalVideoFrames.
        // So: watch those two counters, and when the dropped count keeps pace
        // with the decoded count for ~2s while the clock is still running, treat
        // the picture as frozen and re-prime the pipeline. A hair-thin seek is
        // enough (it flushes the decoder and its buffer queue); if that does not
        // take, replay, and as a last resort step the quality down a notch,
        // which also makes a relapse less likely. Recoveries are rate-limited to
        // one per 5s and reported to QML for the journal.
        "var WD={total:0,drop:0,bad:0,ok:0,fixAt:0,step:0};" +
        "function wdFix(v,p){var t=v.currentTime;WD.step++;" +
        "if(WD.step===1){if(p&&p.seekTo)p.seekTo(t+0.05,true);else v.currentTime=t+0.05;" +
        "return 'seek@'+t.toFixed(1);}" +
        "if(WD.step===2){if(p&&p.pauseVideo&&p.playVideo){p.pauseVideo();" +
        "setTimeout(function(){try{p.playVideo();}catch(e){}},150);return 'replay@'+t.toFixed(1);}" +
        "return 'noapi@'+t.toFixed(1);}" +
        "WD.step=0;var cur=window.__rtQSet||'';var i=RTQ.indexOf(cur);" +
        "if(i>=0&&i+1<RTQ.length&&p&&p.setPlaybackQualityRange){var nx=RTQ[i+1];" +
        "try{p.setPlaybackQualityRange(nx,nx);}catch(e){}try{p.setPlaybackQuality(nx);}catch(e){}" +
        "window.__rtQSet=nx;return 'quality→'+nx+'@'+t.toFixed(1);}" +
        "if(p&&p.seekTo)p.seekTo(t+0.05,true);return 'seek2@'+t.toFixed(1);}" +
        "setInterval(function(){var v=document.querySelector('video');if(!v)return;" +
        "var p=document.getElementById('movie_player');" +
        "if(v.paused||v.seeking||v.readyState<3){WD.bad=0;return;}" +
        "var q=null;try{q=v.getVideoPlaybackQuality?v.getVideoPlaybackQuality():null;}catch(e){}" +
        "if(!q||q.totalVideoFrames===undefined)return;" +
        "var dt=q.totalVideoFrames-WD.total,dd=q.droppedVideoFrames-WD.drop;" +
        "WD.total=q.totalVideoFrames;WD.drop=q.droppedVideoFrames;" +
        "if(dt>0&&dd>=dt*0.9){WD.bad++;WD.ok=0;}else{WD.bad=0;if(++WD.ok>40)WD.step=0;}" +
        "if(WD.bad<4)return;" +
        "var now=Date.now();if(now-WD.fixAt<5000)return;WD.fixAt=now;WD.bad=0;" +
        "window.__rtWdMsg=wdFix(v,p);report();" +
        "setTimeout(function(){window.__rtWdMsg='';},4000);" +
        "},500);" +
        // re-report when real dimensions arrive (metadata / resize / playback)
        "function hookV(v){if(!v||v.__rtV)return;v.__rtV=1;" +
        "['loadedmetadata','resize','playing'].forEach(function(e){v.addEventListener(e,report);});" +
        "v.addEventListener('playing',function(){setTimeout(setQ,600);});}" +
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

    // Keep the display on while watching. The video plays inside the WebView, so
    // there is no play/pause state on the QML side to gate on — instead prevent
    // blanking for as long as the watch page is up, this page is on top and the
    // app is focused (backgrounding or navigating away re-enables normal blanking).
    DisplayBlanking {
        preventBlanking: page.ready && page.status === PageStatus.Active
                         && Qt.application.active
    }

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
        // Background playback. Sailfish.WebView binds `active` to
        // `Qt.application.state === Qt.ApplicationActive` (see its WebView.qml), so
        // minimising to the cover or blanking the display suspends the view and the
        // video stops — the one thing the system browser did better. `active` is a
        // writable QuickMozView property and that binding is the only one touching
        // it, so overriding it here is enough. Tied to the page rather than
        // hardcoded true, so leaving the player still suspends Gecko.
        active: page.status !== PageStatus.Inactive
        // Keep it rendering (so it loads) but invisible until the watch page is up
        // (so the embed's error-153 page is never seen). The watch page itself is
        // fine to show — it auto-goes fullscreen, and the plain page when not.
        opacity: page.ready ? 1.0 : 0.0
        Behavior on opacity { FadeAnimation {} }

        // Throttle the video to the cheapest level whenever the app is not in
        // the foreground (minimised to the cover, or the display blanked), and
        // put it back on return — see __rtBg above for why this matters.
        property bool appActive: Qt.application.active
        onAppActiveChanged: {
            if (!page.ready)
                return
            runJavaScript("window.__rtBg&&window.__rtBg(" + (appActive ? "false" : "true") + ")")
        }

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
            var bar = t.indexOf("|")
            var fs = bar >= 0 ? t.substring(0, bar) : t
            if (bar >= 0) {
                // Journal only around a watchdog recovery (the event itself plus
                // the next few seconds, so a report shows whether it took):
                // `sudo journalctl -b --no-pager | grep "YT diag"`. Steady-state
                // playback stays silent.
                var payload = t.substring(bar + 1)
                var now = Date.now()
                if (payload.indexOf("wd=") >= 0)
                    lastWdSeen = now
                if (now - lastWdSeen < 8000 && now - lastDiagLog > 1000) {
                    lastDiagLog = now
                    console.log("[RooTheater] YT diag: " + payload)
                }
            }
            if (fs === "RTFS:0")
                page.fsMode = 0
            else if (fs.indexOf(":land") > 0)
                page.fsMode = 1
            else if (fs.indexOf(":port") > 0)
                page.fsMode = 2
        }
        property double lastDiagLog: 0
        property double lastWdSeen: 0
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
