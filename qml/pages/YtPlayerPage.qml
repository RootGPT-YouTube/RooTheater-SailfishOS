import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.WebView 1.0

// In-app YouTube playback. The bare /embed/ player fails on this engine (needs a
// session/PoToken it can't produce → "An error occurred"), but the full mobile
// WATCH page plays (it builds its own session — same as the Sailfish browser).
// The app's fresh WebView profile lacks Google's consent cookie though, which
// made the watch page fail/crash on the consent gate. So: first load the embed
// (a real youtube.com-origin doc that loads fine) to set the consent cookie via
// document.cookie, then navigate to the watch page — now consent is satisfied.
// The cookie persists in the profile, so this is a one-time step per install.
Page {
    id: page
    allowedOrientations: Orientation.All

    property string videoId: ""
    property string title: ""

    readonly property string embedUrl:
        "https://www.youtube.com/embed/" + videoId
    readonly property string watchUrl:
        "https://m.youtube.com/watch?v=" + videoId

    WebView {
        id: web
        anchors.fill: parent
        url: page.embedUrl

        // After the embed (youtube.com origin) loads, set consent then go to watch.
        property bool consentDone: false
        onLoadingChanged: {
            if (!loading && !consentDone) {
                consentDone = true
                runJavaScript(
                    "try{var e='; domain=.youtube.com; path=/; max-age=31536000';" +
                    "document.cookie='SOCS=CAI'+e;" +
                    "document.cookie='CONSENT=YES+1'+e;}catch(x){}")
                gotoWatch.start()
            }
        }
        Timer { id: gotoWatch; interval: 400; onTriggered: web.url = page.watchUrl }

        PullDownMenu {
            MenuItem {
                text: qsTr("Open in browser")
                onClicked: Qt.openUrlExternally(page.watchUrl)
            }
            MenuItem {
                text: qsTr("Reload")
                onClicked: { web.consentDone = false; web.url = page.embedUrl }
            }
        }
    }
}
