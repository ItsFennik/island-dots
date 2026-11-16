import QtQuick
import qs.services

// Sidebar row: rounded-square colour icon with a white glyph, label, accent selection.
MouseArea {
    id: root
    property string text
    property string glyph
    property color tint
    property bool current: false
    implicitHeight: 28

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: root.current ? Theme.accent : "transparent"
    }
    Badge {
        id: badge
        anchors { left: parent.left; leftMargin: 7; verticalCenter: parent.verticalCenter }
        width: 20; height: 20
        tint: root.tint; glyph: root.glyph
    }
    Text {
        anchors { left: badge.right; leftMargin: 8; right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
        text: root.text
        elide: Text.ElideRight
        color: root.current ? Theme.onAccent : Theme.text
        font { family: Theme.font; pixelSize: 13 }
    }
}
