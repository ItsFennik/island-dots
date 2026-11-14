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
            { text: "Sleep", f: () => root.sh("systemctl suspend") },
            { text: "Restart…", f: () => root.sh("systemctl reboot") },
            { text: "Shut Down…", f: () => root.sh("systemctl poweroff") },
            { sep: true },
            { text: "Lock Screen", shortcut: "⌃⌘Q", f: () => Compositor.lock() },
            { text: "Log Out " + (Quickshell.env("USER") || "") + "…", shortcut: "⇧⌘Q", f: () => Compositor.logout() }
        ]
    }
}
