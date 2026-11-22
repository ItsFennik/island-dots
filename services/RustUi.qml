pragma Singleton
import QtQuick
import Quickshell

// Rust replacements for the QML Spotlight and Settings surfaces. The binaries read
// Island's settings.json and theme files; this singleton only launches them.
Singleton {
    id: root

    readonly property string binDir: (Quickshell.env("HOME") || "") + "/.local/bin"

    function call(name, args, withMonitor) {
        let cmd = [root.binDir + "/" + name, "--shell-dir", Quickshell.shellDir];
        if (withMonitor) cmd = cmd.concat(["--monitor", Compositor.screenName()]);
        cmd = cmd.concat(args || []);
        Quickshell.execDetached(cmd);
    }

    function spotlightToggle() { call("island-spotlight", [], true); }
    function spotlightOpen() { call("island-spotlight", ["--open"], true); }
    function spotlightClose() { call("island-spotlight", ["--close"], true); }

    function settingsToggle() { call("island-settings", [], false); }
    function settingsOpen(page) { call("island-settings", ["--open"].concat(page ? ["--page", page] : []), false); }
    function settingsClose() { call("island-settings", ["--close"], false); }
}
