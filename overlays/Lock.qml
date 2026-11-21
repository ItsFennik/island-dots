import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import qs.services

// Lock screen (ext-session-lock, so the compositor stays locked if Island crashes).
// Locks on LockState.lock(), `ipc call lock lock`, `loginctl lock-session`, and optionally once at login.
// What it draws is in LockContent.qml.
Scope {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string user: Quickshell.env("USER") || ""
    property string realName: user
    property string password: ""
    property string primary: ""          // screen that shows the password field
    readonly property bool typing: password !== ""
    property bool failed: false          // wrong password, shown until the next keypress
    property bool unlocking: false       // success: let the fade finish before releasing
    signal shake()

    // Wallpaper, name, picture
    FileView {
        id: wallState
        path: (Quickshell.env("XDG_STATE_HOME") || root.home + "/.local/state") + "/island/wallpaper"
        watchChanges: true
        onFileChanged: reload()
    }
    readonly property string wallFile: (wallState.text() ?? "").trim()
    // A video wallpaper shows its poster frame (wallpaper-set.sh caches it as md5(path).jpg).
    readonly property string wallpaper: /\.(mp4|webm|mkv|mov|m4v|avi)$/i.test(wallFile)
        ? (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/island/video-thumbs/" + Qt.md5(wallFile) + ".jpg"
        : wallFile

    Process {
        running: root.user !== ""
        command: ["getent", "passwd", root.user]
        stdout: StdioCollector {
            onStreamFinished: {
                const gecos = (text.split(":")[4] ?? "").split(",")[0].trim();
                if (gecos) root.realName = gecos;
            }
        }
    }
    // Same places SDDM and GNOME look.
    readonly property var avatars: [home + "/.face.icon", home + "/.face", "/var/lib/AccountsService/icons/" + user]

    // Locking
    Connections {
        target: LockState
        function onLockedChanged() {
            if (!LockState.locked) return;
            root.password = "";
            root.failed = false;
            root.unlocking = false;
            failTimer.stop();
            unlockTimer.stop();
            root.primary = Compositor.screenName();
            Popouts.close();
            Popouts.closeOverlays();
        }
    }

    // Lock on login: session-stamp.sh succeeds only on the first start per boot/session, so hot
    // reloads don't re-lock. Delayed so Config has loaded the setting.
    Process {
        id: sessionStamp
        command: [Quickshell.shellDir + "/scripts/session-stamp.sh"]
        onExited: code => { if (code === 0) Compositor.lock(); }
    }
    Timer {
        interval: 900
        running: true
        onTriggered: if (Config.saved.lockOnStart ?? false) sessionStamp.running = true
    }

    // loginctl lock-session → logind emits Lock on our session object.
    function busEscape(s) {
        let out = "";
        for (let i = 0; i < s.length; i++) {
            const c = s[i];
            out += /[A-Za-z]/.test(c) || (/[0-9]/.test(c) && i > 0) ? c : "_" + c.charCodeAt(0).toString(16).padStart(2, "0");
        }
        return out;
    }
    readonly property string sessionId: Quickshell.env("XDG_SESSION_ID") || ""
    readonly property string sessionPath: sessionId ? "/org/freedesktop/login1/session/" + busEscape(sessionId) : ""
    Process {
        id: logind
        running: true
        command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1"]
        stdout: SplitParser {
            onRead: line => {
                if (!/\.Session\.Lock \(\)/.test(line)) return;
                if (root.sessionPath === "" || line.startsWith(root.sessionPath + ":")) Compositor.lock();
            }
        }
        onExited: relisten.restart()
    }
    Timer { id: relisten; interval: 5000; onTriggered: logind.running = true }

    // Authentication
    // Same PAM stack as hyprlock (/etc/pam.d/login).
    PamContext {
        id: pam
        onResponseRequiredChanged: if (responseRequired) respond(root.password)
        onCompleted: result => {
            if (result === PamResult.Success) { root.password = ""; root.unlock(); }
            else root.fail();
        }
        onError: root.fail()
    }
    readonly property alias pam: pam
    // Keep the surface up for the length of LockContent's fade, then release the session.
    function unlock() {
        if (unlocking) return;
        unlocking = true;
        unlockTimer.restart();
    }
    Timer { id: unlockTimer; interval: 300; onTriggered: LockState.locked = false }
    Timer { id: failTimer; interval: 1800; onTriggered: root.failed = false }
    onPasswordChanged: if (password !== "" && failed) failed = false
    function submit() {
        if (previewing) { fail(); return; }
        if (unlocking || pam.active || password === "") return;
        pam.start();
    }
    function fail() {
        if (unlocking) return;
        password = "";
        failed = true;
        failTimer.restart();
        shake();
    }

    // Surfaces (one per screen)
    WlSessionLock {
        locked: LockState.locked

        WlSessionLockSurface {
            id: surf
            color: "#000000"
            LockContent {
                lock: root
                main: !root.primary || surf.screen?.name === root.primary
                      || !Quickshell.screens.some(s => s.name === root.primary)
            }
        }
    }

    // Preview: the same screen in a normal overlay (any click or Esc closes it). Nothing is locked.
    property bool previewing: false
    LazyLoader {
        active: root.previewing && !LockState.locked
        PanelWindow {
            screen: Quickshell.screens.find(s => s.name === Compositor.screenName()) ?? Quickshell.screens[0]
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "island-lock-preview"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "#000000"
            LockContent {
                lock: root
                preview: true
                focus: true
                Keys.onEscapePressed: root.previewing = false
                MouseArea { anchors.fill: parent; z: 10; onClicked: root.previewing = false }
            }
        }
    }
}
