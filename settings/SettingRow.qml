import QtQuick
import qs.services

// One row in a group: label (and grey description) on the left, control on the right, a
// hairline above every row but the first, inset to line up with the label — macOS layout.
// Clickable rows (device lists) light up under the pointer.
Item {
    id: root
    property string title
    property string subtitle
    property string glyph: ""             // optional leading icon (Nerd Font glyph)
    property color glyphTint: Theme.accent
    property bool changed: false          // kept for callers; not drawn (macOS has no marker)
    property bool pending: false
    default property alias trailing: slot.data
    property alias below: belowSlot.data  // optional full-width content under the row
    property bool clickable: false        // whole row is a button (device lists)
    signal clicked()

    width: parent ? parent.width : 0
    implicitHeight: head.height + belowSlot.childrenRect.height
    opacity: enabled ? 1 : 0.4

    readonly property real textInset: ic.visible ? 46 : 16

    Rectangle {
        visible: root.y > 0
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: root.textInset; rightMargin: 16 }
        height: 1
        color: Qt.alpha(Theme.text, 0.07)
    }
    Item {
        id: head
        width: parent.width
        height: Math.max(root.subtitle !== "" ? 54 : 44, slot.childrenRect.height + 18)
        MouseArea {
            id: hit
            anchors.fill: parent
            enabled: root.clickable
            hoverEnabled: root.clickable
            cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.clicked()
        }
        Rectangle {
            anchors { fill: parent; margins: 4 }
            radius: 8; antialiasing: true
            visible: root.clickable
            color: hit.pressed ? Qt.alpha(Theme.text, 0.09) : hit.containsMouse ? Theme.hover : "transparent"
            Behavior on color { ColorAnimation { duration: 100 } }
        }
        Badge {
            id: ic
            visible: root.glyph !== ""
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            width: 22; height: 22; radius: 6
            tint: root.glyphTint; glyph: root.glyph
        }
        Column {
            anchors { left: parent.left; leftMargin: root.textInset; right: slot.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            spacing: 2
            Text { width: parent.width; text: root.title; color: Theme.text; elide: Text.ElideRight; font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 13 } }
            Text {
                width: parent.width
                visible: root.subtitle !== ""
                text: root.subtitle
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: Theme.textDim
                font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 11 }
            }
        }
        Item {
            id: slot
            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            width: childrenRect.width; height: childrenRect.height
        }
    }
    Item {
        id: belowSlot
        anchors { top: head.bottom; left: parent.left; right: parent.right }
        height: childrenRect.height
    }
}
