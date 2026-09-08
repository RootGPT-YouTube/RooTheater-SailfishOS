import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import RooTheater.Media 1.0

Page {
    id: page
    allowedOrientations: Orientation.All

    // Discovered at startup: internal / Android / SD-card roots for the gallery.
    StorageRoots { id: storage }

    // ── Soft permission gates (Options → Permissions; default granted) ───────
    // Honoured BEFORE using the resource: with internet off no network entry is
    // reachable and no request leaves the app; a storage turned off is hidden.
    ConfigurationValue {
        id: permInternet
        key: "/apps/harbour-rootheater/perm/internet"
        defaultValue: true
    }
    ConfigurationValue {
        id: permAndroid
        key: "/apps/harbour-rootheater/perm/android"
        defaultValue: true
    }
    ConfigurationValue {
        id: permSdcard
        key: "/apps/harbour-rootheater/perm/sdcard"
        defaultValue: true
    }
    readonly property bool internetAllowed:
        permInternet.value !== false && permInternet.value !== "false"
    readonly property bool androidAllowed:
        permAndroid.value !== false && permAndroid.value !== "false"
    readonly property bool sdcardAllowed:
        permSdcard.value !== false && permSdcard.value !== "false"

    // ── YouTube RSS: unseen badges + multi-select on the Home grid ────────────
    property bool ytSelectMode: false
    property var ytSelected: ({})       // channelId -> true
    property int ytSelectedCount: 0
    property int ytSelectionTick: 0     // bumped to refresh delegate highlights

    function ytIsSelected(id) { ytSelectionTick; return ytSelected[id] === true }
    function ytToggle(id) {
        if (ytSelected[id]) { delete ytSelected[id]; ytSelectedCount-- }
        else { ytSelected[id] = true; ytSelectedCount++ }
        ytSelectionTick++
        if (ytSelectedCount === 0) page.ytSelectMode = false
    }
    function ytEnterSelect(id) { page.ytSelectMode = true; if (!ytSelected[id]) ytToggle(id) }
    function ytClearSelection() {
        ytSelected = ({}); ytSelectedCount = 0; ytSelectionTick++; page.ytSelectMode = false
    }
    function ytSelectedIds() {
        var r = []
        for (var k in ytSelected) if (ytSelected[k]) r.push(k)
        return r
    }

    // Per-channel long-press menu (custom centred popup; the Silica ContextMenu
    // misbehaves inside a grid-in-a-Flickable).
    property string ytMenuChannelId: ""
    property string ytMenuChannelName: ""
    function openChanMenu(id, name) {
        page.ytMenuChannelId = id
        page.ytMenuChannelName = name
        chanMenu.show()
    }

    // Refresh the "unseen" counts when the Home page is shown (fetches the
    // channels' RSS feeds → gated by the internet permission).
    onStatusChanged: if (status === PageStatus.Active && page.internetAllowed)
                         ytSubs.refreshUnseen()
    // The startup pass is also where an outage becomes visible: when it ends with
    // every channel unserved, both sources are down (see YtChannelFetch) and the
    // lists on screen are whatever was saved. Say it plainly, once per run — the
    // user asked to be told rather than left to guess from an empty channel.
    property bool ytOutageTold: false
    Connections {
        target: ytSubs
        onFillFinished: if (page.internetAllowed) ytSubs.refreshUnseen()   // after an import completes
        onFeedsRefreshed: {
            if (!page.ytOutageTold && ytSubs.refreshFailed > 0 && ytSubs.refreshOk === 0) {
                page.ytOutageTold = true
                ytOutage.visible = true
            }
        }
    }

    RemorsePopup { id: ytRemorse }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                text: qsTr("Options")
                onClicked: pageStack.push(Qt.resolvedUrl("OptionsPage.qml"))
            }
            MenuItem {
                visible: page.internetAllowed
                text: qsTr("YouTube")
                onClicked: pageStack.push(Qt.resolvedUrl("YouTubePage.qml"))
            }
            MenuItem {
                visible: page.internetAllowed
                text: qsTr("Open network stream…")
                onClicked: page.openUrlDialog()
            }
        }

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: "RooTheater"
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                visible: page.internetAllowed
                color: Theme.secondaryHighlightColor
                text: qsTr("Pull down to open a network stream.")
            }

            // Gallery: the storage categories (filtered by the storage gates).
            // Each opens a folder-grouped grid of the media found under that root.
            Repeater {
                model: {
                    var m = [ { title: qsTr("Internal memory"),
                                icon: "image://theme/icon-m-device",
                                root: storage.internalRoot } ]
                    if (page.androidAllowed)
                        m.push({ title: qsTr("Android storage"),
                                 icon: "image://theme/icon-m-other",
                                 root: storage.androidRoot })
                    if (page.sdcardAllowed)
                        m.push({ title: qsTr("SD card"),
                                 icon: "image://theme/icon-m-sd-card",
                                 root: storage.sdcardRoots.length > 0
                                       ? storage.sdcardRoots[0] : "" })
                    return m
                }
                delegate: BackgroundItem {
                    width: page.width
                    onClicked: pageStack.push(Qt.resolvedUrl("GalleryPage.qml"),
                                              { rootPath: modelData.root, title: modelData.title })
                    Row {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        height: parent.height
                        spacing: Theme.paddingLarge
                        Image {
                            anchors.verticalCenter: parent.verticalCenter
                            source: modelData.icon
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.title
                            color: highlighted ? Theme.highlightColor : Theme.primaryColor
                        }
                    }
                }
            }

            // YouTube RSS: the channels we follow (see YouTubePage). Medium
            // avatars in a grid, channel name + unseen badge; tap opens the
            // channel's recent videos, long-press gives per-channel actions and a
            // multi-select mode. Hidden until there's at least one subscription.
            Item {
                width: parent.width
                height: Theme.itemSizeSmall
                visible: ytSubs.count > 0 && page.internetAllowed

                // While the startup pass runs, the header carries its progress:
                // that pass fetches every channel's feed — unseen badges AND the
                // saved list each channel falls back on when YouTube stops
                // serving its feeds — so it is worth being able to watch it end.
                SectionHeader {
                    anchors.verticalCenter: parent.verticalCenter
                    text: page.ytSelectMode
                          ? qsTr("%1 selected").arg(page.ytSelectedCount)
                          : ytSubs.refreshing
                            ? qsTr("YouTube RSS — %1%").arg(Math.round(ytSubs.refreshProgress * 100))
                            : qsTr("YouTube RSS")
                }
                // Selection-mode actions: mark selected as seen / delete selected.
                Row {
                    anchors {
                        right: parent.right; rightMargin: Theme.horizontalPageMargin
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: Theme.paddingMedium
                    visible: page.ytSelectMode
                    IconButton {
                        icon.source: "image://theme/icon-m-acknowledge"
                        enabled: page.ytSelectedCount > 0
                        onClicked: { ytSubs.markSeenList(page.ytSelectedIds()); page.ytClearSelection() }
                    }
                    IconButton {
                        icon.source: "image://theme/icon-m-delete"
                        enabled: page.ytSelectedCount > 0
                        onClicked: {
                            var ids = page.ytSelectedIds()
                            page.ytClearSelection()
                            ytRemorse.execute(qsTr("Deleting %1 channel(s)").arg(ids.length),
                                              function() { ytSubs.removeList(ids) })
                        }
                    }
                    IconButton {
                        icon.source: "image://theme/icon-m-cancel"
                        onClicked: page.ytClearSelection()
                    }
                }
            }
            Grid {
                id: ytGrid
                visible: ytSubs.count > 0 && page.internetAllowed
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                // `cell` is the *target* tile width; the column count rounds to
                // the nearest fit (not floor) so a screen that would leave a wide
                // dead band on the right — e.g. the C2, ~4.5 cells wide — gets an
                // extra column (5) instead of an ugly gap, while a screen that
                // divides cleanly (X10III ≈ 4) stays put. Bigger screens naturally
                // get 5+ columns. `cellW` is the actual per-column width; tiles
                // (avatar + height) scale to it, so rows always fill edge-to-edge
                // and cellW stays within ~±10% of `cell`.
                readonly property real cell: Theme.itemSizeExtraLarge
                columns: Math.max(1, Math.round(width / cell))
                readonly property real cellW: width / columns
                Repeater {
                    model: ytSubs
                    delegate: BackgroundItem {
                        id: chanItem
                        width: ytGrid.cellW
                        height: ytGrid.cellW + Theme.fontSizeExtraSmall * 2.6
                        highlighted: down || page.ytIsSelected(model.channelId)
                        onClicked: {
                            if (page.ytSelectMode)
                                page.ytToggle(model.channelId)
                            else
                                pageStack.push(Qt.resolvedUrl("YtChannelPage.qml"),
                                               { channelId: model.channelId,
                                                 channelName: model.name })
                        }
                        onPressAndHold: {
                            if (page.ytSelectMode)
                                page.ytToggle(model.channelId)
                            else
                                page.openChanMenu(model.channelId, model.name)
                        }

                        Column {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width - Theme.paddingSmall
                            spacing: Theme.paddingSmall
                            // Circular avatar (channel og:image); initial placeholder.
                            Item {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: ytGrid.cellW - 2 * Theme.paddingMedium
                                height: width
                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    clip: true
                                    color: Theme.rgba(Theme.highlightColor, 0.15)
                                    opacity: page.ytIsSelected(model.channelId) ? 0.4 : 1.0
                                    Image {
                                        id: avatarImg
                                        anchors.fill: parent
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        source: model.avatar
                                        visible: model.avatar.length > 0 && status === Image.Ready
                                    }
                                    Label {
                                        anchors.centerIn: parent
                                        visible: model.avatar.length === 0
                                                 || avatarImg.status === Image.Error
                                                 || avatarImg.status === Image.Loading
                                        text: model.name.length > 0 ? model.name.charAt(0) : "?"
                                        font.pixelSize: parent.width * 0.4
                                        color: Theme.highlightColor
                                    }
                                }
                                // Selection check overlay.
                                Image {
                                    anchors.centerIn: parent
                                    source: "image://theme/icon-l-acknowledge?" + Theme.highlightColor
                                    visible: page.ytIsSelected(model.channelId)
                                }
                                // Unseen-videos badge (top-right).
                                Rectangle {
                                    anchors { right: parent.right; top: parent.top }
                                    visible: !page.ytSelectMode && model.unseen > 0
                                    width: Math.max(Theme.fontSizeSmall * 1.6, badgeLabel.width + Theme.paddingSmall)
                                    height: Theme.fontSizeSmall * 1.6
                                    radius: height / 2
                                    color: Theme.highlightColor
                                    Label {
                                        id: badgeLabel
                                        anchors.centerIn: parent
                                        text: model.unseen > 99 ? "99+" : model.unseen
                                        font.pixelSize: Theme.fontSizeExtraSmall
                                        color: Theme.highlightDimmerColor
                                    }
                                }
                            }
                            Label {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: model.name
                                maximumLineCount: 2
                                wrapMode: Text.Wrap
                                truncationMode: TruncationMode.Elide
                                font.pixelSize: Theme.fontSizeExtraSmall
                                color: chanItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                            }
                        }
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }

    // ── Per-channel long-press menu: centred, content-width, themed ───────────
    Item {
        id: chanMenu
        anchors.fill: parent
        visible: false
        function show() { visible = true }
        function hide() { visible = false }

        Rectangle {           // dim backdrop; tap outside closes
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.6)
            MouseArea { anchors.fill: parent; onClicked: chanMenu.hide() }
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.round(page.width * 0.72)
            height: menuCol.height
            radius: Theme.paddingMedium
            color: Theme.overlayBackgroundColor

            Column {
                id: menuCol
                width: parent.width

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    topPadding: Theme.paddingLarge
                    bottomPadding: Theme.paddingSmall
                    text: page.ytMenuChannelName
                    truncationMode: TruncationMode.Fade
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeSmall
                }
                Repeater {
                    model: [
                        { label: qsTr("Mark channel as seen"), action: "seen" },
                        { label: qsTr("Mark all as seen"),     action: "seenAll" },
                        { label: qsTr("Select channels"),      action: "select" },
                        { label: qsTr("Delete channel"),       action: "delete" }
                    ]
                    delegate: BackgroundItem {
                        width: menuCol.width
                        onClicked: {
                            chanMenu.hide()
                            var id = page.ytMenuChannelId
                            if (modelData.action === "seen")
                                ytSubs.markSeen(id)
                            else if (modelData.action === "seenAll")
                                ytSubs.markAllSeen()
                            else if (modelData.action === "select")
                                page.ytEnterSelect(id)
                            else if (modelData.action === "delete")
                                ytRemorse.execute(qsTr("Deleting channel"),
                                                  function() { ytSubs.remove(id) })
                        }
                        Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * Theme.horizontalPageMargin
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            truncationMode: TruncationMode.Fade
                            color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                        }
                    }
                }
                Item { width: 1; height: Theme.paddingMedium }
            }
        }
    }

    // ── "YouTube is not answering" notice ─────────────────────────────────────
    // Same centred-panel shape as the channel menu above (the Silica Dialog would
    // push a page onto the stack for a message that needs one tap to dismiss).
    Item {
        id: ytOutage
        anchors.fill: parent
        visible: false

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.6)
            MouseArea { anchors.fill: parent; onClicked: ytOutage.visible = false }
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.round(page.width * 0.82)
            height: outageCol.height
            radius: Theme.paddingMedium
            color: Theme.overlayBackgroundColor

            Column {
                id: outageCol
                width: parent.width
                spacing: Theme.paddingMedium

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    topPadding: Theme.paddingLarge
                    text: qsTr("YouTube is not answering")
                    wrapMode: Text.WordWrap
                    color: Theme.highlightColor
                }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    text: qsTr("None of the %n channel(s) could be updated: the trouble is on YouTube's side, not with your connection. The saved lists are still shown and their videos still play. Try again later.", "", ytSubs.refreshFailed)
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryHighlightColor
                }
                BackgroundItem {
                    width: outageCol.width
                    onClicked: ytOutage.visible = false
                    Label {
                        anchors.centerIn: parent
                        text: qsTr("OK")
                        color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                    }
                }
            }
        }
    }

    function play(source) {
        if (!source || source === "")
            return
        pageStack.push(Qt.resolvedUrl("PlayerPage.qml"), { source: source })
    }

    function openUrlDialog() {
        var dialog = pageStack.push(urlDialog)
        dialog.accepted.connect(function() {
            page.play(dialog.url)
        })
    }

    Component {
        id: urlDialog
        Dialog {
            property alias url: urlField.text
            canAccept: urlField.text.length > 0

            Column {
                width: parent.width
                DialogHeader {
                    title: qsTr("Network stream")
                }
                TextField {
                    id: urlField
                    width: parent.width
                    inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                    placeholderText: qsTr("URL (http, https, rtsp, rtmp…)")
                    label: qsTr("Stream URL")
                    EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                    EnterKey.onClicked: parent.parent.accept()
                }
            }
        }
    }
}
