import QtQuick
import qs.services

// Sidebar row: colour badge and label. The current pane gets a soft accent wash with a short
// accent pill on its leading edge; the others only light up under the pointer.
MouseArea {
    id: root
    property string text
    property string glyph
    property color tint
    property bool current: false
    implicitHeight: 32
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    Rectangle {
        anchors.fill: parent
        radius: 9
        antialiasing: true
        color: root.current ? Qt.alpha(Theme.accent, Theme.dark ? 0.22 : 0.16)
             : root.pressed ? Qt.alpha(Theme.pal.fg, 0.1)
             : root.containsMouse ? Theme.hover : "transparent"
        Behavior on color { ColorAnimation { duration: 110 } }
    }
    Rectangle {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        width: 3; height: root.current ? 14 : 0
        radius: 1.5; antialiasing: true
        color: Theme.accent
        Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
    Badge {
        id: badge
        anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter }
        width: 22; height: 22; radius: 6
        tint: root.tint; glyph: root.glyph
    }
    Text {
        anchors { left: badge.right; leftMargin: 9; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
        text: root.text
        elide: Text.ElideRight
        color: Theme.text
        font { family: Theme.font; pixelSize: 13; weight: Theme.w(root.current ? Font.DemiBold : Font.Normal) }
    }
}
