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
                description: page.statusText
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
