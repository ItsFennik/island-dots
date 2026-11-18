pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Colours picked from the current wallpaper (matugen), for the desktop widgets when
// Settings → Desktop & Widgets → Colours is "Wallpaper". Independent of the shell theme:
// the menu bar can stay monochrome while the widgets follow the wallpaper.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property bool wanted: (Config.saved.widgetColors ?? "system") === "wallpaper"
    readonly property string mode: Theme.dark ? "dark" : "light"
    property string wallpaper: ""
    property var p: ({})                     // matugen colour name → "#rrggbb"
    readonly property bool ready: wanted && p.primary !== undefined

    // Videos: matugen reads the poster frame wallpaper-set.sh caches (md5 of the path).
    readonly property string still: {
        if (!wallpaper) return "";
        if (!/\.(mp4|webm|mkv|mov|m4v|avi)$/i.test(wallpaper)) return wallpaper;
        const cache = Quickshell.env("XDG_CACHE_HOME") || home + "/.cache";
        return cache + "/island/video-thumbs/" + Qt.md5(wallpaper) + ".jpg";
    }

    function refresh() {
        if (!wanted || !still) return;
        gen.running = false;
        gen.command = ["matugen", "image", still, "--json", "hex", "--dry-run", "-q",
            "-m", mode, "-t", "scheme-" + (Config.saved.matugenScheme ?? "tonal-spot"),
            "--prefer", Config.saved.matugenPrefer ?? "saturation"];
        gen.running = true;
    }
    onStillChanged: refresh()
    onWantedChanged: refresh()
    onModeChanged: refresh()

    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || root.home + "/.local/state") + "/island/wallpaper"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.wallpaper = text().trim()
    }

    Process {
        id: gen
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const c = JSON.parse(text).colors, out = {};
                    for (const k in c) out[k] = c[k][root.mode]?.color ?? c[k].default?.color;
                    root.p = out;
                } catch (e) { console.warn("island: matugen widget colours failed", e); }
            }
        }
    }
}
