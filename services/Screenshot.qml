pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Screenshots, macOS-style: capture the screen, a window or a selection (scripts/screenshot.sh
// does the grabbing with grim/slurp), then a floating thumbnail sits in the corner for a few
// seconds. The toolbar (⇧⌘S) and thumbnail are separate windows that only exist while shown.
//   qs -c island ipc call screenshot <toolbar|screen|window|region|all>
Singleton {
    id: root

    readonly property var s: Config.saved
    property bool toolbar: false          // the capture toolbar is open
    property string toolbarScreen: ""
    property string mode: "region"        // toolbar choice: screen | window | region
    property int delay: 0                 // toolbar timer (seconds)

    // The latest capture, shown as the floating thumbnail ("" = none)
    property string shot: ""
    property bool clipboardOnly: false
    property string thumbScreen: ""
    readonly property bool busy: proc.running

    function openToolbar() {
        Popouts.close(); Popouts.closeOverlays();
        toolbarScreen = Compositor.screenName();
        toolbar = true;
    }
    function toggleToolbar() { toolbar ? (toolbar = false) : openToolbar(); }

    // mode: screen | all | window | region. delaySec overrides the toolbar timer.
    function capture(m, delaySec) {
        if (proc.running) return;
        toolbar = false;
        Popouts.close(); Popouts.closeOverlays();
        shot = "";                                    // never photograph our own thumbnail
        thumbScreen = Compositor.screenName();
        const dest = s.screenshotDest ?? "~/Pictures/Screenshots";
        const args = [Quickshell.shellDir + "/scripts/screenshot.sh", m];
        if (dest === "clipboard") args.push("--no-save"); else args.push("--dir", dest);
        if (s.screenshotCopy ?? true) args.push("--copy");
        if (s.screenshotPointer ?? false) args.push("--pointer");
        if (s.screenshotSound ?? true) args.push("--sound");
        const d = delaySec ?? 0;
        if (d > 0) args.push("--delay", String(d));
        proc.command = args;
        proc.running = true;
    }
    function captureFromToolbar() { capture(mode, delay); }

    function dismiss() { shot = ""; }
    function open() { if (shot) Quickshell.execDetached(["xdg-open", shot]); dismiss(); }
    function showInFolder() {
        if (!shot) return;
        Quickshell.execDetached(["xdg-open", shot.slice(0, shot.lastIndexOf("/")) || "/"]);
        dismiss();
    }
    function copy() { if (shot) Quickshell.execDetached(["sh", "-c", 'wl-copy --type image/png < "$1"', "sh", shot]); }
    function trash() {
        if (!shot) return;
        Quickshell.execDetached(["sh", "-c", 'gio trash "$1" 2>/dev/null || rm -f "$1"', "sh", shot]);
        dismiss();
    }

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                const out = text.trim().split("\n").pop() ?? "";
                if (!out) return;
                root.clipboardOnly = out.startsWith("clipboard:");
                if (root.s.screenshotThumb ?? true) root.shot = root.clipboardOnly ? out.slice(10) : out;
            }
        }
    }
}
