import QtQuick 2.0

// Reusable pinch-to-zoom surface shared by the image viewer and the video player.
// Two-finger pinch scales the wrapped content; once zoomed a one-finger drag pans
// it (clamped so the content can't be dragged off-screen); a double tap animates
// back to the original 1× size. A single tap emits clicked() (used to toggle the
// surrounding chrome/controls). `zoomed` lets the host disable an enclosing
// flickable (e.g. the viewer's swipe-between-images ListView) while magnified.
Item {
    id: root

    property real minZoom: 1.0
    property real maxZoom: 6.0
    readonly property bool zoomed: zoomItem.scale > 1.001

    signal clicked()

    // Content placed between PinchZoom { … } lands inside the scaled wrapper.
    default property alias contentData: zoomItem.data

    function reset() {
        resetAnim.restart()
    }

    // Keep the (scaled) content within the view bounds; centred when it is
    // smaller than the view in a given axis.
    function clamp() {
        var maxX = Math.max(0, (root.width * zoomItem.scale - root.width) / 2)
        var maxY = Math.max(0, (root.height * zoomItem.scale - root.height) / 2)
        zoomItem.x = Math.max(-maxX, Math.min(maxX, zoomItem.x))
        zoomItem.y = Math.max(-maxY, Math.min(maxY, zoomItem.y))
    }

    Item {
        id: zoomItem
        width: root.width
        height: root.height
        transformOrigin: Item.Center
    }

    PinchArea {
        anchors.fill: parent
        pinch.target: zoomItem
        pinch.minimumScale: root.minZoom
        pinch.maximumScale: root.maxZoom
        pinch.dragAxis: Pinch.XAndYAxis
        onPinchUpdated: root.clamp()
        onPinchFinished: root.clamp()

        MouseArea {
            anchors.fill: parent
            drag.target: root.zoomed ? zoomItem : undefined
            drag.filterChildren: true
            onClicked: root.clicked()
            onDoubleClicked: root.reset()
            onPositionChanged: if (root.zoomed) root.clamp()
        }
    }

    ParallelAnimation {
        id: resetAnim
        NumberAnimation { target: zoomItem; property: "scale"; to: 1.0; duration: 200; easing.type: Easing.InOutQuad }
        NumberAnimation { target: zoomItem; property: "x"; to: 0; duration: 200; easing.type: Easing.InOutQuad }
        NumberAnimation { target: zoomItem; property: "y"; to: 0; duration: 200; easing.type: Easing.InOutQuad }
    }
}
