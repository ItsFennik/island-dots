pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Wallpapers paired with each theme, shown under the theme carousel in the picker.
// Lives in ~/.config/island/theme-walls.json: { "<theme id>": ["~/Pictures/Wallpapers/x.jpg", …] }.
// Paths may start with "~/". Edit by hand, or press P on a wallpaper in the picker to pair it
// with the current theme (P again unpairs).
Singleton {
    id: root

    readonly property string file: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/island/theme-walls.json"
    readonly property string home: Quickshell.env("HOME")
    property var map: ({})

    function expand(p) { return p.startsWith("~/") ? home + p.slice(1) : p; }
    function collapse(p) { return p.startsWith(home + "/") ? "~" + p.slice(home.length) : p; }

    // Absolute paths for a theme, in file order.
    function forTheme(id) { return (map[id] ?? []).map(expand); }
    function has(id, path) { return forTheme(id).includes(path); }

    // Picking a theme also sets one of its wallpapers at random (never the one already up).
    readonly property string setter: Quickshell.shellDir + "/scripts/wallpaper-set.sh"
    property string current: ""
    function pick(id) {
        const all = forTheme(id), l = all.filter(p => p !== current);
        return l.length ? l[Math.floor(Math.random() * l.length)] : (all[0] ?? "");
    }
    // `wait`: matugen was just switched off; give settings.json a moment to be written, or
    // wallpaper-set.sh would rebuild matugen and re-apply it over the chosen theme.
    function setWall(path, wait) {
        if (!path || path === current) return;
        if (wait) Quickshell.execDetached(["sh", "-c", 'sleep 0.6; exec "$0" "$1"', setter, path]);
        else Quickshell.execDetached([setter, path]);
    }
    function applyRandom(id, wait) {
        const w = pick(id);
        setWall(w, wait);
        return w;
    }

    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || root.home + "/.local/state") + "/island/wallpaper"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.current = text().trim()
    }

    function toggle(id, path) {
        if (!id || !path) return;
        const m = JSON.parse(JSON.stringify(map));
        const list = (m[id] ?? []).filter(p => expand(p) !== path);
        if (list.length === (m[id] ?? []).length) list.push(collapse(path));
        if (list.length) m[id] = list; else delete m[id];
        map = m;
        view.setText(JSON.stringify(m, null, 2) + "\n");
    }

    FileView {
        id: view
        path: root.file
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.map = JSON.parse(text() || "{}"); }
            catch (e) { console.warn("island: theme-walls.json: " + e); }
        }
        onLoadFailed: root.map = {}
    }
}
