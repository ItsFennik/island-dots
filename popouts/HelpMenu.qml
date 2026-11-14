import QtQuick
import Quickshell
import qs.services
import qs.components

// Help menu.
Item {
    id: root
    readonly property bool closeOnLeave: true
    implicitWidth: list.implicitWidth
    implicitHeight: list.implicitHeight
    focus: true

    MenuList {
        id: list
        onDone: Popouts.close()
        items: [
            { text: "Search", shortcut: "⌘D", f: () => Popouts.openOverlay("spotlight") },
            { sep: true },
            { text: "Keyboard Shortcuts", f: () => Popouts.openSettings("keyboard") },
            { text: "About This Computer", f: () => Popouts.openSettings("general") }
        ]
    }
}
