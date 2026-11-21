pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Spotlight history in ~/.local/state/island/spotlight.json, keyed app:/sys:/cmd:. Apps.launch()
// records every launch from any surface; old Apps.usage counts merge in with max().
Singleton {
    id: root

    property var recent: []          // keys, newest first
    property var count: ({})         // key -> launches
    property var pinned: []          // keys kept at the top of "Frequently used", newest first
    property bool ready: false
    property var pending: []         // launches that arrived before the file finished loading

    function record(key) {
        if (!key) return;
        if (!ready) { pending.push(key); return; }
        const c = Object.assign({}, count);
        c[key] = (c[key] ?? 0) + 1;
        count = c;
        recent = [key, ...recent.filter(k => k !== key)].slice(0, 30);
        save();
    }
    function forget(key) {
        recent = recent.filter(k => k !== key);
        pinned = pinned.filter(k => k !== key);
        const c = Object.assign({}, count);
        delete c[key];
        count = c;
        save();
    }

    function isPinned(key) { return !!key && pinned.includes(key); }
    function togglePin(key) {
        if (!key) return;
        pinned = isPinned(key) ? pinned.filter(k => k !== key) : [key, ...pinned];
        save();
    }

    // Most used keys, best first. Ties go to whatever was opened most recently.
    function frequent() {
        const recency = k => { const i = recent.indexOf(k); return i < 0 ? 999 : i; };
        return Object.keys(count)
            .filter(k => (count[k] ?? 0) > 0)
            .sort((a, b) => ((count[b] ?? 0) - (count[a] ?? 0)) || (recency(a) - recency(b)));
    }
    // "Frequently used" order: pinned keys first, then the rest by count.
    function frequentOrdered() {
        return [...new Set([...pinned, ...frequent().filter(k => !pinned.includes(k))])];
    }

    function save() {
        if (!ready) return;
        store.setText(JSON.stringify({ recent, count, pinned }, null, 2) + "\n");
    }

    // Fold the launcher's per-app counts into ours (max, so it's safe to run repeatedly).
    function mergeLauncher() {
        if (!ready) return;
        const usage = Apps.usage ?? {};
        const c = Object.assign({}, count);
        let changed = false;
        for (const id in usage) {
            const key = "app:" + id;
            if ((c[key] ?? 0) < usage[id]) { c[key] = usage[id]; changed = true; }
        }
        if (changed) { count = c; save(); }
    }

    function loaded() {
        root.ready = true;
        const queued = root.pending;
        root.pending = [];
        for (const k of queued) root.record(k);
        root.mergeLauncher();
    }

    readonly property var appUsage: Apps.usage
    onAppUsageChanged: mergeLauncher()

    FileView {
        id: store
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/island/spotlight.json"
        printErrors: false
        atomicWrites: true
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.recent = Array.isArray(d.recent) ? d.recent : [];
                root.count = d.count ?? {};
                root.pinned = Array.isArray(d.pinned) ? d.pinned : [];
            } catch (e) {
                console.warn("island: could not parse spotlight history:", e);
                root.recent = []; root.count = {}; root.pinned = [];
            }
            root.loaded();
        }
        onLoadFailed: {
            root.recent = []; root.count = {}; root.pinned = [];
            root.loaded();
        }
    }
}
