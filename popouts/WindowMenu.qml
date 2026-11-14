import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.components

// Window menu: acts on the focused window (through Compositor, so it works on any compositor).
Item {
    id: root
    readonly property bool closeOnLeave: true
    readonly property var tl: ToplevelManager.activeToplevel
    readonly property int count: Math.max(Config.saved.workspaceCount ?? 6, 6)
    implicitWidth: list.implicitWidth
    implicitHeight: list.implicitHeight
    focus: true

    MenuList {
        id: list
        onDone: Popouts.close()
        items: {
            const on = !!root.tl, out = [
                { text: "Zoom", off: !on, f: () => Compositor.zoom() },
                { text: "Enter Full Screen", shortcut: "⌘F", off: !on, f: () => Compositor.fullscreen() },
                { sep: true },
                { text: "Float Window", shortcut: "⇧⌘T", off: !on || !Compositor.can.float, f: () => Compositor.toggleFloat() },
                { text: "Keep on All Desktops", shortcut: "⌘P", off: !on || !Compositor.can.pin, f: () => Compositor.pin() },
                { text: "Swap Split", shortcut: "⌥⌘T", off: !on || !Compositor.can.swapSplit, f: () => Compositor.swapSplit() },
                { sep: true }
            ];
            for (let i = 1; i <= Math.min(root.count, 9); i++)
                out.push({ text: "Move to Desktop " + i, shortcut: "⇧⌘" + i, off: !on || !Compositor.can.moveTo || Compositor.focusedWorkspace === i,
                           f: () => Compositor.moveTo(i) });
            out.push({ sep: true });
            out.push({ text: "Close Window", shortcut: "⌘Q", off: !on, f: () => root.tl.close() });
            return out;
        }
    }
}
