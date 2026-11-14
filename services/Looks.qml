pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Installed GTK, icon and cursor themes, for Island Settings. Scanned once, the first
// time Settings needs them (singletons are created lazily), and on rescan().
Singleton {
    id: root

    property var gtk: []        // [[value, text], ...]
    property var icons: []
    property var cursors: []

    function rescan() { scan.running = true; }

    Process {
        id: scan
        running: true
        command: ["sh", "-c", `
            for d in "$HOME/.themes" "$HOME/.local/share/themes" /usr/share/themes; do
              for t in "$d"/*/; do [ -d "$t/gtk-3.0" ] && echo "gtk	$(basename "$t")"; done
            done
            for d in "$HOME/.icons" "$HOME/.local/share/icons" /usr/share/icons; do
              for t in "$d"/*/; do
                n=$(basename "$t")
                [ -d "$t/cursors" ] && echo "cursor	$n"
                [ -f "$t/index.theme" ] && grep -q '^Directories=.' "$t/index.theme" && echo "icon	$n"
              done
            done 2>/dev/null | sort -u`]
        stdout: StdioCollector {
            onStreamFinished: {
                const g = [], i = [], c = [];
                const skip = ["hicolor", "locolor", "default", "Default", "Emacs"];
                for (const line of text.split("\n")) {
                    const [kind, name] = line.split("\t");
                    if (!name || skip.includes(name)) continue;
                    const list = kind === "gtk" ? g : kind === "icon" ? i : c;
                    if (!list.some(x => x[0] === name)) list.push([name, name]);
                }
                const byName = (a, b) => a[0].localeCompare(b[0]);
                root.gtk = [["auto", "Island (adw-gtk3, follows theme)"]].concat(g.sort(byName));
                root.icons = i.sort(byName);
                root.cursors = c.sort(byName);
            }
        }
    }
}
