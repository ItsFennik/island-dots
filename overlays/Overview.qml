import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services

// Overview, niri-style: a fixed set of workspaces (setting overviewWorkspaces, default 10) zoomed out to half size and stacked vertically over a
// dark backdrop, the focused one centred, each showing its windows where they really are.
//   click a window         focus it (switches workspace)      middle-click   close it
//   drag a window          drop it on another workspace to move it there
//   click a workspace      go to it                           wheel / ↑↓      scroll workspaces
//   ←→ pick a window, Enter go, 1–9 jump, Esc / click the backdrop to close
// Windows are live (ext-image-capture) on the visible cards — the selected workspace and the
// ones peeking in above and below; the rest keep a still from opening. A window the
// compositor can't capture shows its app icon instead.
// Only exists while open. Open/close fade is the compositor's (layer rule island-overview).
PanelWindow {
    id: win

    readonly property real sw: screen?.width ?? 1920
    readonly property real sh: screen?.height ?? 1080
    readonly property real zoom: 0.5                    // niri's default overview zoom
    readonly property real cardW: Math.round(sw * zoom)
    readonly property real cardH: Math.round(sh * zoom)
    readonly property real gap: Math.round(sh * 0.045)
    readonly property string family: Config.saved.widgetFont || "Adwaita Sans"

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "island-overview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // [{ id, ws, windows: [{ id, app, title, x, y, w, h, focused, tl }] }]
    property var spaces: []
    property int activeWs: -1
    property int sel: 0                 // selected workspace (index into spaces)
    property int winSel: -1             // selected window in it (keyboard), -1 = none
    property bool ready: false

    function close() { Popouts.closeOverlays(); }
    function goWorkspace(ws) { Compositor.focusWorkspace(ws); close(); }
    function focusWindow(w, ws) {
        if (w.tl) w.tl.activate();
        else Compositor.focusWorkspace(ws);
        close();
    }
    function select(i) {
        sel = Math.max(0, Math.min(spaces.length - 1, i));
        winSel = -1;
    }

    // ── Data ──────────────────────────────────────────────────────────
    // Mango: mmsg; Hyprland: hyprctl. Anything else: every window on one card, in a grid.
    Process {
        id: query
        command: Compositor.mango
            ? ["sh", "-c", "mmsg get all-clients; echo; echo ---; mmsg get all-tags"]
            : Compositor.hyprland
            ? ["sh", "-c", "hyprctl -j clients; echo ---; hyprctl -j activeworkspace"]
            : ["true"]
        stdout: StdioCollector { onStreamFinished: win.parse(text) }
        Component.onCompleted: running = true
    }
    Timer { id: requery; interval: 180; onTriggered: query.running = true }

    function parse(out) {
        const parts = out.split("\n---\n");
        let wins = [], active = -1, limit = 0;
        const ox = win.screen?.x ?? 0, oy = win.screen?.y ?? 0, mon = win.screen?.name ?? "";
        try {
            if (Compositor.mango) {
                for (const c of JSON.parse(parts[0]).clients ?? []) {
                    if (c.monitor !== mon || c.is_scratchpad || c.is_minimized || !(c.tags?.length)) continue;
                    wins.push({ id: c.id, app: c.appid, title: c.title, ws: c.tags[0],
                                x: c.x - ox, y: c.y - oy, w: c.width, h: c.height,
                                focused: c.is_focused, floating: c.is_floating });
                }
                for (const m of JSON.parse(parts[1]).all_tags ?? []) if (m.monitor === mon) {
                    limit = m.tags.length;           // Mango's tag count (9, fixed in Mango)
                    for (const t of m.tags) if (t.is_active) { active = t.index; break; }
                }
            } else if (Compositor.hyprland) {
                const aw = JSON.parse(parts[1]);
                active = aw.id;
                for (const c of JSON.parse(parts[0])) {
                    if (!c.mapped || c.hidden || c.workspace.id < 1 || c.workspace.id !== Math.floor(c.workspace.id)) continue;
                    if (c.monitor !== aw.monitorID) continue;
                    wins.push({ id: c.address, app: c.class, title: c.title, ws: c.workspace.id,
                                x: c.at[0] - ox, y: c.at[1] - oy, w: c.size[0], h: c.size[1],
                                focused: c.focusHistoryID === 0, floating: c.floating });
                }
            }
        } catch (e) { console.warn("overview:", e); }

        if (!Compositor.mango && !Compositor.hyprland) {
            // No geometry: lay the windows out in a grid on one workspace.
            const tls = ToplevelManager.toplevels.values;
            const cols = Math.ceil(Math.sqrt(tls.length || 1)), rows = Math.ceil((tls.length || 1) / cols);
            const cw = sw / cols, ch = sh / rows;
            wins = tls.map((t, i) => ({ id: i, app: t.appId, title: t.title, ws: 1, tl: t, focused: t.activated,
                x: (i % cols) * cw + cw * 0.06, y: Math.floor(i / cols) * ch + ch * 0.06, w: cw * 0.88, h: ch * 0.88 }));
            active = 1;
        } else {
            // Pair each window with its foreign-toplevel handle (for activate/close/capture).
            const pool = ToplevelManager.toplevels.values.slice();
            for (const w of wins) {
                let i = pool.findIndex(t => t.appId === w.app && t.title === w.title);
                if (i < 0) i = pool.findIndex(t => t.appId === w.app);
                w.tl = i >= 0 ? pool.splice(i, 1)[0] : null;
            }
        }

        // A fixed set of workspaces: 1…overviewWorkspaces (default 10), capped at what the
        // compositor has. Windows or the active workspace beyond that are still shown.
        const ids = {};
        let count = Math.max(1, Config.saved.overviewWorkspaces ?? 10);
        if (limit > 0) count = Math.min(count, limit);
        if (!Compositor.mango && !Compositor.hyprland) count = 1;
        for (let n = 1; n <= count; n++) ids[n] = true;
        for (const w of wins) ids[w.ws] = true;
        if (active > 0) ids[active] = true;
        const list = Object.keys(ids).map(Number).sort((a, b) => a - b).map(n => ({
            ws: n,
            windows: wins.filter(w => w.ws === n)
                         .sort((a, b) => (a.floating - b.floating) || (a.y - b.y) || (a.x - b.x))
        }));

        const keep = spaces[sel]?.ws;
        activeWs = active;
        spaces = list;
        const at = list.findIndex(s => s.ws === (ready ? keep : active));
        sel = Math.max(0, at);
        winSel = -1;
        ready = true;
    }

    // ── Wallpaper inside every card (video wallpapers use their cached poster) ──
    FileView {
        id: wpState
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/island/wallpaper"
    }
    readonly property string wallpaper: {
        const p = (wpState.text() || "").trim();
        if (!p) return "";
        if (/\.(mp4|webm|mkv|mov|avi|gif)$/i.test(p))
            return "file://" + Quickshell.env("HOME") + "/.cache/island/video-thumbs/" + Qt.md5(p) + ".jpg";
        return "file://" + p;
    }

    // ── Backdrop ──────────────────────────────────────────────────────
    Rectangle { anchors.fill: parent; color: Qt.rgba(0.07, 0.07, 0.08, 0.92) }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: win.close()
    }
    // Wheel: one workspace per notch (touchpads accumulate).
    property real wheelAcc: 0
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: e => {
            win.wheelAcc += e.angleDelta.y;
            while (Math.abs(win.wheelAcc) >= 120) {
                win.select(win.sel + (win.wheelAcc > 0 ? -1 : 1));
                win.wheelAcc -= 120 * Math.sign(win.wheelAcc);
            }
        }
    }

    // ── Keyboard ──────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: e => {
            const s = win.spaces[win.sel];
            const n = s?.windows.length ?? 0;
            if (e.key === Qt.Key_Escape) win.close();
            else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) win.select(win.sel - 1);
            else if (e.key === Qt.Key_Down || e.key === Qt.Key_J) win.select(win.sel + 1);
            else if ((e.key === Qt.Key_Right || e.key === Qt.Key_L || e.key === Qt.Key_Tab) && n)
                win.winSel = (win.winSel + 1) % n;
            else if ((e.key === Qt.Key_Left || e.key === Qt.Key_H || e.key === Qt.Key_Backtab) && n)
                win.winSel = win.winSel <= 0 ? n - 1 : win.winSel - 1;
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) {
                if (s && win.winSel >= 0) win.focusWindow(s.windows[win.winSel], s.ws);
                else if (s) win.goWorkspace(s.ws);
            } else if (e.key === Qt.Key_Q && win.winSel >= 0 && s) {
                s.windows[win.winSel].tl?.close(); requery.restart();
            } else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) win.goWorkspace(e.key - Qt.Key_0);
            else return;
            e.accepted = true;
        }
    }

    // ── Workspace strip ───────────────────────────────────────────────
    Item {
        id: stack
        x: (win.sw - win.cardW) / 2
        width: win.cardW
        height: win.spaces.length * (win.cardH + win.gap)
        y: win.sh / 2 - (win.sel * (win.cardH + win.gap) + win.cardH / 2)
        visible: win.ready
        // Cache while it slides: the CPU renderer redraws a cached layer far faster.
        layer.enabled: slide.running
        Behavior on y { enabled: win.ready; NumberAnimation { id: slide; duration: 220; easing.type: Easing.OutCubic } }

        Repeater {
            model: win.spaces
            delegate: Item {
                id: card
                required property var modelData
                required property int index
                readonly property bool current: index === win.sel
                readonly property bool active: modelData.ws === win.activeWs
                property bool dragging: false
                x: 0
                y: index * (win.cardH + win.gap)
                width: win.cardW
                height: win.cardH
                z: dragging ? 10 : 0

                // Soft shadow
                Rectangle { anchors.fill: parent; anchors.margins: -6; radius: 14; color: Qt.rgba(0, 0, 0, 0.18) }
                Rectangle { anchors.fill: parent; anchors.margins: -2; radius: 8; color: Qt.rgba(0, 0, 0, 0.3) }

                Rectangle { anchors.fill: parent; color: "#1b1b1f" }
                Image {
                    anchors.fill: parent
                    source: win.wallpaper
                    sourceSize: Qt.size(win.cardW, win.cardH)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                }
                Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, card.current ? 0 : 0.28) }

                MouseArea {
                    anchors.fill: parent
                    onClicked: win.goWorkspace(card.modelData.ws)
                }

                // Workspace number, left of the card
                Text {
                    anchors { right: parent.left; rightMargin: 18; top: parent.top }
                    text: card.modelData.ws
                    color: card.active ? Theme.accent : Qt.rgba(1, 1, 1, card.current ? 0.85 : 0.4)
                    font { family: win.family; pixelSize: 22; weight: Font.DemiBold }
                }
                Text {
                    anchors.centerIn: parent
                    visible: !card.modelData.windows.length
                    text: "Empty"
                    color: Qt.rgba(1, 1, 1, 0.45)
                    font { family: win.family; pixelSize: 15 }
                }

                Repeater {
                    model: card.modelData.windows
                    delegate: Item {
                        id: thumb
                        required property var modelData
                        required property int index
                        readonly property var w: modelData
                        readonly property bool picked: card.current && win.winSel === index
                        readonly property bool hot: hover.containsMouse || picked || hover.dragged
                        x: w.x * win.zoom
                        y: w.y * win.zoom
                        width: Math.max(24, w.w * win.zoom)
                        height: Math.max(24, w.h * win.zoom)
                        z: hover.dragged ? 5 : (w.floating ? 2 : 1)
                        transform: Translate { x: hover.dx; y: hover.dy }

                        Rectangle { anchors.fill: parent; color: Qt.rgba(0.1, 0.1, 0.12, 0.92) }
                        // App icon (hidden behind the picture once it's captured)
                        Image {
                            anchors.centerIn: parent
                            readonly property int s: Math.min(64, Math.min(parent.width, parent.height) * 0.4)
                            width: s; height: s
                            sourceSize: Qt.size(s, s)
                            visible: !shot.hasContent
                            source: AppIcons.source(DesktopEntries.heuristicLookup(thumb.w.app)?.icon ?? thumb.w.app)
                        }
                        ScreencopyView {
                            id: shot
                            anchors.fill: parent
                            captureSource: thumb.w.tl ?? null
                            // Live only on the cards you can see (the selected one and the two
                            // peeking in above/below); further ones keep their opening frame.
                            live: Math.abs(card.index - win.sel) <= 1
                            constraintSize: Qt.size(parent.width, parent.height)
                        }

                        // Focus ring: accent for the focused window, white for hover/keyboard pick
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -2
                            color: "transparent"
                            border.width: 2
                            border.color: thumb.hot ? Qt.rgba(1, 1, 1, 0.9) : Theme.accent
                            visible: thumb.hot || (thumb.w.focused && card.active)
                        }

                        // Title under the hovered window
                        Rectangle {
                            visible: thumb.hot && !hover.dragged
                            anchors { horizontalCenter: parent.horizontalCenter; top: parent.bottom; topMargin: 8 }
                            width: Math.min(label.implicitWidth + 20, win.cardW)
                            height: 26; radius: 13
                            color: Qt.rgba(0.12, 0.12, 0.14, 0.95)
                            border { width: 1; color: Qt.rgba(1, 1, 1, 0.12) }
                            Text {
                                id: label
                                anchors.centerIn: parent
                                width: Math.min(implicitWidth, win.cardW - 20)
                                elide: Text.ElideRight
                                text: thumb.w.title || thumb.w.app
                                color: "white"
                                font { family: win.family; pixelSize: 13 }
                            }
                        }

                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            cursorShape: dragged ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                            property real px: 0
                            property real py: 0
                            property real dx: 0
                            property real dy: 0
                            property bool dragged: false
                            // In stack coordinates, which the drag offset itself doesn't move.
                            onPressed: e => { const p = mapToItem(stack, e.x, e.y); px = p.x; py = p.y; }
                            onPositionChanged: e => {
                                if (!pressed || pressedButtons !== Qt.LeftButton) return;
                                const p = mapToItem(stack, e.x, e.y);
                                if (!dragged && Math.hypot(p.x - px, p.y - py) < 6) return;
                                dragged = true; card.dragging = true;
                                dx = p.x - px; dy = p.y - py;
                            }
                            onReleased: e => {
                                if (!dragged) return;
                                // Workspace under the pointer
                                const p = mapToItem(stack, e.x, e.y);
                                const i = Math.floor((p.y + win.gap / 2) / (win.cardH + win.gap));
                                const target = win.spaces[i];
                                dragged = false; card.dragging = false; dx = 0; dy = 0;
                                if (target && target.ws !== card.modelData.ws && p.x > -win.gap && p.x < win.cardW + win.gap) {
                                    Compositor.moveWindow(thumb.w, target.ws);
                                    requery.restart();
                                }
                            }
                            onClicked: e => {
                                if (e.button === Qt.MiddleButton) { thumb.w.tl?.close(); requery.restart(); }
                                else win.focusWindow(thumb.w, card.modelData.ws);
                            }
                        }
                    }
                }
            }
        }
    }

    // Hint along the bottom
    Text {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 18 }
        text: "Click to focus  ·  Drag to another workspace to move  ·  Middle-click to close  ·  Esc"
        color: Qt.rgba(1, 1, 1, 0.35)
        font { family: win.family; pixelSize: 12 }
    }
}
