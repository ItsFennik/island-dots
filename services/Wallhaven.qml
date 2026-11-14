pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Wallhaven API key: lives in ~/.config/island/wallhaven-api-key (chmod 600), not settings.json.
// Edit that file by hand or use Island Settings → Wallpaper → API key.
Singleton {
    id: root

    readonly property string keyFile: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/island/wallhaven-api-key"
    readonly property string script: Quickshell.shellDir + "/scripts/wallhaven.sh"
    property string apiKey: ""
    readonly property bool hasKey: apiKey !== "" || (Quickshell.env("WALLHAVEN_API_KEY") ?? "") !== ""

    // Writes the file with 0600 and checks the key with Wallhaven (result comes as a notification).
    function setKey(k) {
        k = (k ?? "").trim();
        if (k === apiKey) return;
        apiKey = k;
        saver.environment = ({ WALLHAVEN_NEW_KEY: k });
        saver.running = true;
    }

    Process { id: saver; command: [root.script, "save-key"] }

    FileView {
        path: root.keyFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.apiKey = text().split("\n").filter(l => !l.trim().startsWith("#")).join("").trim()
        onLoadFailed: root.apiKey = ""
    }
}
