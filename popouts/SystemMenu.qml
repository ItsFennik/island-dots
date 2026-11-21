import QtQuick
import Quickshell
import qs.services
import qs.components

// The logo menu at the far left of the menu bar (macOS order and wording).
Item {
    id: root
    readonly property bool closeOnLeave: true
    implicitWidth: list.implicitWidth
    implicitHeight: list.implicitHeight
    focus: true

    readonly property string term: Quickshell.env("TERMINAL") || "foot"
    function sh(c) { Quickshell.execDetached(["sh", "-c", c]); }

    MenuList {
        id: list
        onDone: Popouts.close()
        items: [
            { text: "About This Computer", f: () => Popouts.openSettings("general") },
            { sep: true },
            { text: "System Settings…", shortcut: "⌘I", f: () => Popouts.openSettings("") },
            { sep: true },
            { text: "Force Quit…", shortcut: "⌥⌘⎋", f: () => Compositor.forceQuit() },
            { sep: true },
            { text: "Sleep", f: () => Compositor.power("suspend") },
            { text: "Restart…", f: () => Compositor.power("reboot") },
            { text: "Shut Down…", f: () => Compositor.power("poweroff") },
            { sep: true },
            { text: "Lock Screen", shortcut: "⌃⌘Q", f: () => Compositor.lock() },
            { text: "Log Out " + (Quickshell.env("USER") || "") + "…", shortcut: "⇧⌘Q", f: () => Compositor.logout() }
        ]
    }
}
