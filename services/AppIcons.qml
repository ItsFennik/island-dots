pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// App icon source for the dock, Launchpad, Spotlight, the bottom bar and desktop icons.
// Settings: iconStyle = "default" | "clear" | "tinted" (macOS-style), iconTint = "" (accent) or "#rrggbb".
// Clear/Tinted icons are pre-rendered by scripts/tint-icons.py (the software renderer can't
// colourise with shaders) and cached on disk; until one is ready the normal icon shows.
//   source(name)             follows iconStyle
//   source(name, fb, style)  forces a style ("clear" / "tinted" / "border": unchanged icon + thin rim)
Singleton {
    id: root

    readonly property string style: Config.saved.iconStyle ?? "default"
    readonly property color tint: Config.saved.iconTint || Theme.accent
    readonly property string key: tint + "|" + Theme.dark

    property var ready: ({})            // "style:name" -> file path ("" = couldn't make one)
    property var queue: []              // ["style:name"]
    property var inflight: ({})         // keys handed to the script, not back yet (not bound to)
    property string runKey: ""
    property string runStyle: ""

    onKeyChanged: { ready = {}; queue = []; inflight = {}; }

    function source(name, fallback, forceStyle) {
        const normal = Quickshell.iconPath(name ?? "", fallback ?? "application-x-executable");
        const st = forceStyle || style;
        if (!["clear", "tinted", "border"].includes(st) || !name) return normal;
        const k = st + ":" + name;
        const p = ready[k];
        if (p === undefined) { request(k); return normal; }
        return p ? "file://" + p : normal;
    }

    function request(k) {
        if (inflight[k] || queue.includes(k)) return;
        queue.push(k);
        batch.restart();
    }

    Timer {
        id: batch
        interval: 30
        onTriggered: if (!proc.running && root.queue.length) {
            // one script run per style; the rest waits for the next round
            const st = root.queue[0].split(":")[0];
            const mine = root.queue.filter(k => k.startsWith(st + ":") && root.ready[k] === undefined);
            root.queue = root.queue.filter(k => !k.startsWith(st + ":"));
            if (!mine.length) { if (root.queue.length) batch.restart(); return; }
            for (const k of mine) root.inflight[k] = true;
            root.runKey = root.key;
            root.runStyle = st;
            proc.command = ["python3", Quickshell.shellDir + "/scripts/tint-icons.py",
                            st, root.tint.toString(), Theme.dark ? "1" : "0"].concat(mine.map(k => k.slice(st.length + 1)));
            proc.running = true;
        }
    }

    Process {
        id: proc
        stdout: SplitParser {
            onRead: line => {
                if (root.runKey !== root.key) return;
                const tab = line.indexOf("\t");
                if (tab < 0) return;
                const k = root.runStyle + ":" + line.slice(0, tab);
                delete root.inflight[k];
                const r = Object.assign({}, root.ready);
                r[k] = line.slice(tab + 1);
                root.ready = r;
            }
        }
        onRunningChanged: running ? watchdog.restart() : watchdog.stop()
        onExited: { root.inflight = {}; if (root.queue.length) batch.restart(); }
    }
    // never let a stuck run block icons forever
    Timer {
        id: watchdog
        interval: 90000
        onTriggered: if (proc.running) proc.signal(9)
    }
}
