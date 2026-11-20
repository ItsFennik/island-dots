import QtQuick
import Quickshell
import qs.services
import qs.components

// Right-click menu for an app on the bottom bar / compact bar (Popouts.ctxApp, set by the
// bar before opening): its windows, the desktop file's actions (New Private Window…), open or
// new window, pin to the taskbar, and close / quit — like the Dock's menu, macOS style.
Item {
    id: root
    readonly property bool closeOnLeave: true
    readonly property var app: Popouts.ctxApp           // { id, name, entry, wins }
    implicitWidth: list.implicitWidth
    implicitHeight: list.implicitHeight
    focus: true

    // The app quit (its last window closed and it isn't pinned) while the menu was open.
    onAppChanged: if (!app) Popouts.close()

    MenuList {
        id: list
        minWidth: 200
        onDone: Popouts.close()
        items: {
            const a = root.app;
            if (!a) return [];
            const wins = a.wins ?? [], out = [{ header: true, text: a.name }];
            for (const w of wins)
                out.push({ text: w.title || a.name, check: w.activated, f: () => w.activate() });
            if (wins.length) out.push({ sep: true });
            const acts = a.entry?.actions ?? [];
            for (const x of acts) out.push({ text: x.name, f: () => x.execute() });
            if (acts.length) out.push({ sep: true });
            if (a.entry) out.push({ text: wins.length ? "New Window" : "Open", f: () => Apps.launch(a.entry, a.id) });
            if (a.entry) {
                const pinned = DockPins.has(a.id);
                out.push({ text: pinned ? "Unpin from Taskbar" : "Pin to Taskbar", f: () => DockPins.toggle(a.id) });
            }
            if (wins.length) {
                out.push({ sep: true });
                const focused = wins.find(w => w.activated) ?? wins[0];
                out.push({ text: wins.length > 1 ? "Close Window" : "Close", f: () => focused.close() });
                if (wins.length > 1) out.push({ text: "Quit (" + wins.length + " windows)", f: () => wins.forEach(w => w.close()) });
            }
            return out;
        }
    }
}
