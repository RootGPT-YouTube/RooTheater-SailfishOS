import QtQuick 2.0
import Sailfish.Silica 1.0

// One choice in TracksPage: name, an optional detail line (codec, channels,
// flags), and a check mark on the one in use.
BackgroundItem {
    id: item
    property alias text: nameLabel.text
    property alias detail: detailLabel.text
    property bool checked: false

    width: parent ? parent.width : 0
    height: Math.max(Theme.itemSizeSmall, labels.height + 2 * Theme.paddingMedium)

    Column {
        id: labels
        anchors {
            left: parent.left; leftMargin: Theme.horizontalPageMargin
            right: check.left; rightMargin: Theme.paddingMedium
            verticalCenter: parent.verticalCenter
        }
        Label {
            id: nameLabel
            width: parent.width
            truncationMode: TruncationMode.Fade
            color: item.checked || item.highlighted ? Theme.highlightColor : Theme.primaryColor
        }
        Label {
            id: detailLabel
            width: parent.width
            visible: text !== ""
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeExtraSmall
            color: item.checked || item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
        }
    }
    Icon {
        id: check
        anchors {
            right: parent.right; rightMargin: Theme.horizontalPageMargin
            verticalCenter: parent.verticalCenter
        }
        source: "image://theme/icon-m-acknowledge?" + Theme.highlightColor
        visible: item.checked
    }
}
