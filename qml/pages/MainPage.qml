import QtQuick 2.0
import Sailfish.Silica 1.0
import RooTheater.Media 1.0

Page {
    id: page
    allowedOrientations: Orientation.All

    // Discovered at startup: internal / Android / SD-card roots for the gallery.
    StorageRoots { id: storage }

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

    // Refresh the "unseen" counts when the Home page is shown.
    onStatusChanged: if (status === PageStatus.Active) ytSubs.refreshUnseen()
    Connections {
        target: ytSubs
        onFillFinished: ytSubs.refreshUnseen()   // after an import completes
    }

    RemorsePopup { id: ytRemorse }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                text: qsTr("About")
                onClicked: pageStack.push(Qt.resolvedUrl("AboutPage.qml"))
            }
            MenuItem {
                text: qsTr("YouTube")
                onClicked: pageStack.push(Qt.resolvedUrl("YouTubePage.qml"))
            }
            MenuItem {
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
                color: Theme.secondaryHighlightColor
                text: qsTr("Pull down to open a network stream.")
            }

            // Gallery: three storage categories. Each opens a folder-grouped grid
            // of the images and videos found under that storage root.
            Repeater {
                model: [
                    { title: qsTr("Internal memory"), icon: "image://theme/icon-m-device",
                      root: storage.internalRoot },
                    { title: qsTr("Android storage"), icon: "image://theme/icon-m-other",
                      root: storage.androidRoot },
                    { title: qsTr("SD card"), icon: "image://theme/icon-m-sd-card",
                      root: storage.sdcardRoots.length > 0 ? storage.sdcardRoots[0] : "" }
                ]
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
                visible: ytSubs.count > 0

                SectionHeader {
                    anchors.verticalCenter: parent.verticalCenter
                    text: page.ytSelectMode
                          ? qsTr("%1 selected").arg(page.ytSelectedCount)
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
                visible: ytSubs.count > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                readonly property real cell: Theme.itemSizeExtraLarge
                columns: Math.max(1, Math.floor(width / cell))
                Repeater {
                    model: ytSubs
                    delegate: BackgroundItem {
                        id: chanItem
                        width: ytGrid.cell
                        height: ytGrid.cell + Theme.fontSizeExtraSmall * 2.6
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
                                width: ytGrid.cell - 2 * Theme.paddingMedium
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
