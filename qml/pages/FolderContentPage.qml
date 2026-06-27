import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.Share 1.0
import Nemo.Thumbnailer 1.0
import Nemo.Configuration 1.0
import RooTheater.Media 1.0

Page {
    id: page
    allowedOrientations: Orientation.All

    property string title: ""
    property string kind: "image"     // "image" | "video" | "audio"
    property string folderPath: ""    // used as the persistence key for sort/view prefs
    property var items: []            // [{ filePath, fileName, mimeType, size, modified }, …]
    property QtObject owner            // GalleryPage to notify on delete (keeps its model in sync)

    // Working copy (input minus anything deleted) and the sorted view fed to the grid.
    property var allItems: []
    property var gridItems: []

    // Sorting: field 0=name 1=size 2=date, plus direction. Defaults: Date, Descending.
    property int sortBy: 2
    property bool sortDesc: true

    // Thumbnail size: 0 small … 3 huge → drives how many columns fit. Default: Large.
    property int thumbScale: 2
    readonly property var _thumbTargets: [Theme.itemSizeMedium, Theme.itemSizeLarge,
                                          Theme.itemSizeExtraLarge, Theme.itemSizeHuge]
    readonly property int columns: Math.max(2, Math.floor(width / _thumbTargets[thumbScale]))

    // Multi-selection.
    property bool selectionMode: false
    property var selected: ({})       // filePath -> true
    property int selectedCount: 0
    property int selectionTick: 0     // bumped to refresh delegate highlight bindings

    // Long-press action popup target (one item map, or null when hidden).
    property var actionItem: null

    // Per-folder sort/view persistence. A single dconf value holds a JSON map of
    // "<folderPath>|<kind>" -> { t: thumbScale, s: sortBy, d: sortDesc }.
    readonly property string prefKey: folderPath + "|" + kind
    ConfigurationValue {
        id: sortConfig
        key: "/apps/harbour-rootheater/gallerySort"
        defaultValue: "{}"
    }
    function loadPrefs() {
        var map = {}
        try { map = JSON.parse(sortConfig.value) } catch (e) { map = {} }
        var p = map[prefKey]
        if (p) {
            thumbScale = p.t
            sortBy = p.s
            sortDesc = p.d
        }
        // else keep the property defaults (Large / Date / Descending)
    }
    function savePrefs() {
        var map = {}
        try { map = JSON.parse(sortConfig.value) } catch (e) { map = {} }
        map[prefKey] = { t: thumbScale, s: sortBy, d: sortDesc }
        sortConfig.value = JSON.stringify(map)
    }

    // Audio track numbers (filePath -> int, 0 when unknown), filled async by the
    // TrackIndexer so "Sort by Track" (sortBy 3, audio only) can order an album.
    property var trackByPath: ({})

    function rebuild() {
        var arr = allItems.slice()
        var key = sortBy
        arr.sort(function(a, b) {
            var r = 0
            if (key === 1) {
                r = (a.size || 0) - (b.size || 0)
            } else if (key === 2) {
                r = (a.modified || 0) - (b.modified || 0)
            } else if (key === 3) {
                r = (page.trackByPath[a.filePath] || 0) - (page.trackByPath[b.filePath] || 0)
            } else {
                r = 0
            }
            if (r === 0) {   // tie-break (and name sort) by file name
                var an = (a.fileName || "").toLowerCase()
                var bn = (b.fileName || "").toLowerCase()
                r = an < bn ? -1 : (an > bn ? 1 : 0)
            }
            return page.sortDesc ? -r : r
        })
        gridItems = arr
    }

    function isSelected(fp) {
        selectionTick           // create a binding dependency so highlight refreshes
        return selected[fp] === true
    }
    function toggle(fp) {
        if (selected[fp]) { delete selected[fp]; selectedCount-- }
        else { selected[fp] = true; selectedCount++ }
        selectionTick++
    }
    function enterSelection(fp) {
        selectionMode = true
        if (!selected[fp]) toggle(fp)
    }
    function clearSelection() {
        selected = ({})
        selectedCount = 0
        selectionTick++
    }
    function exitSelection() {
        clearSelection()
        selectionMode = false
    }
    function selectAll() {
        selected = ({})
        selectedCount = 0
        for (var i = 0; i < gridItems.length; ++i) {
            selected[gridItems[i].filePath] = true
            selectedCount++
        }
        selectionTick++
    }
    function selectedPaths() {
        var r = []
        for (var i = 0; i < gridItems.length; ++i) {
            var fp = gridItems[i].filePath
            if (selected[fp]) r.push(fp)
        }
        return r
    }
    function selectedItemObjects() {
        var r = []
        for (var i = 0; i < gridItems.length; ++i)
            if (selected[gridItems[i].filePath]) r.push(gridItems[i])
        return r
    }
    // The share sheet filters methods by the resource mime type, so a generic
    // "*/*" hides app targets (RooTelegram, Bluetooth, …) that declare concrete
    // types. Use the exact shared type when the selection is homogeneous, fall
    // back to the common category ("image/*"), and only then to "*/*".
    function commonMime(itemsArr) {
        if (!itemsArr || itemsArr.length === 0) return "*/*"
        var first = itemsArr[0].mimeType || ""
        var sameExact = itemsArr.every(function(it) { return (it.mimeType || "") === first })
        if (sameExact && first !== "") return first
        var cat = first.indexOf("/") >= 0 ? first.split("/")[0] : ""
        var sameCat = cat !== "" && itemsArr.every(function(it) {
            var m = it.mimeType || ""
            return m.indexOf("/") >= 0 && m.split("/")[0] === cat
        })
        return sameCat ? cat + "/*" : "*/*"
    }
    function shareSelected() {
        var its = selectedItemObjects()
        var paths = its.map(function(it) { return it.filePath })
        shareFiles(paths, commonMime(its))
    }

    // Drop paths from the in-memory model after they've been deleted on disk.
    function removePaths(paths) {
        var set = {}
        for (var i = 0; i < paths.length; ++i) set[paths[i]] = true
        allItems = allItems.filter(function(it) { return !set[it.filePath] })
        for (var j = 0; j < paths.length; ++j) {
            if (selected[paths[j]]) { delete selected[paths[j]]; selectedCount-- }
        }
        selectionTick++
        rebuild()
        // Propagate to the gallery so the folder list / preview stay in sync.
        if (owner && typeof owner.removePaths === "function")
            owner.removePaths(paths)
    }
    function deleteFiles(paths) {
        fileOps.removeList(paths)
        removePaths(paths)
        if (selectionMode && selectedCount === 0)
            selectionMode = false
    }
    // Splice freshly created files (e.g. an image-editor "_edit" copy) into the
    // model so they show up without a full folder rescan.
    function addItems(newItems) {
        if (!newItems || newItems.length === 0) return
        allItems = allItems.concat(newItems)
        rebuild()
        if (owner && typeof owner.addItems === "function")
            owner.addItems(newItems)
    }
    function confirmDelete(paths) {
        if (paths.length === 0) return
        var msg = paths.length === 1 ? qsTr("Deleting")
                                     : qsTr("Deleting %1 items").arg(paths.length)
        remorse.execute(msg, function() { page.deleteFiles(paths) })
    }
    function shareFiles(paths, mime) {
        if (paths.length === 0) return
        var urls = paths.map(function(p) {
            return p.indexOf("file://") === 0 ? p : "file://" + p
        })
        shareAction.mimeType = mime ? mime : "*/*"
        shareAction.resources = urls
        shareAction.trigger()
    }

    // Strip the extension for a friendlier label when a track has no title tag.
    function baseName(fileName) {
        var dot = fileName.lastIndexOf(".")
        return dot > 0 ? fileName.substring(0, dot) : fileName
    }

    function openItem(idx) {
        if (page.kind === "image") {
            pageStack.push(Qt.resolvedUrl("ImageViewerPage.qml"),
                           { items: page.gridItems, index: idx, owner: page })
        } else if (page.kind === "audio") {
            // Tapping a track plays the whole folder as an album, starting here.
            var paths = page.gridItems.map(function(it) { return it.filePath })
            pageStack.push(Qt.resolvedUrl("PlayerPage.qml"),
                           { queue: paths, trackIndex: idx })
        } else {
            // Open the whole folder of videos as a queue so prev/next (in-app and
            // on the cover) skip between clips, starting at the tapped one.
            var vpaths = page.gridItems.map(function(it) { return it.filePath })
            pageStack.push(Qt.resolvedUrl("PlayerPage.qml"),
                           { queue: vpaths, trackIndex: idx })
        }
    }

    Component.onCompleted: {
        loadPrefs()
        allItems = items.slice()
        rebuild()
        // Audio: pull every track's number in the background so "Sort by Track"
        // is ready (and re-sorts once the data lands).
        if (page.kind === "audio") {
            var paths = allItems.map(function(it) { return it.filePath })
            trackIndexer.read(paths)
        }
    }

    TrackIndexer {
        id: trackIndexer
        onReady: {
            page.trackByPath = trackByPath
            page.rebuild()
        }
    }
    FileOperations { id: fileOps }
    ShareAction { id: shareAction }
    RemorsePopup { id: remorse }

    SilicaGridView {
        id: grid
        anchors.fill: parent
        cellWidth: Math.floor(width / page.columns)
        cellHeight: cellWidth
        model: page.gridItems

        header: PageHeader {
            title: page.selectionMode
                   ? qsTr("%1 selected").arg(page.selectedCount)
                   : page.title
        }

        PullDownMenu {
            MenuItem {
                visible: page.selectionMode
                text: qsTr("Cancel selection")
                onClicked: page.exitSelection()
            }
            MenuItem {
                visible: page.selectionMode
                text: page.selectedCount === page.gridItems.length
                      ? qsTr("Deselect all") : qsTr("Select all")
                onClicked: page.selectedCount === page.gridItems.length
                           ? page.clearSelection() : page.selectAll()
            }
            MenuItem {
                visible: page.selectionMode
                enabled: page.selectedCount > 0
                text: qsTr("Share (%1)").arg(page.selectedCount)
                onClicked: page.shareSelected()
            }
            MenuItem {
                visible: page.selectionMode
                enabled: page.selectedCount > 0
                text: qsTr("Delete (%1)").arg(page.selectedCount)
                onClicked: page.confirmDelete(page.selectedPaths())
            }
            MenuItem {
                visible: !page.selectionMode
                text: qsTr("Sorting")
                onClicked: pageStack.push(sortDialog)
            }
        }

        delegate: BackgroundItem {
            id: delegate
            width: grid.cellWidth
            height: grid.cellHeight

            readonly property bool isSel: page.isSelected(modelData.filePath)
            readonly property bool isAudio: page.kind === "audio"
            highlighted: down || isSel

            // Image/video: filesystem thumbnail (with a play badge for video).
            Thumbnail {
                id: thumb
                anchors.fill: parent
                anchors.margins: Theme.paddingSmall / 2
                visible: !delegate.isAudio
                source: !delegate.isAudio ? modelData.filePath : ""
                mimeType: modelData.mimeType
                sourceSize.width: grid.cellWidth
                sourceSize.height: grid.cellHeight
                fillMode: Thumbnail.PreserveAspectCrop
                clip: true
                opacity: delegate.isSel ? 0.6 : 1.0
            }
            Image {
                anchors.centerIn: thumb
                visible: page.kind === "video"
                source: "image://theme/icon-l-play"
            }

            // Audio: embedded cover (lazy, ♪ placeholder) + track title over a
            // gradient — the album track listing the user expects, no play badge.
            Item {
                id: audioCell
                anchors.fill: parent
                anchors.margins: Theme.paddingSmall / 2
                visible: delegate.isAudio
                opacity: delegate.isSel ? 0.6 : 1.0

                Rectangle {
                    anchors.fill: parent
                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)
                    visible: trackCover.status !== Image.Ready
                }
                Label {
                    anchors.centerIn: parent
                    visible: trackCover.status !== Image.Ready
                    text: "♪"
                    color: Theme.secondaryColor
                    font.pixelSize: parent.height * 0.45
                }
                Image {
                    id: trackCover
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    clip: true
                    asynchronous: true
                    cache: false
                    source: delegate.isAudio
                            ? "image://rttrackcover/" + encodeURIComponent(modelData.filePath)
                            : ""
                }
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: titleLabel.height + Theme.paddingSmall
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.75) }
                    }
                }
                Label {
                    id: titleLabel
                    anchors {
                        left: parent.left; right: parent.right; bottom: parent.bottom
                        leftMargin: Theme.paddingSmall; rightMargin: Theme.paddingSmall
                        bottomMargin: Theme.paddingSmall / 2
                    }
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.lightPrimaryColor
                    text: tagReader.title !== "" ? tagReader.title
                                                 : page.baseName(modelData.fileName)
                }
                TagReader {
                    id: tagReader
                    filePath: modelData.filePath
                }
            }

            // Selection check mark.
            Image {
                anchors {
                    top: parent.top; right: parent.right
                    margins: Theme.paddingSmall
                }
                visible: delegate.isSel
                source: "image://theme/icon-s-installed?" + Theme.highlightColor
            }

            onClicked: {
                if (page.selectionMode)
                    page.toggle(modelData.filePath)
                else
                    page.openItem(index)
            }
            onPressAndHold: {
                if (!page.selectionMode)
                    page.actionItem = modelData
            }
        }

        VerticalScrollDecorator {}
    }

    // ── Long-press action sheet (opaque, slides up from the bottom) ─────────
    Item {
        id: actionOverlay
        anchors.fill: parent
        enabled: page.actionItem !== null
        visible: opacity > 0
        opacity: page.actionItem !== null ? 1.0 : 0.0
        Behavior on opacity { FadeAnimation { duration: 150 } }

        // Dim backdrop; tap anywhere outside the sheet to dismiss.
        MouseArea {
            anchors.fill: parent
            onClicked: page.actionItem = null
            Rectangle { anchors.fill: parent; color: Theme.rgba("black", 0.6) }
        }

        Rectangle {
            id: sheet
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            anchors.bottomMargin: page.actionItem !== null ? 0 : -height
            height: sheetCol.height
            color: Theme.rgba(Theme.overlayBackgroundColor, 1.0)
            Behavior on anchors.bottomMargin {
                NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
            }

            // Swallow taps on the sheet itself (so they don't dismiss it).
            MouseArea { anchors.fill: parent }

            Column {
                id: sheetCol
                width: parent.width

                Label {
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    x: Theme.horizontalPageMargin
                    topPadding: Theme.paddingLarge
                    bottomPadding: Theme.paddingMedium
                    truncationMode: TruncationMode.Fade
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeSmall
                    text: page.actionItem ? page.actionItem.fileName : ""
                }

                Separator {
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: Theme.secondaryColor
                }

                Repeater {
                    model: page.kind === "audio"
                        ? [
                            { label: qsTr("Select"),    act: "select", icon: "icon-m-acknowledge" },
                            { label: qsTr("View tags"), act: "tags",   icon: "icon-m-about" },
                            { label: qsTr("Share"),     act: "share",  icon: "icon-m-share" },
                            { label: qsTr("Delete"),    act: "delete", icon: "icon-m-delete" }
                          ]
                        : [
                            { label: qsTr("Select"), act: "select", icon: "icon-m-acknowledge" },
                            { label: qsTr("Share"),  act: "share",  icon: "icon-m-share" },
                            { label: qsTr("Delete"), act: "delete", icon: "icon-m-delete" }
                          ]
                    delegate: BackgroundItem {
                        width: sheetCol.width
                        Row {
                            x: Theme.horizontalPageMargin
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.paddingLarge
                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                source: "image://theme/" + modelData.icon + "?"
                                        + (highlighted ? Theme.highlightColor : Theme.primaryColor)
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                color: highlighted ? Theme.highlightColor : Theme.primaryColor
                            }
                        }
                        onClicked: {
                            var it = page.actionItem
                            page.actionItem = null
                            if (!it) return
                            if (modelData.act === "select")
                                page.enterSelection(it.filePath)
                            else if (modelData.act === "tags")
                                pageStack.push(Qt.resolvedUrl("TagsPage.qml"),
                                               { filePath: it.filePath, fileName: it.fileName })
                            else if (modelData.act === "share")
                                page.shareFiles([it.filePath], it.mimeType)
                            else
                                page.confirmDelete([it.filePath])
                        }
                    }
                }
            }
        }
    }

    // ── Sorting / view options dialog ───────────────────────────────────────
    Component {
        id: sortDialog
        Dialog {
            id: dlg
            property int thumbScaleLocal: page.thumbScale
            property int sortByLocal: page.sortBy
            property bool sortDescLocal: page.sortDesc

            onAccepted: {
                page.thumbScale = thumbScaleLocal
                page.sortBy = sortByLocal
                page.sortDesc = sortDescLocal
                page.savePrefs()
                page.rebuild()
            }

            // Inline segmented selector: a labelled row of toggle buttons.
            // model.value carries the index; the highlighted one is `current`.
            Column {
                width: parent.width
                spacing: Theme.paddingLarge

                DialogHeader { title: qsTr("Sorting") }

                SegmentSelector {
                    width: parent.width
                    title: qsTr("Thumbnails")
                    options: [qsTr("Small"), qsTr("Medium"), qsTr("Large"), qsTr("Huge")]
                    current: dlg.thumbScaleLocal
                    onSelected: dlg.thumbScaleLocal = index
                }
                SegmentSelector {
                    width: parent.width
                    title: qsTr("Sort by")
                    // "Track" (index 3) sorts by the metadata track number; audio only.
                    options: page.kind === "audio"
                             ? [qsTr("Name"), qsTr("Size"), qsTr("Date"), qsTr("Track")]
                             : [qsTr("Name"), qsTr("Size"), qsTr("Date")]
                    current: dlg.sortByLocal
                    onSelected: dlg.sortByLocal = index
                }
                SegmentSelector {
                    width: parent.width
                    title: qsTr("Order")
                    options: [qsTr("Ascending"), qsTr("Descending")]
                    current: dlg.sortDescLocal ? 1 : 0
                    onSelected: dlg.sortDescLocal = (index === 1)
                }
            }
        }
    }
}
