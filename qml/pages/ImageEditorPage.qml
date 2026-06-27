import QtQuick 2.6
import Sailfish.Silica 1.0
import RooTheater.Media 1.0

// Non-destructive image editor: interactive crop (free edge/corner handles) plus
// freehand / circle / arrow annotations in selectable colours and stroke widths.
// The preview is fitted to the screen; all edits are stored as resolution-
// independent vectors (normalised to the displayed image) and re-rendered at full
// resolution by the C++ ImageEditor on save, which writes a new "_edit" copy.
Page {
    id: page
    allowedOrientations: Orientation.All

    property string filePath: ""
    // Emitted with the saved file's path so the caller can splice it into its model.
    signal edited(string newPath)

    // ── Editing state ────────────────────────────────────────────────────────
    property string tool: "draw"          // "crop" | "draw"
    property string shape: "free"         // "free" | "circle" | "arrow"
    property string penColor: "#ff3b30"
    property real penWidth: 8              // stroke width, in displayed pixels

    readonly property var palette: ["#ff3b30", "#ff9500", "#ffcc00", "#34c759",
                                    "#007aff", "#af52de", "#ffffff", "#000000"]

    // Display rotation in degrees (0/90/180/270), cycled by the rotate button and
    // baked into the saved copy. Crop + annotations live in this rotated frame.
    property int rotation: 0
    readonly property bool swap: rotation % 180 !== 0

    // Crop rectangle, normalised [0..1] over the displayed image.
    property real cropL: 0
    property real cropT: 0
    property real cropR: 1
    property real cropB: 1

    // Committed annotations + the one currently being drawn. Each annotation:
    //   { type, color, width (fraction of image width), points: [ {x,y} … ] }
    property var annotations: []
    property var current: null

    property bool saving: false

    ImageEditor {
        id: editor
        onError: { saving = false; errorLabel.text = message }
    }

    function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

    function resetAll() {
        annotations = []
        current = null
        cropL = 0; cropT = 0; cropR = 1; cropB = 1
        rotation = 0
        canvas.requestPaint()
    }

    // Turn the image 90° clockwise, carrying the crop window and any existing
    // annotations along so they stay anchored to the same image content. A point
    // (x, y) in the old frame maps to (1 - y, x) in the rotated one.
    function rotate90() {
        var na = []
        for (var i = 0; i < annotations.length; ++i) {
            var a = annotations[i]
            var np = []
            for (var j = 0; j < a.points.length; ++j)
                np.push({ x: 1 - a.points[j].y, y: a.points[j].x })
            na.push({ type: a.type, color: a.color, width: a.width, points: np })
        }
        annotations = na
        var nl = 1 - cropB, nr = 1 - cropT, nt = cropL, nb = cropR
        cropL = nl; cropT = nt; cropR = nr; cropB = nb
        rotation = (rotation + 90) % 360
        canvas.requestPaint()
    }
    function undo() {
        if (annotations.length === 0) return
        var arr = annotations.slice()
        arr.pop()
        annotations = arr
        canvas.requestPaint()
    }
    function doSave() {
        if (saving || srcImage.status !== Image.Ready) return
        saving = true
        errorLabel.text = ""
        // Defer so the busy indicator paints before the (blocking) full-res render.
        saveTimer.start()
    }
    Timer {
        id: saveTimer
        interval: 16
        onTriggered: {
            var crop = Qt.rect(page.cropL, page.cropT,
                               page.cropR - page.cropL, page.cropB - page.cropT)
            var p = editor.save(page.filePath, crop, page.annotations, page.rotation)
            page.saving = false
            if (p && p.length > 0) {
                page.edited(p)
                pageStack.pop()
            }
        }
    }

    onAnnotationsChanged: canvas.requestPaint()

    SilicaFlickable {
        anchors.fill: parent
        // Crop/draw gestures own the touch on the stage, so don't let the
        // flickable steal drags.
        interactive: false

        PullDownMenu {
            MenuItem {
                text: qsTr("Save a copy")
                enabled: !page.saving
                onClicked: page.doSave()
            }
            MenuItem {
                text: qsTr("Undo")
                enabled: page.annotations.length > 0
                onClicked: page.undo()
            }
            MenuItem {
                text: qsTr("Reset")
                onClicked: page.resetAll()
            }
        }

        Rectangle { anchors.fill: parent; color: "black" }

        // ── Fitted image + edit overlays ─────────────────────────────────────
        Item {
            id: stage
            // topBar / toolbar live on the page (not in this flickable), so reserve
            // room for them via margins rather than cross-parent anchors.
            anchors {
                top: parent.top; topMargin: topBar.height
                left: parent.left; right: parent.right
                bottom: parent.bottom; bottomMargin: toolbar.height
            }

            Image {
                id: srcImage
                anchors.centerIn: parent
                // Swap the fit box on 90°/270° turns so the rotated image still
                // fits the stage; `area` then overlays its on-screen rectangle.
                width: page.swap ? stage.height : stage.width
                height: page.swap ? stage.width : stage.height
                rotation: page.rotation
                source: page.filePath
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                autoTransform: true
                cache: false
                // Decode at a generous size so the preview stays crisp.
                sourceSize.width: stage.width * 2
                sourceSize.height: stage.height * 2
            }

            BusyIndicator {
                anchors.centerIn: parent
                size: BusyIndicatorSize.Large
                running: srcImage.status === Image.Loading || page.saving
                visible: running
            }

            // Exactly the painted image rectangle; all editing happens in here so
            // child coordinates map 1:1 onto the image.
            Item {
                id: area
                // The painted rectangle as it appears on screen: width/height swap
                // with the image once it is turned 90°/270°.
                width: page.swap ? srcImage.paintedHeight : srcImage.paintedWidth
                height: page.swap ? srcImage.paintedWidth : srcImage.paintedHeight
                x: (stage.width - width) / 2
                y: (stage.height - height) / 2
                visible: srcImage.status === Image.Ready

                readonly property real aw: width
                readonly property real ah: height

                // Annotation layer.
                Canvas {
                    id: canvas
                    anchors.fill: parent
                    renderStrategy: Canvas.Cooperative

                    function ellipsePath(ctx, cx, cy, rx, ry) {
                        var k = 0.5522847498
                        ctx.beginPath()
                        ctx.moveTo(cx, cy - ry)
                        ctx.bezierCurveTo(cx + rx * k, cy - ry, cx + rx, cy - ry * k, cx + rx, cy)
                        ctx.bezierCurveTo(cx + rx, cy + ry * k, cx + rx * k, cy + ry, cx, cy + ry)
                        ctx.bezierCurveTo(cx - rx * k, cy + ry, cx - rx, cy + ry * k, cx - rx, cy)
                        ctx.bezierCurveTo(cx - rx, cy - ry * k, cx - rx * k, cy - ry, cx, cy - ry)
                    }

                    function drawAnno(ctx, a) {
                        if (!a || !a.points || a.points.length === 0) return
                        var P = a.points
                        ctx.strokeStyle = a.color
                        ctx.lineWidth = Math.max(1, a.width * area.aw)
                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"
                        var x0 = P[0].x * area.aw, y0 = P[0].y * area.ah
                        if (a.type === "free") {
                            ctx.beginPath()
                            ctx.moveTo(x0, y0)
                            if (P.length === 1) {
                                ctx.lineTo(x0 + 0.1, y0 + 0.1)   // a tap = a dot
                            } else {
                                for (var i = 1; i < P.length; ++i)
                                    ctx.lineTo(P[i].x * area.aw, P[i].y * area.ah)
                            }
                            ctx.stroke()
                        } else if (P.length >= 2) {
                            var x1 = P[1].x * area.aw, y1 = P[1].y * area.ah
                            if (a.type === "circle") {
                                ellipsePath(ctx, (x0 + x1) / 2, (y0 + y1) / 2,
                                            Math.abs(x1 - x0) / 2, Math.abs(y1 - y0) / 2)
                                ctx.stroke()
                            } else if (a.type === "arrow") {
                                ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); ctx.stroke()
                                var head = Math.max(ctx.lineWidth * 4, area.aw * 0.018)
                                var ang = Math.atan2(y1 - y0, x1 - x0), sp = Math.PI / 7
                                ctx.beginPath()
                                ctx.moveTo(x1, y1)
                                ctx.lineTo(x1 - head * Math.cos(ang - sp), y1 - head * Math.sin(ang - sp))
                                ctx.moveTo(x1, y1)
                                ctx.lineTo(x1 - head * Math.cos(ang + sp), y1 - head * Math.sin(ang + sp))
                                ctx.stroke()
                            }
                        }
                    }

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        for (var i = 0; i < page.annotations.length; ++i)
                            drawAnno(ctx, page.annotations[i])
                        drawAnno(ctx, page.current)
                    }
                }

                // Drawing input.
                MouseArea {
                    id: drawArea
                    anchors.fill: parent
                    enabled: page.tool === "draw"
                    preventStealing: true

                    function pt(x, y) {
                        return { x: page.clamp(x / area.aw, 0, 1),
                                 y: page.clamp(y / area.ah, 0, 1) }
                    }

                    onPressed: {
                        var p0 = pt(mouse.x, mouse.y)
                        var a = { type: page.shape, color: page.penColor,
                                  width: page.penWidth / area.aw, points: [p0] }
                        if (page.shape !== "free")
                            a.points.push({ x: p0.x, y: p0.y })   // start == current
                        page.current = a
                        canvas.requestPaint()
                    }
                    onPositionChanged: {
                        if (!page.current) return
                        var p1 = pt(mouse.x, mouse.y)
                        if (page.shape === "free")
                            page.current.points.push(p1)
                        else
                            page.current.points[1] = p1
                        canvas.requestPaint()
                    }
                    onReleased: {
                        if (!page.current) return
                        page.annotations = page.annotations.concat([page.current])
                        page.current = null
                    }
                }

                // ── Crop overlay (dim outside + frame + handles) ──────────────
                readonly property real clx: page.cropL * aw
                readonly property real ctx2: page.cropT * ah
                readonly property real crx: page.cropR * aw
                readonly property real cbx: page.cropB * ah

                Item {
                    anchors.fill: parent
                    visible: page.tool === "crop"

                    // Four dim panels around the crop window.
                    Rectangle { color: "#a6000000"
                        x: 0; y: 0; width: area.aw; height: area.ctx2 }
                    Rectangle { color: "#a6000000"
                        x: 0; y: area.cbx; width: area.aw; height: area.ah - area.cbx }
                    Rectangle { color: "#a6000000"
                        x: 0; y: area.ctx2; width: area.clx; height: area.cbx - area.ctx2 }
                    Rectangle { color: "#a6000000"
                        x: area.crx; y: area.ctx2; width: area.aw - area.crx; height: area.cbx - area.ctx2 }

                    // Frame.
                    Rectangle {
                        x: area.clx; y: area.ctx2
                        width: area.crx - area.clx; height: area.cbx - area.ctx2
                        color: "transparent"
                        border.color: "white"; border.width: 2
                    }

                    // Eight handles (4 corners + 4 edge midpoints).
                    Repeater {
                        model: [["tl", 0, 0], ["tr", 1, 0], ["bl", 0, 1], ["br", 1, 1],
                                ["l", 0, 0.5], ["r", 1, 0.5], ["t", 0.5, 0], ["b", 0.5, 1]]
                        Rectangle {
                            width: Theme.iconSizeSmall; height: width; radius: width / 2
                            color: "white"; border.color: "#333"; border.width: 1
                            x: area.clx + modelData[1] * (area.crx - area.clx) - width / 2
                            y: area.ctx2 + modelData[2] * (area.cbx - area.ctx2) - height / 2
                        }
                    }
                }

                // Crop input: a single hit-tested MouseArea drives all handles.
                MouseArea {
                    anchors.fill: parent
                    enabled: page.tool === "crop"
                    preventStealing: true
                    property string grab: ""
                    property real lastX: 0
                    property real lastY: 0

                    function near(mx, my, px, py, t) {
                        return Math.abs(mx - px) < t && Math.abs(my - py) < t
                    }

                    onPressed: {
                        var t = Theme.itemSizeExtraSmall
                        var l = area.clx, r = area.crx, tp = area.ctx2, b = area.cbx
                        lastX = mouse.x; lastY = mouse.y
                        if (near(mouse.x, mouse.y, l, tp, t)) grab = "tl"
                        else if (near(mouse.x, mouse.y, r, tp, t)) grab = "tr"
                        else if (near(mouse.x, mouse.y, l, b, t)) grab = "bl"
                        else if (near(mouse.x, mouse.y, r, b, t)) grab = "br"
                        else if (Math.abs(mouse.x - l) < t && mouse.y > tp && mouse.y < b) grab = "l"
                        else if (Math.abs(mouse.x - r) < t && mouse.y > tp && mouse.y < b) grab = "r"
                        else if (Math.abs(mouse.y - tp) < t && mouse.x > l && mouse.x < r) grab = "t"
                        else if (Math.abs(mouse.y - b) < t && mouse.x > l && mouse.x < r) grab = "b"
                        else if (mouse.x > l && mouse.x < r && mouse.y > tp && mouse.y < b) grab = "move"
                        else grab = ""
                    }
                    onPositionChanged: {
                        if (grab === "") return
                        var nx = page.clamp(mouse.x / area.aw, 0, 1)
                        var ny = page.clamp(mouse.y / area.ah, 0, 1)
                        var m = 0.05
                        if (grab === "tl") { page.cropL = Math.min(nx, page.cropR - m); page.cropT = Math.min(ny, page.cropB - m) }
                        else if (grab === "tr") { page.cropR = Math.max(nx, page.cropL + m); page.cropT = Math.min(ny, page.cropB - m) }
                        else if (grab === "bl") { page.cropL = Math.min(nx, page.cropR - m); page.cropB = Math.max(ny, page.cropT + m) }
                        else if (grab === "br") { page.cropR = Math.max(nx, page.cropL + m); page.cropB = Math.max(ny, page.cropT + m) }
                        else if (grab === "l") page.cropL = Math.min(nx, page.cropR - m)
                        else if (grab === "r") page.cropR = Math.max(nx, page.cropL + m)
                        else if (grab === "t") page.cropT = Math.min(ny, page.cropB - m)
                        else if (grab === "b") page.cropB = Math.max(ny, page.cropT + m)
                        else if (grab === "move") {
                            var dxn = (mouse.x - lastX) / area.aw
                            var dyn = (mouse.y - lastY) / area.ah
                            var w = page.cropR - page.cropL, h = page.cropB - page.cropT
                            var nl = page.clamp(page.cropL + dxn, 0, 1 - w)
                            var nt = page.clamp(page.cropT + dyn, 0, 1 - h)
                            page.cropL = nl; page.cropT = nt
                            page.cropR = nl + w; page.cropB = nt + h
                            lastX = mouse.x; lastY = mouse.y
                        }
                    }
                    onReleased: grab = ""
                }
            }
        }

        Label {
            id: errorLabel
            anchors {
                bottom: parent.bottom
                bottomMargin: toolbar.height + Theme.paddingMedium
                horizontalCenter: parent.horizontalCenter
            }
            color: Theme.errorColor
            font.pixelSize: Theme.fontSizeSmall
            visible: text.length > 0
        }
    }

    // ── Bottom toolbar ───────────────────────────────────────────────────────
    Column {
        id: toolbar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        spacing: Theme.paddingMedium
        topPadding: Theme.paddingMedium
        bottomPadding: Theme.paddingLarge

        // Tool selector.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.paddingLarge
            Repeater {
                model: [["crop", qsTr("Crop")], ["draw", qsTr("Draw")]]
                Rectangle {
                    width: tlabel.width + Theme.paddingLarge * 2
                    height: Theme.itemSizeSmall
                    radius: Theme.paddingSmall
                    color: page.tool === modelData[0]
                           ? Theme.highlightBackgroundColor : Theme.rgba(Theme.secondaryColor, 0.15)
                    Label {
                        id: tlabel
                        anchors.centerIn: parent
                        text: modelData[1]
                        color: page.tool === modelData[0] ? Theme.highlightColor : Theme.primaryColor
                    }
                    MouseArea { anchors.fill: parent; onClicked: page.tool = modelData[0] }
                }
            }
        }

        // Shape selector (draw mode only).
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.paddingLarge
            visible: page.tool === "draw"
            Repeater {
                model: [["free", "✎"], ["circle", "◯"], ["arrow", "➜"]]
                Rectangle {
                    width: Theme.itemSizeSmall; height: Theme.itemSizeSmall
                    radius: Theme.paddingSmall
                    color: page.shape === modelData[0]
                           ? Theme.highlightBackgroundColor : Theme.rgba(Theme.secondaryColor, 0.15)
                    Label {
                        anchors.centerIn: parent
                        text: modelData[1]
                        font.pixelSize: Theme.fontSizeLarge
                        color: page.shape === modelData[0] ? Theme.highlightColor : Theme.primaryColor
                    }
                    MouseArea { anchors.fill: parent; onClicked: page.shape = modelData[0] }
                }
            }

            // Rotate (an action, not a shape) — Gallery's image-rotate icon,
            // 90° clockwise per tap; highlighted while the image is turned.
            Rectangle {
                width: Theme.itemSizeSmall; height: Theme.itemSizeSmall
                radius: Theme.paddingSmall
                color: page.rotation !== 0
                       ? Theme.highlightBackgroundColor : Theme.rgba(Theme.secondaryColor, 0.15)
                Icon {
                    anchors.centerIn: parent
                    source: "image://theme/icon-m-rotate-right"
                    color: page.rotation !== 0 ? Theme.highlightColor : Theme.primaryColor
                }
                MouseArea { anchors.fill: parent; onClicked: page.rotate90() }
            }
        }

        // Colour swatches (draw mode only).
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.paddingMedium
            visible: page.tool === "draw"
            Repeater {
                model: page.palette
                Rectangle {
                    width: Theme.itemSizeExtraSmall * 0.7; height: width; radius: width / 2
                    color: modelData
                    border.color: page.penColor === modelData ? Theme.highlightColor : "#80ffffff"
                    border.width: page.penColor === modelData ? 4 : 1
                    MouseArea { anchors.fill: parent; onClicked: page.penColor = modelData }
                }
            }
        }

        // Stroke width (draw mode only).
        Slider {
            width: parent.width
            visible: page.tool === "draw"
            minimumValue: 2
            maximumValue: 40
            stepSize: 1
            value: page.penWidth
            label: qsTr("Stroke width")
            valueText: Math.round(value) + " px"
            onValueChanged: page.penWidth = value
        }

        // Crop-mode hint.
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: page.tool === "crop"
            text: qsTr("Drag the edges or corners")
            color: Theme.secondaryColor
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    // ── Top action bar: Save / Undo / Reset, above the image ──────────────────
    Row {
        id: topBar
        anchors {
            top: parent.top; topMargin: Theme.paddingMedium
            horizontalCenter: parent.horizontalCenter
        }
        height: Theme.itemSizeSmall + Theme.paddingMedium
        spacing: Theme.paddingLarge

        Repeater {
            model: [["save", qsTr("Save copy")], ["undo", qsTr("Undo")], ["reset", qsTr("Reset")]]
            Rectangle {
                width: alabel.width + Theme.paddingLarge * 2
                height: Theme.itemSizeSmall
                radius: Theme.paddingSmall
                readonly property bool act: modelData[0] === "save"
                readonly property bool dim: modelData[0] === "undo" && page.annotations.length === 0
                opacity: dim ? 0.4 : 1.0
                color: act ? Theme.highlightBackgroundColor
                           : Theme.rgba(Theme.secondaryColor, 0.15)
                Label {
                    id: alabel
                    anchors.centerIn: parent
                    text: modelData[1]
                    color: act ? Theme.highlightColor : Theme.primaryColor
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: !parent.dim && !page.saving
                    onClicked: {
                        if (modelData[0] === "save") page.doSave()
                        else if (modelData[0] === "undo") page.undo()
                        else page.resetAll()
                    }
                }
            }
        }
    }
}
