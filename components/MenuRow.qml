import QtQuick
import qs.services

// One row of a macOS menu extra (Sound, Wi-Fi…). Kinds:
//   default  – text (and optional round icon like macOS device rows), highlights on hover
//   header   – bold title with an optional control on the right (e.g. a switch)
//   section  – small grey caption ("Output", "Known Networks")
//   sep      – hairline
// Put a control (Switch / Slider) inside as a child; it lands on the right.
MouseArea {
    id: root
    property string text
    property string detail                // grey text on the right
    property string icon                  // Nerd Font glyph in a circle
    property bool on: false               // circle filled with the selection colour
    property bool check: false
    property string kind: "default"
    default property alias trailing: slot.data

    readonly property bool plain: kind === "default"
    readonly property bool lit: plain && containsMouse && enabled
    width: parent ? parent.width : 0
    height: kind === "sep" ? 9 : kind === "section" ? 22 : kind === "header" ? 30 : icon !== "" ? 30 : 22
    hoverEnabled: plain
    cursorShape: Qt.ArrowCursor
    opacity: enabled ? 1 : 0.4

    Rectangle { visible: root.kind === "sep"; anchors { left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 10; verticalCenter: parent.verticalCenter }
        height: 1; color: Qt.alpha(Theme.menuText, Theme.dark ? 0.13 : 0.11) }
    Rectangle { visible: root.plain; anchors.fill: parent; radius: 6; antialiasing: true
        color: root.lit ? Qt.alpha(Theme.menuText, root.pressed ? (Theme.dark ? 0.18 : 0.12) : (Theme.dark ? 0.11 : 0.07)) : "transparent"
        Behavior on color { ColorAnimation { duration: 100 } } }

    Rectangle {
        id: circle
        visible: root.icon !== "" && root.kind !== "sep"
        anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
        width: 24; height: 24; radius: 12
        antialiasing: true
        color: root.on ? Theme.menuSel : Qt.alpha(Theme.menuText, Theme.dark ? 0.16 : 0.1)
        Behavior on color { ColorAnimation { duration: 120 } }
        Text { anchors.centerIn: parent; text: root.icon; color: root.on ? Theme.menuOnSel : Theme.menuText
            font { family: Theme.mono; pixelSize: 12 } }
    }
    Text {
        visible: root.check && root.icon === ""
        anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
        text: "✓"; color: Theme.menuText
        font { family: Theme.font; pixelSize: 12; weight: Theme.w(Font.DemiBold) }
    }
    Text {
        id: label
        visible: root.kind !== "sep"
        anchors { left: circle.visible ? circle.right : parent.left
                  leftMargin: circle.visible ? 9 : root.plain ? 20 : 10
                  right: det.visible ? det.left : slot.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
        text: root.kind === "section" ? root.text.toUpperCase() : root.text
        elide: Text.ElideRight
        color: root.kind === "section" ? Qt.alpha(Theme.menuText, 0.5) : Theme.menuText
        font { family: Theme.font; pixelSize: root.kind === "section" ? 11 : 13
               letterSpacing: root.kind === "section" ? 0.6 : 0
               weight: Theme.w(root.kind === "header" || root.kind === "section" ? Font.DemiBold : Font.Normal) }
    }
    Text {
        id: det
        visible: root.detail !== "" && root.kind !== "sep"
        anchors { right: slot.left; rightMargin: slot.width > 0 ? 8 : 0; verticalCenter: parent.verticalCenter }
        text: root.detail
        color: Qt.alpha(Theme.menuText, 0.45)
        font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 12 }
    }
    Item {
        id: slot
        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
        width: childrenRect.width; height: childrenRect.height
    }
}
