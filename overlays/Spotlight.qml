import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.components

// Spotlight (Super+D): apps, system actions, files in ~ (3+ letters), math, "> cmd", and the web.
// Empty shows Recently / Frequently used (SpotHistory); "?" lists prefixes. Only exists while open.
//   ↑/↓ pick · Enter open · Ctrl+1-9 quick select · Shift+Del remove · Ctrl+F pin/unpin
//   Ctrl+Enter / right-click: Keep in Dock · Esc clear, then close
PanelWindow {
    id: win

    readonly property var s: Config.saved
    readonly property string family: s.widgetFont || "Adwaita Sans"
    readonly property int w: Math.max(460, Math.min(920, Math.round(s.spotlightWidth ?? 700)))
    readonly property int fieldH: 52
    readonly property int rowH: 44
    readonly property int headH: 26
    readonly property int footH: 34
    readonly property int maxRows: Math.max(5, Math.min(12, Math.round(s.spotlightRows ?? 9)))

    // Without focus grabs it covers the whole screen (click outside the card closes it).
    readonly property bool catchAll: !Compositor.focusGrab
    readonly property int topGap: Math.round((screen?.height ?? 1080) * 0.2)
    readonly property int topBarH: (s.barHeight ?? 30) + (BarLayout.skin === "pills" ? 6 : 0)
    readonly property int bottomBarH: (s.taskbarHeight ?? 54) + 8
    // auto follows the bar: capsule bars grow from the capsule, menu bars drop down, bottom
    // bars rise above them. Attached / floating / capsule are explicit overrides.
    readonly property string style: BarLayout.spotlightStyle
    readonly property bool morph: BarLayout.spotlightMorph
    readonly property bool bottom: style === "bottom"
    readonly property bool floating: style === "floating"
    readonly property bool attachedTop: style === "attached"
    readonly property bool notch: BarLayout.skin === "notch"
    readonly property int capY: notch ? 0 : 6
    readonly property int capW0: BarLayout.capsuleIdleW
    readonly property int capH0: s.barHeight ?? 30
    property bool grown: false
    // Grow once the surface has rendered a few frames (not on a blind timer: see Bar.qml's panel).
    FrameAnimation {
        property int frames: 0
        running: win.morph && Popouts.spotlight && !win.grown
        onRunningChanged: frames = 0
        onTriggered: if (++frames >= 3) win.grown = true
    }
    Connections { target: Popouts; enabled: win.morph; function onSpotlightChanged() { if (!Popouts.spotlight) win.grown = false; } }

    anchors {
        top: win.catchAll || !win.bottom
        bottom: win.catchAll || win.bottom
        left: win.catchAll
        right: win.catchAll
    }
    margins.top: win.catchAll || win.morph ? 0 : win.floating ? win.topGap : 0
    exclusionMode: ExclusionMode.Ignore
    // Fixed size (the biggest it can get) so typing never reallocates the surface.
    implicitWidth: w + 40
    implicitHeight: fieldH + maxRows * rowH + 4 * headH + footH + 40
    color: "transparent"
    mask: Region { item: card; Region { item: win.catchAll ? catcher : null } Region { item: ctx.visible ? ctx : null } }

    WlrLayershell.namespace: morph ? "island-capsule-spotlight" : "island-spotlight"   // capsule: Qt animates, not the compositor
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    property bool armed: false
    Timer { interval: 60; running: true; onTriggered: win.armed = true }
    HyprlandFocusGrab { windows: [win]; active: Compositor.focusGrab && win.armed; onCleared: Popouts.closeOverlays() }
    MouseArea {
        id: catcher
        anchors.fill: parent
        z: -1
        visible: win.catchAll
        acceptedButtons: Qt.AllButtons
        onPressed: Popouts.closeOverlays()
    }

    // Sources
    readonly property var system: [
        { key: "sys:lock", title: "Lock", sub: "Lock the screen", glyph: "", words: "lock screen", f: () => Compositor.lock() },
        { key: "sys:sleep", title: "Sleep", sub: "Suspend to RAM", glyph: "󰒲", words: "sleep suspend", f: () => Compositor.power("suspend") },
        { key: "sys:logout", title: "Log Out", sub: "End the session", glyph: "󰍃", words: "log out logout exit quit session", confirm: true, f: () => Compositor.logout() },
        { key: "sys:reboot", title: "Restart", sub: "Reboot the computer", glyph: "", words: "restart reboot", confirm: true, f: () => Compositor.power("reboot") },
        { key: "sys:off", title: "Shut Down", sub: "Power off the computer", glyph: "⏻", words: "shut down shutdown power off poweroff", confirm: true, f: () => Compositor.power("poweroff") },
        { key: "sys:settings", title: "System Settings", sub: "Island settings", glyph: "", words: "settings preferences island", f: () => Popouts.openSettings("") },
        { key: "sys:spotlight", title: "Spotlight Settings", sub: "Window, results and search sources", glyph: "\uf002", words: "spotlight search launcher settings", f: () => Popouts.openSettings("spotlight") }
    ]
    readonly property bool filesOn: s.spotlightFiles !== false
    readonly property bool commandsOn: s.spotlightCommands !== false
    readonly property bool webOn: s.spotlightWeb !== false
    readonly property var help: {
        const out = [
            { kind: "help", fill: "", title: "Apps & actions", sub: "Type a name: Firefox, Lock, Sleep, Restart…", glyph: "" }
        ];
        if (commandsOn) out.push({ kind: "help", fill: "> ", title: "> command", sub: "Run a shell command ($ works too)", glyph: "" });
        out.push({ kind: "help", fill: "", title: "Math", sub: "2*(3+4), 15% of 80 → type it, Enter copies the result", glyph: "󰃬" });
        if (filesOn) out.push({ kind: "help", fill: "", title: "Files", sub: "3+ letters also search your home folder", glyph: "" });
        if (webOn) out.push({ kind: "help", fill: "", title: "Web", sub: "Anything else: last row searches DuckDuckGo", glyph: "󰖟" });
        out.push({ kind: "help", fill: "", title: "Frequently used", sub: "Ctrl+F pins the selected row so it stays at the top", glyph: "󰐃" });
        return out;
    }

    // A history key back to a row (null when the app is gone).
    function fromKey(key) {
        if (key.startsWith("app:")) {
            const e = DesktopEntries.byId(key.slice(4));
            return e && !e.noDisplay ? appRow(e) : null;
        }
        if (key.startsWith("sys:")) { const s = system.find(x => x.key === key); return s ? Object.assign({ kind: "sys" }, s) : null; }
        if (key.startsWith("cmd:")) { const c = key.slice(4); return { kind: "cmd", key, cmd: c, title: c, sub: "Shell command", glyph: "" }; }
        return null;
    }
    function appRow(e) { return { kind: "app", key: "app:" + e.id, entry: e, title: e.name, sub: e.comment || e.genericName || "", icon: e.icon }; }

    // Search
    property string query: ""
    property int index: 0
    property string confirmKey: ""
    readonly property string q: query.trim()
    readonly property bool commandOff: !commandsOn && (q.startsWith(">") || q.startsWith("$"))
    readonly property bool cmd: commandsOn && (q.startsWith(">") || q.startsWith("$"))
    readonly property string calc: {
        let s = q.replace(/^=/, "");
        s = s.replace(/(\d+(?:[.,]\d+)?)\s*%\s*of\s*/gi, "($1/100)*");
        if (cmd || !/^[\d\s+\-*/%().,^]+$/.test(s) || !/\d/.test(s) || !/[+\-*/%^]/.test(s) && !q.startsWith("=")) return "";
        try {
            const v = Function('"use strict"; return (' + s.replace(/,/g, ".").replace(/\^/g, "**") + ")")();
            return typeof v === "number" && isFinite(v) ? String(Math.round(v * 1e10) / 1e10) : "";
        } catch (e) { return ""; }
    }

    // Files: `find` in ~ (no hidden dirs, depth 4), debounced, only for 3+ letters.
    property var files: []
    readonly property bool wantFiles: filesOn && q.length >= 3 && !cmd && !commandOff && calc === "" && q !== "?"
    onQChanged: { files = []; finder.running = false; if (wantFiles) debounce.restart(); }
    Timer { id: debounce; interval: 220; onTriggered: { finder.pattern = win.q; finder.running = true; } }
    Process {
        id: finder
        property string pattern: ""
        command: ["sh", "-c", "cd \"$HOME\" && timeout 1 find . -maxdepth 4 -name '.*' -prune -o -iname \"*$1*\" -print 2>/dev/null | head -n 4", "sh", pattern]
        stdout: StdioCollector {
            onStreamFinished: {
                if (finder.pattern !== win.q) return;
                const home = Quickshell.env("HOME");
                win.files = text.split("\n").filter(l => l && l !== ".").map(l => {
                    const rel = l.replace(/^\.\//, ""), name = rel.split("/").pop();
                    const ext = name.includes(".") ? name.split(".").pop().toLowerCase() : "";
                    const icon = ["png", "jpg", "jpeg", "webp", "gif", "svg"].includes(ext) ? "image-x-generic"
                        : ["mp4", "mkv", "webm", "mov"].includes(ext) ? "video-x-generic"
                        : ["mp3", "flac", "ogg", "wav", "opus"].includes(ext) ? "audio-x-generic"
                        : ext === "pdf" ? "application-pdf" : ext ? "text-x-generic" : "folder";
                    return { kind: "file", title: name, sub: "~/" + rel, icon, path: home + "/" + rel };
                });
            }
        }
    }

    // Flat list of rows: { kind, section?, ... }
    readonly property var rows: {
        const out = [];
        const add = (list, section) => list.forEach((r, i) => out.length < maxRows && out.push(Object.assign({}, r, { section: i === 0 ? section : "" })));
        if (q === "") {
            // Pinned rows live in Frequently used, so keep them out of Recently used.
            const rec = SpotHistory.recent.filter(k => !SpotHistory.isPinned(k)).map(fromKey).filter(r => r).slice(0, 3);
            const seen = rec.map(r => r.key);
            const freq = SpotHistory.frequentOrdered().filter(k => !seen.includes(k)).map(fromKey).filter(r => r).slice(0, 8 - rec.length);
            add(rec, "Recently used");
            add(freq, "Frequently used");
            if (!out.length) add(Apps.search("").slice(0, 8).map(appRow), "Applications");
            return out;
        }
        if (q === "?") { add(help, "Help"); return out; }
        if (commandOff) {
            add([{ kind: "sys", title: "Shell commands are off", sub: "Turn them on in Spotlight Settings", glyph: "\uf002", f: () => Popouts.openSettings("spotlight") }], "Command");
            return out;
        }
        if (cmd) {
            const c = q.slice(1).trim();
            add([{ kind: "cmd", key: "cmd:" + c, cmd: c, title: c ? c : "Type a shell command", sub: "Run in a shell", glyph: "" }], "Command");
            return out;
        }
        if (calc !== "") add([{ kind: "calc", title: calc, sub: q.replace(/^=/, "") + " =  ·  Enter copies", glyph: "󰃬" }], "Math");
        const ql = q.toLowerCase();
        const sys = system.map(s => ({ s, m: Math.max(Apps.match(s.title.toLowerCase(), ql), ...s.words.split(" ").map(w => Apps.match(w, ql) * 0.7)) }))
            .filter(x => x.m >= 300).sort((a, b) => b.m - a.m).map(x => Object.assign({ kind: "sys" }, x.s));
        // Bar skins: "skin", "bar", "menu bar", or (4+ letters) a skin's own name.
        const skinWord = ql.length >= 2 && ["skin", "skins", "bar", "bars", "menu bar", "bar skin", "notch", "island", "pills"]
            .some(w => w.startsWith(ql) || ql.startsWith(w + " "));
        const skins = BarLayout.skins
            .filter(k => skinWord || (ql.length >= 4 && Apps.match(k.label.toLowerCase(), ql) >= 300))
            .map(k => {
                const on = (s.shellLayout ?? "menubar") === "menubar" && BarLayout.skin === k.id;
                return { kind: "sys", title: k.label, sub: (on ? "Current  ·  " : "") + k.sub, glyph: k.glyph, f: () => BarLayout.setSkin(k.id) };
            });
        if (skins.length && /^(skin|bar|menu)/.test(ql)) add(skins, "Bar skins");
        const apps = Apps.search(q).slice(0, sys.length ? 4 : 5).map(appRow);
        if (sys.length && (!apps.length || Apps.match(apps[0].title.toLowerCase(), ql) < Apps.match(sys[0].title.toLowerCase(), ql))) {
            add(sys.slice(0, 2), "Actions"); add(apps, "Applications");
        } else {
            add(apps, "Applications"); add(sys.slice(0, 2), "Actions");
        }
        if (skins.length && !/^(skin|bar|menu)/.test(ql)) add(skins, "Bar skins");
        if (filesOn) add(files.slice(0, Math.max(0, maxRows - 1 - out.length)), "Files");
        if (webOn) add([{ kind: "web", title: "Search the web for “" + q + "”", sub: "DuckDuckGo", glyph: "󰖟" }], "Web");
        return out;
    }
    onRowsChanged: { index = Math.min(index, Math.max(0, rows.length - 1)); if (!rows.some(r => r.key === confirmKey)) confirmKey = ""; }
    onQueryChanged: { index = 0; confirmKey = ""; }

    function inHistory(r) {
        return !!r?.key && (SpotHistory.count[r.key] !== undefined || SpotHistory.recent.includes(r.key) || SpotHistory.isPinned(r.key));
    }

    function run(r) {
        if (!r) return;
        if (r.kind === "help") { input.text = r.fill; return; }
        if (r.kind === "cmd" && !r.cmd) return;
        if (r.confirm && confirmKey !== r.key) { confirmKey = r.key; return; }
        // Apps are recorded by Apps.launch() so Dock/Launchpad launches count too.
        if (r.key && r.kind !== "app") SpotHistory.record(r.key);
        Popouts.closeOverlays();
        if (r.kind === "app") Apps.launch(r.entry, r.entry.id);
        else if (r.kind === "sys") { if (r.f) r.f(); else Quickshell.execDetached(r.cmd); }
        else if (r.kind === "cmd") Apps.run(r.cmd);
        else if (r.kind === "calc") Quickshell.execDetached(["wl-copy", r.title]);
        else if (r.kind === "file") Quickshell.execDetached(["xdg-open", r.path]);
        else if (r.kind === "web") Quickshell.execDetached(["xdg-open", "https://duckduckgo.com/?q=" + encodeURIComponent(q)]);
    }

    // Right-click menu
    property var ctxRow: null
    function openCtx(r, p) {
        if (!ctxItems(r).length) return;
        ctx.px = p.x; ctx.py = p.y;
        ctxRow = r;
    }
    function closeCtx() { ctxRow = null; input.forceActiveFocus(); }
    function ctxItems(r) {
        if (!r) return [];
        const out = [], hist = () => {
            if (!r.key) return;
            out.push({ sep: true });
            out.push({ text: SpotHistory.isPinned(r.key) ? "Unpin from Top" : "Pin to Top", shortcut: "⌃F", f: () => SpotHistory.togglePin(r.key) });
            if (win.inHistory(r)) out.push({ text: "Remove from Recents", shortcut: "⇧⌦", f: () => SpotHistory.forget(r.key) });
        };
        if (r.kind === "app") {
            out.push({ header: true, text: r.title });
            out.push({ text: "Open", f: () => win.run(r) });
            const acts = r.entry?.actions ?? [];
            if (acts.length) out.push({ sep: true });
            for (const a of acts) out.push({ text: a.name, f: () => { Popouts.closeOverlays(); a.execute(); } });
            out.push({ sep: true });
            out.push({ text: DockPins.has(r.entry.id) ? "Unpin from Taskbar" : "Pin to Taskbar", shortcut: "⌃↵", f: () => DockPins.toggle(r.entry.id) });
            hist();
        } else if (r.kind === "file") {
            const dir = r.path.replace(/\/[^/]*$/, "");
            out.push({ header: true, text: r.title });
            out.push({ text: "Open", f: () => win.run(r) });
            out.push({ text: "Open Containing Folder", f: () => { Popouts.closeOverlays(); Quickshell.execDetached(["xdg-open", dir]); } });
            out.push({ sep: true });
            out.push({ text: "Copy Path", f: () => Quickshell.execDetached(["wl-copy", r.path]) });
            out.push({ text: "Copy Name", f: () => Quickshell.execDetached(["wl-copy", r.title]) });
        } else if (r.kind === "cmd" && r.cmd) {
            out.push({ text: "Run", f: () => win.run(r) });
            out.push({ text: "Copy Command", f: () => Quickshell.execDetached(["wl-copy", r.cmd]) });
            hist();
        } else if (r.kind === "calc") {
            out.push({ text: "Copy Result", f: () => win.run(r) });
            out.push({ text: "Copy Expression", f: () => Quickshell.execDetached(["wl-copy", win.query.replace(/^=/, "")]) });
        } else if (r.kind === "web") {
            out.push({ text: "Search the Web", f: () => win.run(r) });
            out.push({ text: "Copy Search Text", f: () => Quickshell.execDetached(["wl-copy", win.query]) });
        } else if (r.kind === "sys") {
            out.push({ header: true, text: r.title });
            out.push({ text: r.confirm ? r.title + "…" : r.title, f: () => win.run(r) });
            hist();
        }
        return out;
    }
    // A click anywhere else while the menu is open just closes the menu.
    MouseArea {
        anchors.fill: parent
        z: 9
        visible: win.ctxRow !== null
        acceptedButtons: Qt.AllButtons
        onPressed: win.closeCtx()
    }
    Rectangle {
        id: ctx
        z: 10
        property real px: 0
        property real py: 0
        // at the pointer, kept on screen (the size follows the items, so bind rather than set once)
        x: Math.round(Math.max(8, Math.min(win.width - width - 8, px)))
        y: Math.round(Math.max(8, Math.min(win.height - height - 8, py)))
        visible: win.ctxRow !== null
        width: (ctxLoader.item?.implicitWidth ?? 0) + 10
        height: (ctxLoader.item?.implicitHeight ?? 0) + 10
        radius: 10
        color: Theme.menuBg
        border { width: 1; color: Theme.menuEdge }
        // Created only while open: MenuList takes keyboard focus when it's created, and a hidden
        // one made with the window stole it from the search field (Super+D couldn't type).
        Loader {
            id: ctxLoader
            x: 5; y: 5
            active: win.ctxRow !== null
            sourceComponent: MenuList {
                minWidth: 190
                items: win.ctxItems(win.ctxRow)
                onDone: win.closeCtx()
                Keys.onEscapePressed: win.closeCtx()
                Keys.onLeftPressed: win.closeCtx()
            }
        }
    }

    // Card
    readonly property color sel: Theme.accent
    readonly property color selText: Theme.onAccent
    readonly property color chip: Qt.alpha(Theme.text, 0.10)

    Rectangle {
        id: card
        readonly property int fullH: win.fieldH + 1 + (win.rows.length ? results.height + 12 : 0) + 1 + win.footH
        anchors.horizontalCenter: parent.horizontalCenter
        y: win.morph ? win.capY
         : win.bottom ? Math.max(8, win.height - fullH - win.bottomBarH - 8)
         : win.attachedTop ? win.topBarH + 8
         : (win.catchAll ? win.topGap : 0) + 10
        width: win.morph && !win.grown ? win.capW0 : win.w
        height: win.morph && !win.grown ? win.capH0 : fullH
        Behavior on width { enabled: win.morph; NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 0.7 } }
        Behavior on height { enabled: win.morph; NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 0.7 } }
        radius: win.morph ? (win.notch ? 18 : Math.min(height / 2, 26)) : win.floating ? 16 : 14
        color: win.morph ? BarLayout.capsuleFill : win.floating ? Theme.menuFloat : Theme.menuBg
        border { width: win.morph ? 0 : 1; color: Theme.menuEdge }
        clip: true
        // Notch: square top corners, flush with the screen edge.
        Rectangle { visible: win.morph && win.notch; width: parent.width; height: parent.radius; color: parent.color }
        Rectangle {
            visible: !win.morph
            anchors { fill: parent; margins: 1 }
            radius: parent.radius - 1
            color: "transparent"
            border { width: 1; color: Theme.menuInner }
        }
        GlassSheen { visible: !win.morph; radius: card.radius; height: Math.min(card.height, 120) }
        // While capsule-sized (opening / closing) the contents hide under the capsule colour.
        Rectangle {
            z: 100
            anchors.fill: parent
            radius: parent.radius
            color: parent.color
            opacity: win.morph && !win.grown ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }

        opacity: win.morph ? 1 : 0; scale: win.morph ? 1 : 0.97
        Component.onCompleted: { opacity = 1; scale = 1; }
        Behavior on opacity { enabled: !win.morph; NumberAnimation { duration: 120 } }
        Behavior on scale { enabled: !win.morph; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        // Field
        Item {
            id: field
            width: parent.width; height: win.fieldH
            Text {
                id: glass
                anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                text: ""; color: Theme.textDim
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 16; hintingPreference: Font.PreferNoHinting }
            }
            TextInput {
                id: input
                anchors { left: glass.right; leftMargin: 12; right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
                focus: true
                clip: true
                color: Theme.text
                selectionColor: Theme.accent; selectedTextColor: Theme.onAccent
                font { family: win.family; weight: Theme.fontWeight; pixelSize: 17 }
                Component.onCompleted: forceActiveFocus()
                onTextChanged: win.query = text
                Row {
                    visible: !input.text
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Text { id: ph; text: "Search apps, files, actions"; color: Theme.textFaint; font: input.font }
                    Text { text: "·  ? for help"; color: Qt.alpha(Theme.textFaint, 0.7); anchors.baseline: ph.baseline; font { family: win.family; weight: Theme.fontWeight; pixelSize: 13 } }
                }
                Keys.onPressed: e => {
                    const n = win.rows.length, ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier;
                    const r = win.rows[win.index];
                    if (e.key === Qt.Key_Escape) { if (input.text) input.text = ""; else Popouts.closeOverlays(); }
                    else if (e.key === Qt.Key_Down || e.key === Qt.Key_Tab || (ctrl && (e.key === Qt.Key_J || e.key === Qt.Key_N))) { if (n) win.index = (win.index + 1) % n; }
                    else if (e.key === Qt.Key_Up || e.key === Qt.Key_Backtab || (ctrl && (e.key === Qt.Key_K || e.key === Qt.Key_P))) { if (n) win.index = (win.index + n - 1) % n; }
                    else if (ctrl && e.key >= Qt.Key_1 && e.key <= Qt.Key_9) win.run(win.rows[e.key - Qt.Key_1]);
                    else if (ctrl && e.key === Qt.Key_F) { if (r?.key) SpotHistory.togglePin(r.key); }
                    else if (e.key === Qt.Key_Menu || (shift && e.key === Qt.Key_F10)) win.openCtx(r, card.mapToItem(win.contentItem, 60, win.fieldH + 30));
                    else if (shift && e.key === Qt.Key_Delete) { if (win.inHistory(r)) SpotHistory.forget(r.key); }
                    else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && ctrl) { if (r?.kind === "app") DockPins.toggle(r.entry.id); }
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) win.run(r);
                    else return;
                    e.accepted = true;
                }
            }
        }

        Rectangle { y: win.fieldH; width: parent.width; height: 1; color: Theme.hairline }

        // Results
        Column {
            id: results
            visible: win.rows.length > 0
            y: win.fieldH + 1 + 6
            x: 6
            width: parent.width - 12
            Repeater {
                model: win.rows
                delegate: Column {
                    id: rowCol
                    required property var modelData
                    required property int index
                    readonly property var r: modelData
                    width: results.width
                    Text {
                        visible: !!rowCol.r.section
                        height: win.headH
                        leftPadding: 12; topPadding: rowCol.index === 0 ? 6 : 10
                        text: rowCol.r.section ?? ""
                        color: Theme.textDim
                        font { family: win.family; pixelSize: 11; weight: Theme.w(Font.DemiBold) }
                    }
                    MouseArea {
                        id: row
                        readonly property bool hot: win.index === rowCol.index
                        readonly property bool asking: win.confirmKey !== "" && win.confirmKey === rowCol.r.key
                        width: parent.width
                        height: win.rowH
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onEntered: win.index = rowCol.index
                        onClicked: e => {
                            if (e.button === Qt.RightButton) win.openCtx(rowCol.r, row.mapToItem(win.contentItem, e.x, e.y));
                            else win.run(rowCol.r);
                        }
                        Rectangle { anchors.fill: parent; radius: 8; color: row.hot ? win.sel : "transparent" }

                        // Icon: app/file icon, or a glyph in a round badge (actions, commands, math…)
                        Item {
                            id: ic
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            width: 28; height: 28
                            Image {
                                visible: !rowCol.r.glyph
                                anchors.fill: parent
                                sourceSize { width: 28 * Screen.devicePixelRatio; height: 28 * Screen.devicePixelRatio }
                                source: rowCol.r.glyph ? "" : AppIcons.source(rowCol.r.icon, rowCol.r.kind === "file" ? "text-x-generic" : undefined)
                                asynchronous: true
                            }
                            Rectangle {
                                visible: !!rowCol.r.glyph
                                anchors.fill: parent
                                radius: width / 2
                                color: row.asking ? Qt.alpha(Theme.pal.red, 0.18) : row.hot ? Qt.alpha(win.selText, 0.18) : Qt.alpha(Theme.text, 0.12)
                                Text {
                                    anchors.centerIn: parent
                                    text: rowCol.r.glyph ?? ""
                                    color: row.asking ? Theme.pal.red : row.hot ? win.selText : Theme.text
                                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 14; hintingPreference: Font.PreferNoHinting }
                                }
                            }
                        }
                        Column {
                            anchors { left: ic.right; leftMargin: 12; right: tail.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            spacing: 1
                            Text {
                                width: parent.width
                                text: row.asking ? "Press ↵ again to " + rowCol.r.title.toLowerCase() : rowCol.r.title
                                elide: Text.ElideRight
                                color: row.asking ? (row.hot ? win.selText : Theme.pal.red) : row.hot ? win.selText : Theme.text
                                font { family: win.family; pixelSize: rowCol.r.kind === "calc" ? 17 : 13; weight: Theme.w(Font.Medium) }
                            }
                            Text {
                                visible: text !== ""
                                width: parent.width
                                text: rowCol.r.sub ?? ""
                                elide: rowCol.r.kind === "file" ? Text.ElideMiddle : Text.ElideRight
                                color: row.hot ? Qt.alpha(win.selText, 0.72) : Theme.textDim
                                font { family: win.family; weight: Theme.fontWeight; pixelSize: 11 }
                            }
                        }
                        Row {
                            id: tail
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            spacing: 8
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: SpotHistory.isPinned(rowCol.r.key)
                                text: "Pinned"
                                color: row.hot ? Qt.alpha(win.selText, 0.7) : Theme.textFaint
                                font { family: win.family; weight: Theme.fontWeight; pixelSize: 10 }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: rowCol.r.kind === "app" && DockPins.has(rowCol.r.entry.id)
                                text: "In Dock"
                                color: row.hot ? Qt.alpha(win.selText, 0.7) : Theme.textFaint
                                font { family: win.family; weight: Theme.fontWeight; pixelSize: 10 }
                            }
                            Rectangle {
                                visible: row.hot
                                width: 26; height: 20; radius: 5
                                color: row.hot ? Qt.alpha(win.selText, 0.16) : win.chip
                                Text { anchors.centerIn: parent; text: "↵"; color: row.hot ? win.selText : Theme.textDim; font { family: win.family; weight: Theme.fontWeight; pixelSize: 12 } }
                            }
                        }
                    }
                }
            }
        }

        // Footer: key hints
        Rectangle { y: card.height - win.footH - 1; width: parent.width; height: 1; color: Theme.hairline }
        Item {
            id: foot
            y: card.height - win.footH
            width: parent.width; height: win.footH
            readonly property bool history: win.q === ""
            component Key: Row {
                property string keys
                property string label
                spacing: 6
                anchors.verticalCenter: parent?.verticalCenter
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: kt.implicitWidth + 10; height: 17; radius: 4
                    color: win.chip
                    Text { id: kt; anchors.centerIn: parent; text: keys; color: Theme.textDim; font { family: win.family; weight: Theme.fontWeight; pixelSize: 10 } }
                }
                Text { anchors.verticalCenter: parent.verticalCenter; text: label; color: Theme.textFaint; font { family: win.family; weight: Theme.fontWeight; pixelSize: 11 } }
            }
            Row {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                spacing: 10
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: foot.history ? "History" : win.q === "?" ? "Help" : "Results"
                    color: Theme.textDim
                    font { family: win.family; pixelSize: 11; weight: Theme.w(Font.Medium) }
                }
                Key { keys: "↑↓"; label: "Navigate" }
                Key { keys: "↵"; label: "Open" }
                Key { keys: "Ctrl 1-9"; label: "Jump" }
                Key {
                    id: forget
                    visible: win.inHistory(win.rows[win.index])
                    keys: "⇧ Del"; label: "Remove"
                }
                Key {
                    visible: !!win.rows[win.index]?.key
                    keys: "Ctrl F"; label: SpotHistory.isPinned(win.rows[win.index]?.key) ? "Unpin" : "Pin"
                }
                Key {
                    visible: !forget.visible && win.rows[win.index]?.kind === "app"
                    keys: "Ctrl ↵"; label: DockPins.has(win.rows[win.index]?.entry?.id ?? "") ? "Remove from Dock" : "Keep in Dock"
                }
            }
            Row {
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                spacing: 14
                Key { visible: foot.history; keys: "?"; label: "Help" }
                Key { keys: "Esc"; label: "Close" }
            }
        }
    }
}
