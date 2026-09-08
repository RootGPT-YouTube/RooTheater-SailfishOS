import QtQuick 2.0
import Sailfish.Silica 1.0
import RooTheater.Media 1.0

// A single subscribed channel's recent videos (from its public RSS feed).
// Opened from the Home "YouTube RSS" grid. Offers unsubscribe + open-in-browser.
Page {
    id: page
    allowedOrientations: Orientation.All

    property string channelId: ""
    property string channelName: ""

    YtFeed { id: feed }
    Component.onCompleted: {
        feed.loadChannels([ channelId ])
        // Opening a channel counts as seeing it: clear its unseen badge on Home.
        ytSubs.markSeen(channelId)
    }

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
        anchors.fill: parent
        model: feed

        header: Column {
            width: parent.width

            PageHeader {
                title: page.channelName.length > 0 ? page.channelName : qsTr("Channel")
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
        }

        PullDownMenu {
            MenuItem {
                text: qsTr("Unsubscribe")
                onClicked: {
                    ytSubs.remove(page.channelId)
                    pageStack.pop()
                }
            }
            MenuItem {
                text: qsTr("Open in browser")
                onClicked: Qt.openUrlExternally(
                    "https://www.youtube.com/channel/" + page.channelId)
            }
            MenuItem {
                text: qsTr("Reload")
                onClicked: feed.loadChannels([ page.channelId ], true)
            }
        }

        // A failed fetch and a channel with nothing in it used to look identical
        // here (an empty list, no message). Say which one it is, and why.
        ViewPlaceholder {
            enabled: feed.count === 0 && !feed.loading
            text: feed.failedCount > 0 ? qsTr("Could not load this channel")
                                       : qsTr("No recent videos")
            hintText: feed.failedCount > 0
                      ? qsTr("YouTube did not answer: %1\nPull down to retry.")
                        .arg(feed.lastError)
                      : ""
        }

        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: feed.loading
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
                    text: page.timeAgo(model.published)
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
