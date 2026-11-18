pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Spotlight's history: what was opened recently and how often, keyed "app:<desktop id>",
// "sys:<action>" or "cmd:<shell command>". Stored in ~/.local/state/island/spotlight.json.
// First run seeds the counts from the launcher's app launch counts (Apps.usage).
Singleton {
    id: root

    property var recent: []          // keys, newest first
    property var count: ({})         // key -> uses
    property bool seeded: false

    function record(key) {
        recent = [key, ...recent.filter(k => k !== key)].slice(0, 30);
        const c = Object.assign({}, count);
        c[key] = (c[key] ?? 0) + 1;
        count = c;
        save();
    }
    function forget(key) {
        recent = recent.filter(k => k !== key);
        const c = Object.assign({}, count);
        delete c[key];
        count = c;
        save();
    }
    // Most used keys, best first.
    function frequent() {
        return Object.keys(count).sort((a, b) => count[b] - count[a]);
    }
    function save() { store.setText(JSON.stringify({ recent, count }) + "\n"); }

    FileView {
        id: store
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/island/spotlight.json"
        printErrors: false
        atomicWrites: true
        onLoaded: {
            try { const d = JSON.parse(text()); root.recent = d.recent ?? []; root.count = d.count ?? {}; root.seeded = true; }
            catch (e) { root.recent = []; root.count = {}; }
        }
        onLoadFailed: root.seeded = false
    }
    // No file yet: start "frequently used" from the launcher's counts.
    readonly property var appUsage: Apps.usage
    onAppUsageChanged: {
        if (seeded || Object.keys(count).length) return;
        const c = {};
        for (const id in appUsage) c["app:" + id] = appUsage[id];
        count = c;
    }
}
