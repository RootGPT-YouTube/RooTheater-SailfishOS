import QtQuick 2.6
import Sailfish.Silica 1.0

// A labelled row of mutually-exclusive toggle buttons (a simple segmented
// control). Emits selected(index) when the user taps an option.
Column {
    id: root

    property string title: ""
    property var options: []      // list of display strings
    property int current: 0

    signal selected(int index)

    spacing: Theme.paddingSmall

    Label {
        x: Theme.horizontalPageMargin
        text: root.title
        color: Theme.secondaryHighlightColor
        font.pixelSize: Theme.fontSizeSmall
    }

    Flow {
        x: Theme.horizontalPageMargin
        width: parent.width - 2 * Theme.horizontalPageMargin
        spacing: Theme.paddingMedium

        Repeater {
            model: root.options
            delegate: Rectangle {
                readonly property bool active: index === root.current
                width: optLabel.width + 2 * Theme.paddingLarge
                height: Theme.itemSizeSmall
                radius: Theme.paddingSmall
                color: active ? Theme.highlightBackgroundColor : "transparent"
                border.width: active ? 0 : 1
                border.color: Theme.secondaryColor

                Label {
                    id: optLabel
                    anchors.centerIn: parent
                    text: modelData
                    color: active ? Theme.highlightColor : Theme.primaryColor
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.selected(index)
                }
            }
        }
    }
}
