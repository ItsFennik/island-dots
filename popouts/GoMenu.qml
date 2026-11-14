import QtQuick
import Quickshell
import qs.services
import qs.components

// Go menu (with Files or the desktop focused), like Finder's.
Item {
    id: root
    readonly property bool closeOnLeave: true
    readonly property string home: Quickshell.env("HOME")
    implicitWidth: list.implicitWidth
    implicitHeight: list.implicitHeight
    focus: true

    function open(uri) { Quickshell.execDetached(["gio", "open", uri]); }
    // XDG user folders (localised names), falling back to the English ones.
    function xdg(name, fallback) { return "sh -c 'gio open \"$(xdg-user-dir " + name + " 2>/dev/null || echo \"$HOME/" + fallback + "\")\"'"; }
    function sh(c) { Quickshell.execDetached(["sh", "-c", c]); }

    MenuList {
        id: list
        onDone: Popouts.close()
        items: [
            { text: "Home", shortcut: "⇧⌘H", f: () => root.open(root.home) },
            { text: "Desktop", f: () => root.sh(root.xdg("DESKTOP", "Desktop")) },
            { text: "Documents", f: () => root.sh(root.xdg("DOCUMENTS", "Documents")) },
            { text: "Downloads", f: () => root.sh(root.xdg("DOWNLOAD", "Downloads")) },
            { text: "Pictures", f: () => root.sh(root.xdg("PICTURES", "Pictures")) },
            { text: "Music", f: () => root.sh(root.xdg("MUSIC", "Music")) },
            { text: "Videos", f: () => root.sh(root.xdg("VIDEOS", "Videos")) },
            { sep: true },
            { text: "Applications", shortcut: "⌘A", f: () => Popouts.openOverlay("launchpad") },
            { text: "Computer", f: () => root.open("file:///") },
            { text: "Trash", f: () => root.open("trash:///") }
        ]
    }
}
