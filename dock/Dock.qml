import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import qs.services

// The dock: a frosted shelf at the bottom with pinned apps, running apps, a divider and the
// trash. Icons magnify under the pointer, running apps get a dot, launching bounces the icon,
// hovering shows the name, right-click opens a menu (windows, Keep in Dock, Quit…).
//   qs -c island ipc call dock <toggle|autohide>
PanelWindow {
    id: win

    required property ShellScreen modelData
    screen: modelData

    readonly property var s: Config.saved
    readonly property int base: s.dockSize ?? 52
    readonly property real mag: (s.dockMagnify ?? true) ? (s.dockMagnifySize ?? 1.7) : 1
    readonly property bool autohide: s.dockAutohide ?? false
    readonly property int edge: s.dockMargin ?? 6           // gap under the shelf
    readonly property int pad: Math.round(base * 0.12)      // shelf padding around icons
    readonly property int spacing: Math.round(base * 0.08)
    readonly property int shelfH: base + pad * 2
    readonly property string iconTheme: "application-x-executable"

    readonly property bool wanted: (s.dock ?? true) && ((s.dockAllScreens ?? false) || Quickshell.screens.length === 0 || Quickshell.screens[0] === modelData)
    visible: wanted

    // Memory: the surface is only as wide as the fully magnified dock (plus room for the menu),
    // not the whole screen, and it's fixed so magnifying never reallocates the buffer.
    anchors.bottom: true
    implicitWidth: catchAll ? modelData.width : Math.min(modelData.width, Math.max(360, Math.ceil(baseTotal + base * (mag - 1) * 2.2 + pad * 2 + 120)))
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: autohide ? 0 : shelfH + edge
    implicitHeight: catchAll ? modelData.height : Math.ceil(base * mag) + pad + edge + 56 + (menu.open ? menu.height + 12 : 0)
    color: "transparent"
    mask: Region { item: hit; Region { item: win.catchAll ? catcher : null } }

    WlrLayershell.namespace: "island-dock"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // ── Items ─────────────────────────────────────────────────────────
    readonly property var pinned: DockPins.ids
    // Windows parked on special:browser (the warm hidden LibreWolf, see hypr/startup.lua)
    // don't count as running.
    readonly property var parked: Hyprland.toplevels.values
        .filter(h => h.workspace?.name === "special:browser" && h.wayland).map(h => h.wayland)
    readonly property var toplevels: ToplevelManager.toplevels.values.filter(t => !parked.includes(t))

    function entryFor(appId) { return DesktopEntries.heuristicLookup(appId) ?? null; }
    function keyFor(t) { const e = entryFor(t.appId); return e ? e.id : (t.appId || "?"); }

    readonly property var items: {
        const groups = {};
        for (const t of toplevels) {
            const k = keyFor(t);
            (groups[k] = groups[k] ?? []).push(t);
        }
        const out = [];
        out.push({ kind: "launcher", id: "island:launcher", name: "Launchpad", icon: "view-app-grid", wins: [] });
        for (const id of pinned) {
            const e = DesktopEntries.byId(id) ?? DesktopEntries.heuristicLookup(id);
            if (!e) continue;
            out.push({ kind: "app", id: e.id, pinId: id, entry: e, name: e.name, icon: e.icon, wins: groups[e.id] ?? [], pinned: true });
            delete groups[e.id];
        }
        for (const k of Object.keys(groups)) {
            const e = DesktopEntries.byId(k);
            out.push({ kind: "app", id: k, entry: e, name: e?.name ?? groups[k][0].title ?? k, icon: e?.icon ?? k, wins: groups[k], pinned: false });
        }
        out.push({ kind: "divider", id: "island:divider" });
        out.push({ kind: "trash", id: "island:trash", name: "Trash", icon: trashFull ? "user-trash-full" : "user-trash", wins: [] });
        return out;
    }

    function activate(it) {
        if (it.kind === "launcher") { Popouts.toggleLaunchpad(); return; }
        if (it.kind === "trash") { Quickshell.execDetached(["gio", "open", "trash:///"]); return; }
        if (it.wins.length > 0) {
            // Focus the app; clicking an app that's already focused cycles its windows.
            const i = it.wins.findIndex(w => w.activated);
            const next = i < 0 ? it.wins[0] : it.wins[(i + 1) % it.wins.length];
            if (next !== it.wins[i]) next.activate();
        } else if (it.entry) {
            launch(it);
        }
    }
    function launch(it) { if (!it.entry) return; Apps.launch(it.entry); bouncing = it.id; bounceStop.restart(); }
    function setPinned(id, on) { on ? DockPins.pin(id) : DockPins.unpin(id); }

    property string bouncing: ""
    Timer { id: bounceStop; interval: 2400; onTriggered: win.bouncing = "" }
    onToplevelsChanged: if (bouncing && items.some(i => i.id === bouncing && i.wins.length > 0)) bounceStop.interval = 700

    // Trash state (polled; Trash can't be watched without inotify on a directory).
    property bool trashFull: false
    Process {
        id: trashCheck
        command: ["sh", "-c", 'ls -A "${XDG_DATA_HOME:-$HOME/.local/share}/Trash/files" 2>/dev/null | head -c1']
        stdout: StdioCollector { onStreamFinished: win.trashFull = text.length > 0 }
    }
    Timer { interval: 30000; running: win.wanted; repeat: true; triggeredOnStart: true; onTriggered: trashCheck.running = true }

    // ── Hover / reveal ────────────────────────────────────────────────
    readonly property bool hovering: dockHover.hovered
    readonly property bool revealed: !autohide || hovering || menu.open || hideDelay.running
    onHoveringChanged: { if (!hovering && autohide) hideDelay.restart(); if (hovering) trashCheck.running = true; }
    Timer { id: hideDelay; interval: 600 }

    // Pointer x in window coordinates, and how strongly magnification applies (eases in/out).
    property real px: -1e4
    property real hoverAmt: hovering && !menu.open && dragFrom < 0 ? 1 : 0
    Behavior on hoverAmt { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    // Base (unmagnified) layout, so the pointer maps to stable positions while icons grow.
    readonly property var baseW: items.map(i => i.kind === "divider" ? 12 : base)
    readonly property real baseTotal: baseW.reduce((a, b) => a + b, 0) + spacing * (items.length - 1)
    function sizeAt(i) {
        if (items[i].kind === "divider") return 12;
        let x = (width - baseTotal) / 2;
        for (let k = 0; k < i; k++) x += baseW[k] + spacing;
        const d = Math.abs(px - (x + base / 2)), range = base * 2.6;
        const f = d < range ? (Math.cos(Math.PI * d / range) + 1) / 2 : 0;
        return base * (1 + (mag - 1) * f * hoverAmt);
    }

    // ── Drag to reorder ───────────────────────────────────────────────
    // Drag a pinned app to move it; drag a running (unpinned) app in among the pinned ones to pin
    // it there. Magnification is off while dragging, so every slot is exactly base + spacing wide.
    // Nothing is saved until the drop (one settings write).
    property int dragFrom: -1
    property int dragTo: -1
    property real dragDx: 0
    readonly property int pinnedCount: items.filter(i => i.pinned).length
    function slotCenter(i) { return (width - baseTotal) / 2 + i * (base + spacing) + base / 2; }
    function dragMove(from, dx) {
        if (dragFrom < 0) { dragFrom = from; menu.close(); }
        dragDx = dx;
        const maxT = items[from].pinned ? pinnedCount : Math.min(from, pinnedCount + 1);
        const t = Math.round((slotCenter(from) + dx - slotCenter(0)) / (base + spacing));
        dragTo = Math.max(1, Math.min(maxT, t));
    }
    function dragEnd() {
        const f = dragFrom, t = dragTo;
        dragFrom = -1; dragTo = -1; dragDx = 0;
        if (f < 0 || t === f) return;
        const it = items[f];
        if (!it.pinned && t > pinnedCount && f === pinnedCount + 1) return;   // didn't reach the pins
        // New order of the visible pins (by stored id); pins that don't resolve stay at the end.
        const vis = items.filter(i => i.pinned).map(i => i.pinId);
        const order = vis.filter(id => id !== it.pinId || !it.pinned);
        order.splice(t - 1, 0, it.pinned ? it.pinId : it.id);
        const rest = DockPins.ids.filter(id => !vis.includes(id) && !order.includes(id));
        Config.commit("dockPinned", order.concat(rest));
    }

    // ── Hit area (input mask) ─────────────────────────────────────────
    Item {
        id: hit
        anchors.horizontalCenter: parent.horizontalCenter
        y: menu.open ? 0 : win.revealed ? shelf.y - (win.hovering ? Math.ceil(win.base * (win.mag - 1)) + 40 : 0) : win.height - 2
        width: menu.open ? win.width : win.revealed ? shelf.width : Math.max(shelf.width, 200)
        height: win.height - y
    }
    HoverHandler { id: dockHover; onPointChanged: win.px = point.position.x }

    // ── Shelf ─────────────────────────────────────────────────────────
    Rectangle {
        id: shelf
        property real slide: win.revealed ? 0 : win.shelfH + win.edge + 4
        anchors.horizontalCenter: parent.horizontalCenter
        y: win.height - win.edge - height + slide
        Behavior on slide { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        width: row.width + win.pad * 2
        height: win.shelfH
        radius: Math.round(win.base * 0.36)
        color: Qt.alpha(Theme.bg, win.s.dockOpacity ?? 0.45)
        border { width: 1; color: Qt.alpha(Theme.text, 0.14) }
    }

    Row {
        id: row
        x: shelf.x + win.pad
        y: shelf.y + win.pad + win.base - height       // icons grow upwards from the shelf
        height: Math.ceil(win.base * win.mag)
        spacing: win.spacing

        Repeater {
            model: win.items
            delegate: Item {
                id: cell
                required property var modelData
                required property int index
                readonly property bool divider: modelData.kind === "divider"
                readonly property real size: win.sizeAt(index)
                width: size
                height: row.height
                z: index === win.dragFrom ? 10 : 0

                // Slide aside to make room for a dragged icon; the dragged one follows the pointer.
                readonly property real shift: {
                    const f = win.dragFrom, t = win.dragTo, pitch = win.base + win.spacing;
                    if (f < 0) return 0;
                    if (index === f) return win.dragDx;
                    if (f < t && index > f && index <= t) return -pitch;
                    if (t < f && index >= t && index < f) return pitch;
                    return 0;
                }
                transform: Translate {
                    x: cell.shift
                    Behavior on x { enabled: cell.index !== win.dragFrom; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }

                // Divider
                Rectangle {
                    visible: cell.divider
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height - win.base - win.pad * 0.3
                    width: 1; height: win.base + win.pad * 0.6
                    color: Qt.alpha(Theme.text, 0.22)
                }

                Image {
                    id: icon
                    visible: !cell.divider
                    width: cell.size; height: cell.size
                    y: parent.height - height - bounce.offset
                    source: cell.divider ? "" : Quickshell.iconPath(cell.modelData.icon ?? "", win.iconTheme)
                    sourceSize { width: Math.ceil(win.base * win.mag); height: Math.ceil(win.base * win.mag) }   // decoded once at max size
                    smooth: true; mipmap: true
                    asynchronous: true
                    opacity: area.pressed ? 0.6 : 1

                    QtObject {
                        id: bounce
                        property real offset: 0
                    }
                    SequentialAnimation {
                        running: win.bouncing === cell.modelData.id
                        loops: Animation.Infinite
                        NumberAnimation { target: bounce; property: "offset"; to: win.base * 0.45; duration: 300; easing.type: Easing.OutQuad }
                        NumberAnimation { target: bounce; property: "offset"; to: 0; duration: 300; easing.type: Easing.InQuad }
                        onRunningChanged: if (!running) bounce.offset = 0
                    }
                }

                // Running dot
                Rectangle {
                    visible: (cell.modelData.wins?.length ?? 0) > 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height + win.pad - 4 - 1
                    width: 4; height: 4; radius: 2
                    color: Qt.alpha(Theme.text, 0.85)
                }

                // Name bubble
                Rectangle {
                    visible: hover.hovered && !cell.divider && !menu.open
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: icon.y - height - 10
                    width: label.implicitWidth + 20; height: label.implicitHeight + 8
                    radius: 7
                    color: Qt.alpha(Theme.bg, 0.92)
                    border { width: 1; color: Qt.alpha(Theme.text, 0.14) }
                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: cell.modelData.name ?? ""
                        color: Theme.text
                        font { family: win.s.widgetFont || "Adwaita Sans"; pixelSize: 13; weight: Font.Medium }
                    }
                }

                HoverHandler { id: hover; enabled: !cell.divider }
                MouseArea {
                    id: area
                    enabled: !cell.divider
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: -win.pad }
                    height: cell.size + win.pad
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    // Window coords (not local: the cell itself moves while dragging).
                    property real startX: 0
                    property bool dragged: false
                    readonly property bool draggable: cell.modelData.kind === "app" && !!cell.modelData.entry
                    onPressed: e => { dragged = false; startX = mapToItem(win.contentItem, e.x, 0).x; }
                    onPositionChanged: e => {
                        if (!(pressedButtons & Qt.LeftButton) || !draggable) return;
                        const dx = mapToItem(win.contentItem, e.x, 0).x - startX;
                        if (!dragged && Math.abs(dx) < 8) return;
                        dragged = true;
                        win.dragMove(cell.index, dx);
                    }
                    onReleased: if (dragged) Qt.callLater(win.dragEnd)
                    onCanceled: if (dragged) Qt.callLater(win.dragEnd)
                    onClicked: e => {
                        if (dragged) return;
                        if (e.button === Qt.RightButton) menu.show(cell.modelData, cell);
                        else if (e.button === Qt.MiddleButton && cell.modelData.entry) win.launch(cell.modelData);
                        else win.activate(cell.modelData);
                    }
                }
            }
        }
    }

    // ── Right-click menu ──────────────────────────────────────────────
    Rectangle {
        id: menu
        property bool open: false
        property var item: null
        property real cx: 0
        function show(it, cellItem) {
            item = it;
            cx = cellItem.mapToItem(win.contentItem, cellItem.width / 2, 0).x - win.width / 2;   // from centre: the window may widen
            open = true;
        }
        function close() { open = false; }
        onOpenChanged: if (!open) item = null

        readonly property var actions: {
            const it = item;
            if (!it) return [];
            const out = [];
            if (it.kind === "trash") {
                out.push({ text: "Open", f: () => win.activate(it) });
                out.push({ sep: true });
                out.push({ text: "Empty Trash", f: () => Quickshell.execDetached(["sh", "-c", "gio trash --empty && true"]), off: !win.trashFull });
                return out;
            }
            if (it.kind === "launcher") {
                out.push({ text: "Open Launchpad", f: () => win.activate(it) });
                out.push({ text: "Spotlight Search", f: () => Popouts.openOverlay("spotlight") });
                out.push({ text: "System Settings…", f: () => Popouts.openSettings("") });
                return out;
            }
            for (const w of it.wins) out.push({ text: w.title || it.name, f: () => w.activate(), check: w.activated });
            if (it.wins.length) out.push({ sep: true });
            if (it.entry) {
                for (const a of it.entry.actions ?? []) out.push({ text: a.name, f: () => a.execute() });
                if ((it.entry.actions ?? []).length) out.push({ sep: true });
            }
            if (it.entry) out.push({ text: it.pinned ? "Remove from Dock" : "Keep in Dock", f: () => win.setPinned(it.id, !it.pinned) });
            if (it.entry) out.push({ text: it.wins.length ? "New Window" : "Open", f: () => win.launch(it) });
            if (it.wins.length) { out.push({ sep: true }); out.push({ text: "Quit", f: () => it.wins.forEach(w => w.close()) }); }
            return out;
        }

        visible: open
        x: Math.max(8, Math.min(win.width - width - 8, win.width / 2 + cx - width / 2))
        y: shelf.y - height - 14
        width: Math.min(320, Math.max(180, col.implicitWidth + 12))
        height: col.implicitHeight + 10
        radius: 12
        color: Qt.alpha(Theme.bg, 0.96)
        border { width: 1; color: Qt.alpha(Theme.text, 0.14) }

        Column {
            id: col
            x: 5; y: 5
            width: parent.width - 10
            Repeater {
                model: menu.actions
                delegate: Item {
                    required property var modelData
                    width: col.width
                    height: modelData.sep ? 9 : 26
                    Rectangle { visible: !!parent.modelData.sep; anchors.centerIn: parent; width: parent.width - 16; height: 1; color: Theme.hairline }
                    MouseArea {
                        id: ma
                        visible: !parent.modelData.sep
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !parent.modelData.off
                        onClicked: { const f = parent.modelData.f; f(); menu.close(); }
                        Rectangle { anchors.fill: parent; radius: 6; color: ma.containsMouse ? Theme.accent : "transparent" }
                        Text {
                            anchors { left: parent.left; leftMargin: 22; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            text: parent.parent.modelData.text ?? ""
                            elide: Text.ElideRight
                            color: !ma.enabled ? Theme.textFaint : ma.containsMouse ? Theme.onAccent : Theme.text
                            font { family: win.s.widgetFont || "Adwaita Sans"; pixelSize: 13 }
                        }
                        Text {
                            visible: !!parent.parent.modelData.check
                            anchors { left: parent.left; leftMargin: 7; verticalCenter: parent.verticalCenter }
                            text: "✓"
                            color: ma.containsMouse ? Theme.onAccent : Theme.text
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }
    }

    // Clicking anywhere else closes the menu.
    // Armed a beat after opening: activating the grab in the same frame the surface grows makes
    // Hyprland clear it straight away (the menu would close the instant it opened).
    property bool grabArmed: false
    Connections { target: menu; function onOpenChanged() { win.grabArmed = false; if (menu.open) arm.restart(); } }
    Timer { id: arm; interval: 80; onTriggered: win.grabArmed = menu.open }
    HyprlandFocusGrab { windows: [win]; active: Compositor.focusGrab && win.grabArmed; onCleared: menu.close() }
    // Elsewhere: the dock covers the screen with a transparent catcher while the menu is open.
    readonly property bool catchAll: !Compositor.focusGrab && menu.open
    MouseArea {
        id: catcher
        anchors.fill: parent
        z: -1
        visible: win.catchAll
        acceptedButtons: Qt.AllButtons
        onPressed: menu.close()
    }
}
