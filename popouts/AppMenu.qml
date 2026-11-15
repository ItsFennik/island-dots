import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.components

// The bold app-name menu.
Item {
    id: root
    readonly property bool closeOnLeave: true
    readonly property var tl: ToplevelManager.activeToplevel
    readonly property var entry: tl ? DesktopEntries.heuristicLookup(tl.appId) : null
    readonly property string name: entry?.name || tl?.appId || "Desktop"
    implicitWidth: list.implicitWidth
    implicitHeight: list.implicitHeight
    focus: true

    MenuList {
        id: list
        onDone: Popouts.close()
        items: root.tl ? [
            { text: "New Window", shortcut: "⌘N", off: !root.entry, f: () => Apps.launch(root.entry) },
            { sep: true },
            { text: DockPins.has(root.entry?.id ?? "") ? "Remove from Dock" : "Keep in Dock", off: !root.entry, f: () => DockPins.toggle(root.entry.id) },
            { sep: true },
            { text: "Quit " + root.name, shortcut: "⌘Q", f: () => root.tl.close() }
        ] : [
            { text: "Open Launchpad", shortcut: "⌘A", f: () => Popouts.openOverlay("launchpad") },
            { text: "Spotlight Search", shortcut: "⌘D", f: () => Popouts.openOverlay("spotlight") },
            { sep: true },
            { text: "Change Wallpaper…", shortcut: "⌘W", f: () => Popouts.open("wallpapers") },
            { text: "Take Screenshot…", shortcut: "⇧⌘S", f: () => Screenshot.openToolbar() }
        ]
    }
}
