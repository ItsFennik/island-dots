pragma Singleton
import QtQuick
import Quickshell

// Pinned dock apps (desktop ids, in order), stored in the dockPinned setting.
// Shared by the dock, Launchpad and Spotlight so "Keep in Dock" works everywhere.
Singleton {
    id: root

    readonly property var ids: Config.saved.dockPinned ?? []

    function has(id) { return ids.includes(id); }
    function pin(id, at) {
        const p = ids.filter(x => x !== id);
        p.splice(at === undefined ? p.length : Math.max(0, Math.min(at, p.length)), 0, id);
        Config.commit("dockPinned", p);
    }
    function unpin(id) { Config.commit("dockPinned", ids.filter(x => x !== id)); }
    function toggle(id) { has(id) ? unpin(id) : pin(id); }
    function move(id, to) { if (has(id)) pin(id, to); }
}
