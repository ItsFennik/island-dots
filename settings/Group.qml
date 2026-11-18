import QtQuick
import qs.services

// Inset rounded section like macOS System Settings: a small-caps caption above, the rows
// in a soft card, and a grey note below.
Column {
    id: root
    property string title
    property string footer
    default property alias content: rows.data
    width: parent ? parent.width : 0
    spacing: 7

    Text {
        visible: root.title !== ""
        leftPadding: 12
        text: root.title.toUpperCase()
        color: Theme.textDim
        font { family: Theme.font; pixelSize: 11; weight: Font.DemiBold; letterSpacing: 0.6 }
    }
    Rectangle {
        width: parent.width
        height: rows.implicitHeight
        radius: 12
        antialiasing: true
        color: Theme.dark ? Qt.alpha(Theme.text, 0.05) : Qt.rgba(1, 1, 1, 0.75)
        border { width: 1; color: Qt.alpha(Theme.text, Theme.dark ? 0.06 : 0.07) }
        Column { id: rows; anchors { left: parent.left; right: parent.right; top: parent.top } }
    }
    Text {
        visible: root.footer !== ""
        width: parent.width
        leftPadding: 12; rightPadding: 12
        text: root.footer
        wrapMode: Text.WordWrap
        color: Theme.textDim
        font { family: Theme.font; pixelSize: 11 }
        lineHeight: 1.15
    }
}
