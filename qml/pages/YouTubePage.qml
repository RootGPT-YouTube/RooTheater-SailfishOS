import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Pickers 1.0
import RooTheater.Media 1.0

// The YouTube "subscriptions" view (100% keyless / zero Data API quota): the
// recent videos of every followed channel, merged from their public RSS feeds.
// Videos and channels are found via in-app search (YtSearchPage — channels are
// subscribed right from the results), and the subscription list can be
// imported/exported. Playback opens in the in-app player (YtPlayerPage).
Page {
    id: page
    allowedOrientations: Orientation.All

    // Transient status line (import/export/add results), auto-cleared.
    property string statusText: ""
    Timer { id: statusTimer; interval: 5000; onTriggered: page.statusText = "" }
    function notify(msg) { page.statusText = msg; statusTimer.restart() }

    // The aggregated feed of all subscribed channels.
    YtFeed { id: feed }

    function reloadFeed() { feed.loadChannels(ytSubs.channelIds()) }

    Component.onCompleted: reloadFeed()

    Connections {
        target: ytSubs
        onAdded: { page.notify(qsTr("Added: %1").arg(name)); page.reloadFeed() }
        onError: page.notify(name)   // signal arg is the message
        // Backfill (avatars/ids) done → reload feeds so everything is settled.
        onFillFinished: page.reloadFeed()
    }

    // ── relative "time ago" for a ms-since-epoch timestamp ───────────────────
    function timeAgo(ms) {
        if (!ms || ms <= 0)
            return ""
        var s = Math.max(0, Math.floor((Date.now() - ms) / 1000))
        if (s < 3600)  return qsTr("%1 min ago").arg(Math.floor(s / 60))
        if (s < 86400) return qsTr("%1 h ago").arg(Math.floor(s / 3600))
        var d = Math.floor(s / 86400)
        if (d < 30)    return qsTr("%1 d ago").arg(d)
        return Qt.formatDate(new Date(ms), Qt.DefaultLocaleShortDate)
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: feed

        header: Column {
            width: list.width
            PageHeader {
                title: qsTr("YouTube")
                // Transient notifications win; otherwise report channels whose
                // feed failed, so a partial load is never mistaken for the truth.
                description: page.statusText !== "" ? page.statusText
                           : feed.failedCount > 0
                             ? qsTr("%n channel(s) could not be loaded", "", feed.failedCount)
                             : ""
            }
            // YouTube's feed service can be down while YouTube itself is up: on
            // 2026-09-05 feeds/videos.xml answered 404/500 for every channel while
            // the channel pages still answered 200. The list below then comes from
            // the copy saved on disk — say so, and say when, instead of letting an
            // old list pass for a fresh one. The videos in it still play: playback
            // goes to the watch page, which needs only the video id.
            Label {
                visible: feed.staleCount > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.highlightColor
                // Two separate sentences rather than one with a %1 that is
                // sometimes a date and sometimes a word: "saved on 5/9/26" and
                // "the last saved list" do not share a grammatical shape, in
                // English or in Italian.
                text: feed.staleSince > 0
                      ? qsTr("YouTube is not serving its video feeds right now. Showing the list saved on %1 — the videos still play.")
                        .arg(Qt.formatDateTime(new Date(feed.staleSince), Qt.DefaultLocaleShortDate))
                      : qsTr("YouTube is not serving its video feeds right now. Showing the last saved list — the videos still play.")
            }
            // Import / backfill progress: fetching channel avatars & ids.
            ProgressBar {
                width: parent.width
                visible: ytSubs.filling
                indeterminate: ytSubs.fillProgress <= 0
                value: ytSubs.fillProgress
                minimumValue: 0
                maximumValue: 1
                label: qsTr("Importing channels…")
                valueText: Math.round(ytSubs.fillProgress * 100) + "%"
            }
        }

        PullDownMenu {
            MenuItem {
                text: qsTr("Search videos and channels")
                onClicked: pageStack.push(Qt.resolvedUrl("YtSearchPage.qml"))
            }
            MenuItem {
                text: qsTr("Import subscriptions")
                onClicked: pageStack.push(importPicker)
            }
            MenuItem {
                text: qsTr("Export subscriptions")
                enabled: ytSubs.count > 0
                onClicked: {
                    var p = ytSubs.exportToDir("")   // → Downloads
                    page.notify(p.length > 0 ? qsTr("Exported to %1").arg(p)
                                             : qsTr("Export failed"))
                }
            }
            // A big import fetches the avatars in the background; if some are
            // still missing (a channel page that would not answer), this asks
            // for them again without waiting for the next app start.
            MenuItem {
                text: qsTr("Fetch %n missing avatar(s)", "", ytSubs.missingAvatars)
                visible: ytSubs.missingAvatars > 0 && !ytSubs.filling
                onClicked: ytSubs.fillMissing()
            }
            MenuItem {
                text: qsTr("Reload")
                enabled: ytSubs.count > 0
                onClicked: page.reloadFeed()
            }
        }

        ViewPlaceholder {
            enabled: ytSubs.count === 0 && !ytSubs.busy
            text: qsTr("No subscriptions")
            hintText: qsTr("Pull down to search videos and channels, or import a subscriptions file.")
        }

        // Subscriptions exist but every feed failed: that is a load error, not an
        // empty account. Without this it reads as "your channels have no videos".
        ViewPlaceholder {
            enabled: ytSubs.count > 0 && feed.count === 0
                     && !feed.loading && !ytSubs.busy && feed.failedCount > 0
            text: qsTr("Could not load the feeds")
            hintText: qsTr("YouTube did not answer: %1\nPull down to retry.")
                      .arg(feed.lastError)
        }

        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: feed.loading || ytSubs.busy
        }

        delegate: ListItem {
            id: item
            width: parent.width
            contentHeight: thumb.height + 2 * Theme.paddingMedium

            onClicked: pageStack.push(Qt.resolvedUrl("YtPlayerPage.qml"),
                                      { videoId: model.videoId, title: model.title })

            Image {
                id: thumb
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * 0.42
                height: width * 9 / 16
                fillMode: Image.PreserveAspectCrop
                clip: true
                asynchronous: true
                source: model.thumbnail
            }
            Column {
                anchors {
                    left: thumb.right; leftMargin: Theme.paddingMedium
                    right: parent.right; rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                spacing: 2
                Label {
                    width: parent.width
                    text: model.title
                    maximumLineCount: 2
                    wrapMode: Text.WordWrap
                    truncationMode: TruncationMode.Elide
                    font.pixelSize: Theme.fontSizeSmall
                    color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    text: model.channelName + "  ·  " + page.timeAgo(model.published)
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                }
            }
        }

        VerticalScrollDecorator {}
    }

    // ── import picker (subscriptions .json or full-backup .zip) ──────────────
    // No nameFilters: show ALL files so the backup is findable wherever it lives
    // and whatever it's named (a subscriptions export is a .json; a full-database
    // backup .zip is also accepted — importFile reads either and reports a clear
    // error if the picked file is neither).
    Component {
        id: importPicker
        FilePickerPage {
            title: qsTr("Select a subscriptions file or backup")
            onSelectedContentPropertiesChanged: {
                ytSubs.importFile(selectedContentProperties.filePath)
            }
        }
    }
}
