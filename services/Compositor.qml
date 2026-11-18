pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.I3
import Quickshell.WindowManager

// Which Wayland compositor Island runs under, and the handful of things it needs from it:
// the focused monitor, a "workspace changed" signal, and window / session actions.
//
//   Hyprland          native IPC (Quickshell.Hyprland), focus grabs
//   Sway, Scroll, i3  i3 IPC (Quickshell.I3) + swaymsg
//   niri              `niri msg -j event-stream` + `niri msg action …`
//   MangoWC           `mmsg` (watch for the focused monitor, -d for dispatches)
//   anything else     wlr-foreign-toplevel + ext-workspace (labwc, Wayfire, river, …)
//
// Every caller goes through here, so nothing else in Island should mention a compositor.
Singleton {
    id: root

    readonly property string desktop: (Quickshell.env("XDG_CURRENT_DESKTOP") || "").toLowerCase()
    readonly property bool hyprland: !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
    readonly property bool niri: !hyprland && !!Quickshell.env("NIRI_SOCKET")
    readonly property bool i3: !hyprland && !niri && !!(Quickshell.env("SWAYSOCK") || Quickshell.env("I3SOCK"))
    readonly property bool mango: !hyprland && !niri && !i3 && /mango/.test(desktop)
    readonly property string name: hyprland ? "hyprland" : niri ? "niri" : mango ? "mango"
                                 : i3 ? (/scroll/.test(desktop) ? "scroll" : "sway")
                                 : (desktop.split(":")[0] || "wayland")
    readonly property string msg: /scroll/.test(desktop) ? "scrollmsg" : "swaymsg"

    // Hyprland can tell us when the user clicks outside a popup (HyprlandFocusGrab). Elsewhere
    // popups cover the screen with a transparent click-catcher while open instead.
    readonly property bool focusGrab: hyprland

    // Hyprland swaps a layer surface's buffer cleanly when it is resized. Others (MangoWC, wlroots)
    // show the old buffer stretched to the new size for a frame — a 30 px bar grown to full
    // screen smeared into vertical streaks. Without this, surfaces keep a fixed size instead.
    readonly property bool smoothResize: hyprland

    // ── Focused monitor ───────────────────────────────────────────────
    // Falls back to the monitor of the focused window, which works anywhere with
    // wlr-foreign-toplevel; callers fall back further to the first screen.
    readonly property string focusedScreen: (hyprland ? Hyprland.focusedMonitor?.name
                                           : i3 ? I3.focusedMonitor?.name
                                           : niri ? niriOutput
                                           : mango ? mangoOutput : "")
                                         || ToplevelManager.activeToplevel?.screens?.[0]?.name || ""
    function screenName() { return focusedScreen || (Quickshell.screens[0]?.name ?? ""); }

    // Number of the focused workspace (1-based), or -1 when the compositor doesn't say.
    readonly property int focusedWorkspace: hyprland ? (Hyprland.focusedWorkspace?.id ?? -1)
                                          : i3 ? (I3.focusedWorkspace?.number ?? -1)
                                          : niri ? niriWorkspace : -1

    signal workspaceChanged()

    Connections {
        target: root.hyprland ? Hyprland : null
        function onFocusedWorkspaceChanged() { root.workspaceChanged(); }
    }
    Connections {
        target: root.i3 ? I3 : null
        function onFocusedWorkspaceChanged() { root.workspaceChanged(); }
    }
    // ext-workspace-v1 (MangoWC, labwc, Wayfire, …).
    Instantiator {
        model: root.hyprland || root.i3 || root.niri ? [] : WindowManager.windowsets
        delegate: Connections {
            required property var modelData
            target: modelData
            function onActiveChanged() { if (modelData.active) root.workspaceChanged(); }
        }
    }

    // ── niri ──────────────────────────────────────────────────────────
    property string niriOutput: ""
    property int niriWorkspace: -1
    property var niriWorkspaces: []
    function niriFocus(ws) {
        if (!ws) return;
        const changed = ws.idx !== niriWorkspace || ws.output !== niriOutput;
        niriOutput = ws.output ?? "";
        niriWorkspace = ws.idx ?? -1;
        if (changed) workspaceChanged();
    }
    Process {
        id: niriEvents
        running: root.niri
        command: ["niri", "msg", "-j", "event-stream"]
        stdout: SplitParser {
            onRead: line => {
                let e; try { e = JSON.parse(line); } catch (err) { return; }
                if (e.WorkspacesChanged) {
                    root.niriWorkspaces = e.WorkspacesChanged.workspaces ?? [];
                    root.niriFocus(root.niriWorkspaces.find(w => w.is_focused));
                } else if (e.WorkspaceActivated?.focused) {
                    root.niriFocus(root.niriWorkspaces.find(w => w.id === e.WorkspaceActivated.id));
                }
            }
        }
        onExited: if (root.niri) retry.restart()
    }

    // ── MangoWC ───────────────────────────────────────────────────────
    // `mmsg -w` streams per-monitor state; "<output> selmon 1" marks the focused one.
    property string mangoOutput: ""
    Process {
        id: mangoWatch
        running: root.mango
        command: ["mmsg", "-w"]
        stdout: SplitParser {
            onRead: line => {
                const m = /^(\S+)\s+selmon\s+1\s*$/.exec(line);
                if (m) root.mangoOutput = m[1];
            }
        }
        onExited: if (root.mango) retry.restart()
    }

    // Restart a watcher that died (compositor restarted, socket hiccup); give up after a few tries.
    property int retries: 0
    Timer {
        id: retry
        interval: 2000
        onTriggered: {
            if (++root.retries > 5) return;
            if (root.niri) niriEvents.running = true;
            if (root.mango) mangoWatch.running = true;
        }
    }

    // ── Actions ───────────────────────────────────────────────────────
    function run(cmd) { Quickshell.execDetached(cmd); }
    function sh(c) { Quickshell.execDetached(["sh", "-c", c]); }
    function hypr(d) { run(["hyprctl", "dispatch", d]); }
    function niriAct(...a) { run(["niri", "msg", "action", ...a]); }
    function sway(c) { run([msg, c]); }
    function mmsg(d) { run(["mmsg", "-d", d]); }
    readonly property var tl: ToplevelManager.activeToplevel

    // What the window menu can offer here. Missing = greyed out.
    readonly property var can: ({
        fullscreen: true, zoom: true, close: true,
        float: hyprland || niri || i3 || mango,
        pin: hyprland || i3,
        swapSplit: hyprland || i3,
        moveTo: hyprland || niri || i3 || mango
    })

    function fullscreen() {
        if (hyprland) hypr("hl.dsp.window.fullscreen(0)");
        else if (niri) niriAct("fullscreen-window");
        else if (i3) sway("fullscreen toggle");
        else if (mango) mmsg("togglefullscreen");
        else if (tl) tl.fullscreen = !tl.fullscreen;
    }
    // macOS "Zoom": fill the screen but keep the bar.
    function zoom() {
        if (hyprland) hypr("hl.dsp.window.fullscreen(1)");
        else if (niri) niriAct("maximize-column");
        else if (mango) mmsg("togglemaximizescreen");
        else if (tl) tl.maximized = !tl.maximized;
    }
    function toggleFloat() {
        if (hyprland) hypr("hl.dsp.window.float()");
        else if (niri) niriAct("toggle-window-floating");
        else if (i3) sway("floating toggle");
        else if (mango) mmsg("togglefloating");
    }
    function pin() {
        if (hyprland) hypr("hl.dsp.window.pin()");
        else if (i3) sway("sticky toggle");
    }
    function swapSplit() {
        if (hyprland) hypr('hl.dsp.layout("togglesplit")');
        else if (i3) sway("layout toggle split");
    }
    function moveTo(i) {
        if (hyprland) hypr("hl.dsp.window.move({ workspace = " + i + " })");
        else if (niri) niriAct("move-window-to-workspace", String(i));
        else if (i3) sway("move container to workspace number " + i);
        else if (mango) mmsg("tag," + i);
    }
    function closeWindow() { tl?.close(); }

    // Force Quit: Hyprland lets you click a window; elsewhere kill the focused window's process.
    function forceQuit() {
        if (hyprland) run(["hyprctl", "kill"]);
        else if (niri) sh("p=$(niri msg -j focused-window | jq -r '.pid // empty'); [ -n \"$p\" ] && kill -9 \"$p\"");
        else if (i3) sh(msg + " -t get_tree | jq -r '.. | select(.focused? == true) | .pid // empty' | head -n1 | xargs -r kill -9");
        else closeWindow();
    }

    function logout() {
        if (hyprland) sh("command -v hyprshutdown >/dev/null && hyprshutdown -t 'Logging out...' || hyprctl dispatch 'hl.dsp.exit()'");
        else if (niri) niriAct("quit", "--skip-confirmation");
        else if (i3) sway("exit");
        else if (mango) mmsg("quit");
        else sh("loginctl terminate-session \"${XDG_SESSION_ID:-self}\"");
    }

    // Island's own lock screen (overlays/Lock.qml) works on every compositor here.
    function lock() { LockState.lock(); }
}
