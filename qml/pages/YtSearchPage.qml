import QtQuick 2.0
import Sailfish.Silica 1.0
import RooTheater.Media 1.0

// Keyless YouTube search (videos + channels) — see YtSearch.cpp for how the
// results are obtained without any API key. Channels can be subscribed right
// from the results (their id/name/avatar are already resolved); videos open in
// the in-app player. Autocomplete suggestions appear while typing.
Page {
    id: page
    allowedOrientations: Orientation.All

    // Transient status line (subscribe results), auto-cleared.
    property string statusText: ""
    Timer { id: statusTimer; interval: 5000; onTriggered: page.statusText = "" }
    function notify(msg) { page.statusText = msg; statusTimer.restart() }

    // Suggestions are shown while the query is being edited, hidden on search.
    property bool typing: false
    // Query/filter live on the page: ids inside the ListView header component
    // (searchField, filterBox) are NOT in scope here.
    property string query: ""
    property int searchFilter: 0

    YtSearch { id: searcher }

    function doSearch() {
        page.typing = false
        searcher.clearSuggestions()
        page.forceActiveFocus()      // unfocus the field → dismiss the keyboard
        searcher.search(page.query, page.searchFilter)
    }

    Connections {
        target: ytSubs
        onAdded: page.notify(qsTr("Added: %1").arg(name))
        onError: page.notify(name)   // signal arg is the message
    }
    Connections {
        target: searcher
        onError: page.notify(message)
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: searcher

        header: Column {
            width: list.width

            PageHeader {
                title: qsTr("Search YouTube")
                description: page.statusText
            }
            SearchField {
                id: searchField
                width: parent.width
                placeholderText: qsTr("Videos and channels")
                EnterKey.iconSource: "image://theme/icon-m-search"
                EnterKey.onClicked: page.doSearch()
                onTextChanged: {
                    page.query = text
                    page.typing = true
                    suggestTimer.restart()
                }
                // Debounced keyless autocomplete.
                Timer {
                    id: suggestTimer
                    interval: 300
                    onTriggered: if (page.typing) searcher.suggest(searchField.text)
                }
            }
            ComboBox {
                id: filterBox
                width: parent.width
                label: qsTr("Show")
                menu: ContextMenu {
                    MenuItem { text: qsTr("Everything") }
                    MenuItem { text: qsTr("Videos") }
                    MenuItem { text: qsTr("Channels") }
                }
                onCurrentIndexChanged: {
                    page.searchFilter = currentIndex
                    if (page.query.length > 0 && searcher.count > 0)
                        page.doSearch()
                }
            }

            // Tap-to-search suggestions (only while editing the query).
            Column {
                width: parent.width
                visible: page.typing
                Repeater {
                    model: searcher.suggestions
                    delegate: BackgroundItem {
                        width: parent.width
                        height: Theme.itemSizeExtraSmall
                        onClicked: {
                            searchField.text = modelData
                            page.doSearch()
                        }
                        Label {
                            anchors {
                                left: parent.left; leftMargin: Theme.horizontalPageMargin
                                right: parent.right; rightMargin: Theme.horizontalPageMargin
                                verticalCenter: parent.verticalCenter
                            }
                            text: modelData
                            truncationMode: TruncationMode.Fade
                            color: highlighted ? Theme.highlightColor : Theme.secondaryColor
                        }
                    }
                }
            }
        }

        ViewPlaceholder {
            enabled: searcher.count === 0 && !searcher.loading && !page.typing
            text: qsTr("Search YouTube")
            hintText: qsTr("Videos can be watched right away; channels can be added to your subscriptions.")
        }

        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: searcher.loading
        }

        delegate: ListItem {
            id: item
            width: parent.width
            contentHeight: (model.kind === "channel" ? avatarBox.height : thumb.height)
                           + 2 * Theme.paddingMedium
            // The ytSubs.count read makes the binding re-evaluate when a
            // subscription is added/removed (contains() alone wouldn't).
            readonly property bool subscribed:
                ytSubs.count >= 0 && ytSubs.contains(model.channelId)

            onClicked: {
                if (model.kind === "channel")
                    pageStack.push(Qt.resolvedUrl("YtChannelPage.qml"),
                                   { channelId: model.channelId, channelName: model.title })
                else
                    pageStack.push(Qt.resolvedUrl("YtPlayerPage.qml"),
                                   { videoId: model.videoId, title: model.title })
            }

            // ── video row: 16:9 thumbnail + title + byline ───────────────────
            Image {
                id: thumb
                visible: model.kind !== "channel"
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * 0.42
                height: width * 9 / 16
                fillMode: Image.PreserveAspectCrop
                clip: true
                asynchronous: true
                source: model.kind !== "channel" ? model.thumbnail : ""
            }
            Column {
                visible: model.kind !== "channel"
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
                    text: model.channelName
                          + (model.detail.length > 0 ? "  ·  " + model.detail : "")
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                }
            }

            // ── channel row: circular avatar + name + subscribe button ───────
            Item {
                id: avatarBox
                visible: model.kind === "channel"
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.itemSizeMedium
                height: Theme.itemSizeMedium
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    clip: true
                    color: Theme.rgba(Theme.highlightColor, 0.15)
                    Image {
                        id: chanAvatar
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        source: model.kind === "channel" ? model.thumbnail : ""
                        visible: source !== "" && status === Image.Ready
                    }
                    Label {
                        anchors.centerIn: parent
                        visible: !chanAvatar.visible
                        text: model.title.length > 0 ? model.title.charAt(0) : "?"
                        font.pixelSize: parent.width * 0.4
                        color: Theme.highlightColor
                    }
                }
            }
            Column {
                visible: model.kind === "channel"
                anchors {
                    left: avatarBox.right; leftMargin: Theme.paddingMedium
                    right: subscribeBtn.left; rightMargin: Theme.paddingSmall
                    verticalCenter: parent.verticalCenter
                }
                spacing: 2
                Label {
                    width: parent.width
                    text: model.title
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeSmall
                    color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    visible: model.detail.length > 0
                    text: model.detail
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                }
            }
            IconButton {
                id: subscribeBtn
                visible: model.kind === "channel"
                anchors {
                    right: parent.right; rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                // Already-subscribed channels show a static check instead.
                icon.source: item.subscribed ? "image://theme/icon-m-acknowledge"
                                             : "image://theme/icon-m-add"
                enabled: !item.subscribed
                onClicked: ytSubs.addResolved(model.channelId, model.title, model.thumbnail)
            }
        }

        VerticalScrollDecorator {}
    }
}
