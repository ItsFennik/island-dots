import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.services

// Named shortcuts, the same names on every compositor:
//   Hyprland  hl.dsp.global("quickshell:launcher")              (hypr/island.lua, binds.lua)
//   Mango     bind=SUPER,d,spawn,~/.config/mango/scripts/island launcher   (mango/island.conf)
// Hyprland has a global-shortcuts protocol; Mango doesn't, so there the `island` helper writes the
// name to $XDG_RUNTIME_DIR/island.sock — far lighter than starting `qs ipc call` (a Qt app) per
// keypress. The IpcHandlers in shell.qml still work for scripts.
Scope {
    id: root
    required property var settingsWin

    readonly property var actions: ({
        // menus + overlays
        launcher:      () => Popouts.toggleSpotlight(),
        launchpad:     () => Popouts.toggleLaunchpad(),
        overview:      () => Popouts.toggleOverview(),
        notifs:        () => Popouts.toggle("notifs"),
        dnd:           () => Notifs.setDnd(!Notifs.dnd),
        clipboard:     () => Popouts.toggle("clipboard"),
        power:         () => Popouts.toggle("power"),
        controlcenter: () => Popouts.toggle("controls"),
        media:         () => Popouts.toggle("media"),
        wallpaper:     () => Popouts.toggle("wallpapers"),
        theme:         () => Popouts.toggle("themes"),
        settings:      () => { root.settingsWin.open = !root.settingsWin.open; },
        lock:          () => Compositor.lock(),
        // screenshots
        screenshot:        () => Screenshot.capture("region"),
        screenshotWindow:  () => Screenshot.capture("window"),
        screenshotScreen:  () => Screenshot.capture("screen"),
        screenshotToolbar: () => Screenshot.toggleToolbar(),
        // volume + media keys
        volumeUp:       () => Audio.nudge(0.05),
        volumeDown:     () => Audio.nudge(-0.05),
        volumeMute:     () => Audio.toggleMute(),
        mediaPlayPause: () => Media.playPause(),
        mediaNext:      () => Media.next(),
        mediaPrevious:  () => Media.previous(),
        mediaStop:      () => Media.stop()
    })
    function run(name) {
        const f = actions[name];
        if (f) f(); else console.warn("island shortcut: unknown name", name);
    }

    // Hyprland: one GlobalShortcut per action, appid "quickshell" → quickshell:<name>.
    Instantiator {
        active: Compositor.hyprland
        model: Object.keys(root.actions)
        delegate: GlobalShortcut {
            required property string modelData
            appid: "quickshell"
            name: modelData
            onPressed: root.run(modelData)
        }
    }

    // Mango (and anything else): newline-separated names on a Unix socket.
    SocketServer {
        active: true
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/island.sock"
        handler: Socket {
            parser: SplitParser { onRead: line => root.run(line.trim()) }
        }
    }
}
