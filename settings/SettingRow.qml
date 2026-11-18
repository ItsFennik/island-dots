import QtQuick
import qs.services

// One row in a group: label (and grey description) on the left, control on the right,
// an inset hairline above every row but the first — macOS System Settings layout.
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

    Rectangle {
        visible: root.y > 0
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 14; rightMargin: 14 }
        height: 1
        color: Qt.alpha(Theme.text, 0.07)
    }
    Item {
        id: head
        width: parent.width
        MouseArea { anchors.fill: parent; enabled: root.clickable; onClicked: root.clicked() }
        height: Math.max(root.subtitle !== "" ? 52 : 42, slot.childrenRect.height + 16)
        Rectangle {
            id: ic
            visible: root.glyph !== ""
            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
            width: 22; height: 22; radius: 6
            color: root.glyphTint
            Text { anchors.centerIn: parent; text: root.glyph; color: "white"; font { family: Theme.mono; pixelSize: 12 } }
        }
        Column {
            anchors { left: ic.visible ? ic.right : parent.left; leftMargin: ic.visible ? 10 : 14; right: slot.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            spacing: 2
            Text { width: parent.width; text: root.title; color: Theme.text; elide: Text.ElideRight; font { family: Theme.font; pixelSize: 13 } }
            Text {
                width: parent.width
                visible: root.subtitle !== ""
                text: root.subtitle
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: Theme.textDim
                font { family: Theme.font; pixelSize: 11 }
            }
        }
        Item {
            id: slot
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            width: childrenRect.width; height: childrenRect.height
        }
    }
    Item {
        id: belowSlot
        anchors { top: head.bottom; left: parent.left; right: parent.right }
        height: childrenRect.height
    }
}
