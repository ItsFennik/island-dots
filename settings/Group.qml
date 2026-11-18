import QtQuick
import qs.services

// Inset rounded section like macOS System Settings, with an optional bold caption above
// and a grey note below.
Column {
    id: root
    property string title
    property string footer
    default property alias content: rows.data
    width: parent ? parent.width : 0
    spacing: 8

    Text {
        visible: root.title !== ""
        leftPadding: 4
        text: root.title
        color: Theme.text
        font { family: Theme.font; pixelSize: 13; weight: Font.Bold }
    }
    Rectangle {
        width: parent.width
        height: rows.implicitHeight
        radius: 14
        antialiasing: true
        color: Theme.dark ? Qt.alpha(Theme.text, 0.045) : Qt.alpha(Theme.text, 0.03)
        border { width: 1; color: Qt.alpha(Theme.text, Theme.dark ? 0.07 : 0.08) }
        Column { id: rows; anchors { left: parent.left; right: parent.right; top: parent.top } }
    }
    Text {
        visible: root.footer !== ""
        width: parent.width
        leftPadding: 2; rightPadding: 2
        text: root.footer
        wrapMode: Text.WordWrap
        color: Theme.textDim
        font { family: Theme.font; pixelSize: 11 }
        lineHeight: 1.1
    }
}
