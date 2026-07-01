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
    Component.onCompleted: feed.loadChannels([ channelId ])

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

        header: PageHeader {
            title: page.channelName.length > 0 ? page.channelName : qsTr("Channel")
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
                onClicked: feed.loadChannels([ page.channelId ])
            }
        }

        ViewPlaceholder {
            enabled: feed.count === 0 && !feed.loading
            text: qsTr("No recent videos")
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

            onClicked: Qt.openUrlExternally("https://m.youtube.com/watch?v=" + model.videoId)

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
