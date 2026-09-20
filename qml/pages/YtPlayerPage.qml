import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.WebView 1.0
import Sailfish.WebEngine 1.0
import Nemo.KeepAlive 1.2
import Nemo.Configuration 1.0

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
        "'buf2='+(v.buffered.length?v.buffered.length:0)," +
        "'hr='+headroom(v),'gaps='+gapInfo(v)," +
        // `q` is only what WE asked the player for; `qa` is what it reports as
        // actually playing. Keeping them apart matters: on 2026-09-20 the trace
        // showed q=hd720 with size=640x360 for eight seconds, i.e. the cap says one
        // thing and the picture is another — with `q` alone that looks like a 720p
        // stream stuttering, which would send the diagnosis the wrong way.
        "'q='+(window.__rtQSet||'?'),'qa='+qActual()," +
        // Our ceiling, next to what is actually playing: with a range instead of a
        // nail the two are meant to differ, and `qa` sitting BELOW `cap` is ABR doing
        // its job on a link that dipped — the behaviour the nail used to forbid.
        "'cap='+((typeof RTQ!=='undefined'&&RTQ[window.__rtCapIdx||0])||'?')," +
        "'ur='+(window.__rtUrTot||0)," +
        "'err='+(v.error?v.error.code:0)," +
        "(window.__rtWdMsg?'wd='+window.__rtWdMsg:'')," +
        "(window.__rtEv?'ev='+window.__rtEv:'')].join(' ');" +
        "}catch(e){return 'diagerr';}}" +
        // Buffer headroom: seconds of video ready AHEAD of the playhead, and the
        // number the stutter diagnosis turns on — the field report is "it stalls
        // when it grazes the buffering", i.e. the picture starves of DATA, not of
        // graphic buffers. -1 = nothing buffered. `buf2` counts the buffered
        // ranges: more than one means a gap, which starves the picture just the
        // same even when the far end looks comfortable.
        // ⚠️ Measure to the end of the range the PLAYHEAD IS IN, not to the end of
        // the last range. MSE buffers are not one contiguous block: on 2026-09-20
        // this trace showed buf2=2 nine seconds into a video, so the far end sat
        // BEYOND a gap and the first version of this function reported hr=24.6 when
        // the picture was actually a few seconds from starving. That is the very
        // case the field report describes ("it stalls when it grazes the
        // buffering"), so getting it wrong would have hidden the symptom we are
        // hunting. 0 = the playhead is in no range at all, i.e. starving now.
        "function headroom(v){try{var b=v.buffered;if(!b.length)return -1;" +
        "var t=v.currentTime;" +
        "for(var i=0;i<b.length;i++){" +
        "if(t>=b.start(i)-0.1&&t<=b.end(i))return +(b.end(i)-t).toFixed(1);}" +
        "return 0;}catch(e){return -1;}}" +
        "function qActual(){try{var p=document.getElementById('movie_player');" +
        "if(p&&p.getPlaybackQuality)return p.getPlaybackQuality()||'?';}catch(e){}return '?';}" +
        // The shape of the holes, which is what names the cause. On 2026-09-20 a
        // stutter was caught with buf2=46: the MSE buffer had shattered into 46
        // ranges while the network was fine (buf was still growing, 49s → 66s
        // ahead), and the decoder starved at the gaps — total collapsed from +72
        // frames per tick to +11 and readyState fell to 2. Whether the gaps are
        // hairline (segments that fail to coalesce, a timestamp-rounding problem)
        // or wide (data actually thrown away, i.e. eviction) points at completely
        // different levers, and the two look identical in a count. Reported as
        // <size>@<where>, for the first three gaps at or after the playhead.
        "function gapInfo(v){try{var b=v.buffered;if(b.length<2)return '-';" +
        "var t=v.currentTime;var o=[];" +
        "for(var i=0;i<b.length-1&&o.length<3;i++){if(b.end(i)<t-1)continue;" +
        "o.push((+(b.start(i+1)-b.end(i)).toFixed(3))+'@'+b.end(i).toFixed(1));}" +
        "return o.length?o.join(','):'-';}catch(e){return '?';}}" +
        // Flight recorder. The stutter is rare — hours or days apart — so neither
        // obvious logging shape works: a line every 2s would fill the journal for
        // days to catch one event, and logging only AT the event shows the instant
        // without the run-up, which is the part that separates a starving buffer
        // from a wedged pipeline. So keep the last 30 samples (one per probe tick,
        // ~60s) in the page and let the event itself flush them to the journal.
        // Silent until something happens: nobody has to catch the fault in the act.
        "var RB=[];var T0=Date.now();var DUMP={at:0};" +
        "function rbPush(){try{RB.push('+'+((Date.now()-T0)/1000).toFixed(0)+'s '+diag());" +
        "if(RB.length>30)RB.shift();}catch(e){}}" +
        // One dump per 30s at most, window emptied after a flush so two dumps never
        // repeat samples. The event line itself is logged live regardless.
        "function rbDump(tag){var now=Date.now();if(DUMP.at&&now-DUMP.at<30000)return;" +
        "DUMP.at=now;try{document.title='RTDUMP:'+tag+'|'+RB.join(';');}catch(e){}RB=[];}" +
        // Underrun probe — OBSERVATION ONLY. `waiting`/`stalled` fire exactly when
        // the picture runs out of data, the moment the field report describes, and
        // the watchdog below is deliberately blind to it (it stands down on
        // readyState<3, rightly: that is buffering, not a wedged decoder). Nothing
        // here touches the quality: an earlier attempt to also CURE the underrun by
        // widening the quality range crashed the app on this device (SIGSEGV on
        // Gecko's MediaPDecoder thread, 2026-09-20, twice out of two starts), so
        // measuring and curing are kept strictly apart until the trace says what
        // the cure should be.
        "window.__rtUrTot=0;" +
        // A `waiting` before playback has ever begun is not a stutter, it is the
        // player fetching its first bytes — seen on 2026-09-20 as wait@0.0 with
        // rs=0, and it burned the one-dump-per-30s budget at the very moment a real
        // event might have followed. Same for one that lands while seeking. So the
        // counter only opens after the first `playing`.
        "function onWait(){var v=document.querySelector('video');if(!v)return;" +
        "if(!window.__rtStarted||v.seeking)return;" +
        "window.__rtUrTot++;window.__rtEv='wait@'+(v.currentTime||0).toFixed(1)" +
        "+' hr='+headroom(v);report();rbPush();rbDump('underrun');" +
        "setTimeout(function(){window.__rtEv='';},3000);}" +
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
        "window.__rtQSet='';window.__rtCapIdx=0;" +
        "function avQ(p){try{return p.getAvailableQualityLevels()||[];}catch(e){return [];}}" +
        // Apply the ceiling as a RANGE (floor..ceiling), never min==max. This is the
        // whole point: 1.4.0 called setPlaybackQualityRange(X,X), which does not cap
        // the quality but NAILS it, and the same stickiness that made the cap
        // survive ABR also took away the one thing that keeps the picture alive on a
        // link that moves — dropping a rung when the bandwidth drops.
        //
        // Measured on the POCO on 2026-09-20, same video, same wifi, minutes apart:
        // 611 kbit/s while the picture was stalled with hr=0, and 3003 kbit/s while
        // it played clean and the buffer grew 1.6x faster than realtime. The stream
        // itself is ~1.9 Mbit/s. So the link swings by a factor of five, which is
        // exactly the case ABR exists for, and the nail forbade it. It is also why
        // lowering the quality BY HAND cured the stutter: the viewer was doing what
        // the player was not allowed to do.
        "function applyCap(p){var av=avQ(p);if(!av.length)return false;" +
        "var top='';for(var i=window.__rtCapIdx;i<RTQ.length;i++){" +
        "if(av.indexOf(RTQ[i])>=0){top=RTQ[i];break;}}" +
        "if(!top)return false;var flo=lowestQ(p);" +
        "try{p.setPlaybackQualityRange(flo,top);}catch(e){}" +
        "try{p.setPlaybackQuality(top);}catch(e){}" +
        "window.__rtQSet=top;return true;}" +
        "function setQ(){var p=document.getElementById('movie_player');" +
        "if(!p||typeof p.getAvailableQualityLevels!=='function')return false;" +
        "return applyCap(p);}" +
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
        // __rtFg also tells the watchdog whether anyone is looking: see its gate.
        "window.__rtFg=1;" +
        "window.__rtBg=function(on){window.__rtFg=on?0:1;" +
        "var p=document.getElementById('movie_player');" +
        "if(!p||typeof p.setPlaybackQualityRange!=='function')return;" +
        // Going out, a NAILED lowest level is the point rather than a defect: nobody
        // is watching and we want the cheapest stream, full stop. Coming back, the
        // stream is handed to applyCap so the restored level is a range again and ABR
        // keeps its freedom — restoring a nail is what let a stall outlive the return
        // to the foreground. What survives the round trip is our ceiling, not the
        // exact level: inside the range the player picks for itself anyway.
        "if(on){var q=lowestQ(p);" +
        "try{p.setPlaybackQualityRange(q,q);}catch(e){}" +
        "try{p.setPlaybackQuality(q);}catch(e){}window.__rtQSet=q;return;}" +
        "applyCap(p);};" +
        // Frozen-picture watchdog. On this engine the video pipeline can wedge
        // while the audio (a separate, software-decoded track) plays on, and it
        // never recovers by itself. It wedges in two distinct shapes, and the
        // watchdog has to know both — the second one was missed for a whole
        // release because the detector only looked for the first:
        //
        //  A. decoding, painting nothing. The decoder is starved of graphic
        //     buffers: it keeps producing at full rate but the frames come back
        //     too late, so Gecko drops every one. Measured on a POCO M4 Pro at
        //     1080p60, the MTK decoder logged `last successful dequeue was
        //     3491356 us ago` while droppedVideoFrames grew exactly as fast as
        //     totalVideoFrames.
        //  B. producing nothing at all. Both counters stop dead while the clock
        //     keeps running. Journal of 2026-09-04, at 360p — so this is not a
        //     high-resolution problem: total/drop sat at 1308/276 for seconds
        //     while currentTime advanced 40.2 → 42.6. Shape A's test (dropped
        //     keeping pace with decoded) is FALSE here, because nothing is
        //     decoded: the old detector read that as healthy and stood down
        //     exactly when the picture was most stuck.
        //
        // So: sample both counters and the clock. Shape A is "dropped keeps pace
        // with decoded", shape B is "clock moving, decoder producing nothing";
        // either one, held for ~2s while not paused/seeking/buffering, means the
        // picture is frozen. Then re-prime the pipeline: a hair-thin seek first
        // (it flushes the decoder and its buffer queue), replay if that does not
        // take, and as a last resort step the quality down a notch, which also
        // makes a relapse less likely. Recoveries are rate-limited to one per 5s
        // and reported to QML for the journal.
        "var WD={total:0,drop:0,t:-1,bad:0,ok:0,fixAt:0,step:0};" +
        "function wdFix(v,p){var t=v.currentTime;WD.step++;" +
        "if(WD.step===1){if(p&&p.seekTo)p.seekTo(t+0.05,true);else v.currentTime=t+0.05;" +
        "return 'seek@'+t.toFixed(1);}" +
        "if(WD.step===2){if(p&&p.pauseVideo&&p.playVideo){p.pauseVideo();" +
        "setTimeout(function(){try{p.playVideo();}catch(e){}},150);return 'replay@'+t.toFixed(1);}" +
        "return 'noapi@'+t.toFixed(1);}" +
        // Last resort: one notch off the CEILING, which also makes a relapse less
        // likely. It has to move the ceiling rather than nail a level, or it would
        // undo the range the fix above is built on. The ceiling is our own state, so
        // the old tangle of reading the level back out of the player is gone, and
        // with it the `q=?` case that quietly degraded this step into a second
        // pointless seek (journal of 2026-09-04).
        "WD.step=0;" +
        "if(window.__rtCapIdx+1<RTQ.length){window.__rtCapIdx++;" +
        "if(p)applyCap(p);return 'capdown→'+RTQ[window.__rtCapIdx]+'@'+t.toFixed(1);}" +
        "if(p&&p.seekTo)p.seekTo(t+0.05,true);return 'seek2@'+t.toFixed(1);}" +
        "setInterval(function(){var v=document.querySelector('video');if(!v)return;" +
        "var p=document.getElementById('movie_player');" +
        // Stand down when there is nothing on screen to fix. In the background the
        // video is deliberately nailed to 144p for nobody, while both cures — a seek
        // and a pause/play — land squarely on the AUDIO the listener is hearing.
        // Worse, this engine suspends background video by itself
        // (media.suspend-bkgnd-video.* exists in libxul here), which looks exactly
        // like shape B: the watchdog was "reviving" a deliberate battery
        // optimisation. The journal of 2026-09-18 holds two such episodes, both at
        // 256x144, and in both the 273 dropped frames of shape A appear in the
        // sample AFTER our own seek — the cure manufacturing the symptom.
        "if(!window.__rtFg||v.paused||v.seeking||v.readyState<3){WD.bad=0;WD.t=-1;return;}" +
        "var q=null;try{q=v.getVideoPlaybackQuality?v.getVideoPlaybackQuality():null;}catch(e){}" +
        "if(!q||q.totalVideoFrames===undefined)return;" +
        "var ct=v.currentTime;" +
        "if(WD.t<0){WD.t=ct;WD.total=q.totalVideoFrames;WD.drop=q.droppedVideoFrames;return;}" +
        "var dt=q.totalVideoFrames-WD.total,dd=q.droppedVideoFrames-WD.drop,dc=ct-WD.t;" +
        "WD.total=q.totalVideoFrames;WD.drop=q.droppedVideoFrames;WD.t=ct;" +
        "var stuck=(dt>0&&dd>=dt*0.9)||(dt===0&&dc>0.2);" +
        "if(stuck){WD.bad++;WD.ok=0;}else{WD.bad=0;if(++WD.ok>40)WD.step=0;}" +
        "if(WD.bad<4)return;" +
        "var now=Date.now();if(now-WD.fixAt<5000)return;WD.fixAt=now;WD.bad=0;" +
        "window.__rtWdMsg=wdFix(v,p);report();rbPush();rbDump('wd');" +
        "setTimeout(function(){window.__rtWdMsg='';},4000);" +
        "},500);" +
        // re-report when real dimensions arrive (metadata / resize / playback)
        "function hookV(v){if(!v||v.__rtV)return;v.__rtV=1;" +
        "['loadedmetadata','resize','playing'].forEach(function(e){v.addEventListener(e,report);});" +
        "['waiting','stalled'].forEach(function(e){v.addEventListener(e,onWait);});" +
        "v.addEventListener('playing',function(){window.__rtStarted=1;setTimeout(setQ,600);});}" +
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
        // Continuous probe (2s), two jobs in one timer. It feeds the flight recorder
        // so a whole viewing session can be read back after the fact — the old probe
        // only spoke inside a ±8s window around a watchdog intervention, which is
        // precisely why a steady stutter left no trace. And it re-hooks the video
        // element, which YouTube swaps when an ad gives way to the content: the
        // fullscreen starter above hooks it once and then clears itself, so without
        // this the underrun listeners would die with the first element.
        "setInterval(function(){hookV(document.querySelector('video'));report();rbPush();},2000);" +
        "})()"

    // Keep the display on while watching. The video plays inside the WebView, so
    // there is no play/pause state on the QML side to gate on — instead prevent
    // blanking for as long as the watch page is up, this page is on top and the
    // app is focused (backgrounding or navigating away re-enables normal blanking).
    DisplayBlanking {
        preventBlanking: page.ready && page.status === PageStatus.Active
                         && Qt.application.active
    }

    // Full-session diagnostics for the journal, off by default (a line every two
    // seconds is noise unless someone is reading it). The flight-recorder dumps
    // below do NOT depend on this: they fire on their own at every event.
    //   dconf write /apps/harbour-rootheater/yt/diag true
    ConfigurationValue {
        id: ytDiag
        key: "/apps/harbour-rootheater/yt/diag"
        defaultValue: false
    }

    // Serve H.264 instead of VP9 (see Component.onCompleted). ON unless the viewer
    // turns it off in Options, so the sense of the test is "not switched off"
    // rather than "switched on" — and it is written against both false and "false"
    // because dconf hands these back as strings here, as PermissionSwitch guards
    // for too.
    ConfigurationValue {
        id: ytForceH264
        key: "/apps/harbour-rootheater/yt/forceH264"
        defaultValue: true
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
        // Codec choice: turning WebM off in MSE makes YouTube serve H.264/mp4, which
        // lands on a DIFFERENT vendor component (c2.mtk.avc.decoder instead of
        // c2.mtk.vp9.decoder). Reason to try it: on 2026-09-20 the trace caught the
        // picture stalling with readyState=2 — Gecko announcing "not enough data",
        // YouTube showing its spinner — while 39 seconds of CONTIGUOUS video sat in
        // the buffer (buf2=1, gaps=-). The data is there and the decoder is not
        // delivering, and the same hardware path took a SIGSEGV that morning. The
        // 25-30% extra bitrate H.264 costs would matter if the buffer were starving;
        // the measurement says it is not.
        //
        // Set HERE and not on the page that lists the videos: a video can be opened
        // from the Home grid through YtChannelPage, so that page is not on every
        // path. Here is early enough — this pref is read when the watch page's JS
        // probes MSE support, which is hundreds of milliseconds later, after the
        // document has come over the network. (The worry about children completing
        // before their parent is real, but it only bites prefs read at engine or
        // compositor init, not this one.)
        //
        // On by default; the switch lives in Options → YouTube.
        if (ytForceH264.value !== false && ytForceH264.value !== "false") {
            WebEngineSettings.setPreference("media.mediasource.webm.enabled", false)
            WebEngineSettings.setPreference("media.mediasource.vp9.enabled", false)
            console.log("[RooTheater] YT codec: WebM/VP9 off in MSE → expecting H.264")
        } else {
            console.log("[RooTheater] YT codec: default (VP9), forceH264="
                        + ytForceH264.value)
        }
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
            // Flight-recorder flush: a single title change carrying the ~60s that
            // led up to an underrun or a watchdog recovery, oldest sample first.
            // This is what makes a stutter that happens once in hours or days
            // legible after the fact, without anyone watching when it lands.
            if (t.indexOf("RTDUMP:") === 0) {
                var db = t.indexOf("|")
                var tag = t.substring(7, db < 0 ? t.length : db)
                var rows = db < 0 ? [] : t.substring(db + 1).split(";")
                console.log("[RooTheater] YT window (" + tag + "): "
                            + rows.length + " samples before the event")
                for (var i = 0; i < rows.length; ++i) {
                    if (rows[i] !== "")
                        console.log("[RooTheater] YT diag: " + rows[i])
                }
                // Keep logging live for the next few seconds, so the trace also
                // shows whether the picture came back.
                lastWdSeen = Date.now()
                return
            }
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
                var interesting = payload.indexOf("ev=") >= 0
                                  || now - lastWdSeen < 8000
                if ((interesting || ytDiag.value === true)
                        && now - lastDiagLog > 1000) {
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
