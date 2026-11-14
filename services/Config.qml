pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Island settings: defaults.json (shipped) overlaid with ~/.config/island/settings.json (yours).
// Only keys you changed are stored. Edits apply automatically ~0.5 s after the last change.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string file: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/island/settings.json"

    property var defaults: ({})
    property var user: ({})
    property var pending: ({})                       // staged, unsaved edits
    readonly property var saved: Object.assign({}, defaults, user)
    readonly property var values: Object.assign({}, saved, pending)
    readonly property int dirtyCount: Object.keys(pending).length

    // Expanded wallpaper folder, used by the picker.
    readonly property string wallDir: {
        const d = saved.wallDir ?? "~/Pictures/Wallpapers";
        return d.startsWith("~") ? home + d.slice(1) : d;
    }
    // Expanded video wallpaper folder (mpvpaper), also shown in the picker.
    readonly property string videoDir: {
        const d = saved.videoDir ?? "~/Videos/Wallpapers";
        return d.startsWith("~") ? home + d.slice(1) : d;
    }

    function get(key) { return values[key]; }
    function isDefault(key) { return values[key] === defaults[key]; }
    function isPending(key) { return key in pending; }

    // Change a setting. Like macOS, changes apply on their own: they're staged, then saved
    // and applied together a moment after the last edit (so dragging a slider writes once).
    function set(key, value) {
        if (values[key] === value) return;
        const p = Object.assign({}, pending);
        if (value === saved[key]) delete p[key]; else p[key] = value;
        pending = p;
        autoSave.restart();
    }
    Timer { id: autoSave; interval: 450; onTriggered: root.save() }

    // Stage defaults for these keys.
    function reset(keys) {
        for (const k of keys) set(k, defaults[k]);
    }

    function discard() { pending = {}; }

    function save() {
        if (dirtyCount === 0) return;
        const u = Object.assign({}, user, pending);
        for (const k of Object.keys(u)) if (u[k] === defaults[k]) delete u[k];
        user = u;
        pending = {};
        applyAfterSave = true;
        userFile.setText(JSON.stringify(u, null, 2) + "\n");   // apply-settings.sh runs once it's on disk
    }
    // Save and apply one key right away, leaving any other staged edits staged.
    function commit(key, value) {
        const p = Object.assign({}, pending);
        delete p[key];
        pending = p;
        if (user[key] === value || (!(key in user) && value === defaults[key])) return;
        const u = Object.assign({}, user);
        if (value === defaults[key]) delete u[key]; else u[key] = value;
        user = u;
        applyAfterSave = true;
        userFile.setText(JSON.stringify(u, null, 2) + "\n");
    }

    property bool applyAfterSave: false
    function runApply() {
        applyAfterSave = false;
        Quickshell.execDetached([Quickshell.shellDir + "/apply-settings.sh"]);
    }

    FileView {
        path: Quickshell.shellDir + "/defaults.json"
        onLoaded: { try { root.defaults = JSON.parse(text()); } catch (e) { console.warn("island: bad defaults.json", e); } }
    }

    FileView {
        id: userFile
        path: root.file
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onSaved: if (root.applyAfterSave) root.runApply()
        onSaveFailed: if (root.applyAfterSave) root.runApply()
        onLoaded: {
            try {
                const v = JSON.parse(text());
                if (v && typeof v === "object" && JSON.stringify(v) !== JSON.stringify(root.user)) root.user = v;
            } catch (e) { console.warn("island: settings.json is not valid JSON; keeping current values"); }
        }
    }
}
