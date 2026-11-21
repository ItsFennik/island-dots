import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import qs.services
import qs.components

// "Compact bar" layout (setting shellLayout = "compact"): a floating pill along the bottom, only
// as wide as what's in it — start, search, the Dock's apps, then tray, status, CPU/RAM and a
// two-line clock. Lives inside Bar.qml's surface (Bar sizes and centres the pill from
// implicitWidth), so popouts open upwards from here as usual.
Item {
    id: root
    required property var bar

    readonly property var s: Config.saved
    readonly property string family: Theme.font
    readonly property string glyphs: "JetBrainsMono Nerd Font"
    // App icon size (setting compactIconSize); every button is a square tile a little larger,
    // capped to the bar, so all items share one height and one centre line.
    readonly property int icon: Math.min(height - 10, s.compactIconSize ?? 28)
    readonly property int tile: Math.min(height - 6, icon + 8)
    readonly property int gap: 4                         // the one spacing used everywhere
    readonly property int edge: Math.round((height - tile) / 2)
    implicitWidth: Math.ceil(row.width + edge * 2)
    // Bar.qml's taskbar plumbing: no magnification here, so no headroom and no extra hit area.
    readonly property int magHead: 0
    readonly property Item magHit: null
    function isOpen(name) { return bar.expanded && bar.shown === name; }

    component Btn: MouseArea {
        id: b
        property bool active: false
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        height: root.tile
        y: Math.round((root.height - height) / 2)
        Rectangle {
            anchors.fill: parent
            radius: Math.round(root.tile * 0.24)
            color: b.active || b.pressed ? Qt.alpha(Theme.text, 0.16) : b.containsMouse ? Qt.alpha(Theme.text, 0.08) : "transparent"
        }
    }
    component Glyph: Btn {
        property alias text: g.text
        property int px: Math.round(root.tile * 0.44)
        width: root.tile
        Text { id: g; anchors.centerIn: parent; color: Theme.text; font { family: root.glyphs; pixelSize: parent.px; hintingPreference: Font.PreferNoHinting } }
    }
    component Sep: Item {
        width: 1 + root.gap * 2; height: root.height
        Rectangle { x: root.gap; width: 1; height: Math.round(root.tile * 0.6); anchors.verticalCenter: parent.verticalCenter; color: Qt.alpha(Theme.text, 0.15) }
    }

    // ── Apps (pinned first, then everything else that's open) ─────────
    readonly property var parked: Hyprland.toplevels.values
        .filter(h => h.workspace?.name === "special:browser" && h.wayland).map(h => h.wayland)
    readonly property var apps: {
        void DesktopEntries.applications.values; // fresh entry objects after a rescan
        const groups = {};
        for (const t of ToplevelManager.toplevels.values) {
            if (parked.includes(t)) continue;
            const e = DesktopEntries.heuristicLookup(t.appId);
            const k = e ? e.id : (t.appId || "?");
            (groups[k] = groups[k] ?? []).push(t);
        }
        const out = [];
        for (const id of DockPins.ids) {
            const e = DesktopEntries.byId(id) ?? DesktopEntries.heuristicLookup(id);
            if (!e) continue;
            out.push({ id: e.id, entry: e, name: e.name, icon: e.icon, wins: groups[e.id] ?? [] });
            delete groups[e.id];
        }
        for (const k of Object.keys(groups)) {
            const e = DesktopEntries.byId(k);
            out.push({ id: k, entry: e, name: e?.name ?? groups[k][0].title ?? k, icon: e?.icon ?? k, wins: groups[k] });
        }
        return out;
    }
    onAppsChanged: {
        if (launching && apps.some(a => a.id === launching && a.wins.length > 0)) launchStop.interval = 500;
        if (Popouts.ctxApp && root.isOpen("appctx")) Popouts.ctxApp = apps.find(a => a.id === Popouts.ctxApp.id) ?? null;
    }
    function activate(it) {
        if (it.wins.length) {
            const i = it.wins.findIndex(w => w.activated);
            const next = i < 0 ? it.wins[0] : it.wins[(i + 1) % it.wins.length];
            if (next !== it.wins[i]) next.activate();
        } else launch(it);
    }
    // Launch feedback (no headroom above the pill, so it stays inside the tile): the icon hops a
    // few px and the dash pulses until the first window shows (+ a short beat), or 4 s pass.
    function launch(it) {
        if (!it.entry) return;
        Apps.launch(it.entry, it.id);
        if (!(s.taskbarBounce ?? true)) return;
        launchStop.interval = 4000;
        launching = it.id; launchStop.restart();
    }
    property string launching: ""
    Timer { id: launchStop; interval: 4000; onTriggered: root.launching = "" }

    Row {
        id: row
        x: root.edge
        height: parent.height
        spacing: root.gap

        // Power: the shutdown menu (Lock, Sleep, Log Out, Restart, Shut Down); right-click: system menu.
        Glyph {
            id: start
            text: "\uf011"
            active: root.isOpen("power") || root.isOpen("system")
            onClicked: e => root.bar.openFrom(e.button === Qt.RightButton ? "system" : "power", start, "above")
        }
        // Launchpad
        Glyph {
            text: "\u{f003b}"
            active: Popouts.launchpad
            onClicked: Popouts.toggleLaunchpad()
        }
        Glyph { text: "󰍉"; active: Popouts.spotlight; onClicked: Popouts.toggleSpotlight() }   // 󰍉
        Workspaces {
            id: wsInd
            visible: (root.s.barWorkspaces ?? true) && known.length > 0
            screenName: root.bar.screen?.name ?? ""
            family: root.family
            fontPx: 11
            barH: root.height
        }

        Sep {}

        Repeater {
            model: root.apps
            Btn {
                id: app
                required property var modelData
                readonly property bool focused: modelData.wins.some(w => w.activated)
                readonly property bool launching: root.launching === modelData.id
                property real hop: 0
                width: root.tile
                SequentialAnimation {
                    running: app.launching
                    loops: Animation.Infinite
                    NumberAnimation { target: app; property: "hop"; to: Math.max(2, root.edge + 3); duration: 260; easing.type: Easing.OutQuad }
                    NumberAnimation { target: app; property: "hop"; to: 0; duration: 260; easing.type: Easing.InQuad }
                    PauseAnimation { duration: 120 }
                    onRunningChanged: if (!running) app.hop = 0
                }
                active: focused || (root.isOpen("appctx") && Popouts.ctxApp?.id === modelData.id)
                onClicked: e => {
                    if (e.button === Qt.MiddleButton) root.launch(modelData);
                    else if (e.button === Qt.RightButton) { Popouts.ctxApp = modelData; root.bar.openFrom("appctx", app, "above"); }
                    else root.activate(modelData);
                }
                Image {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.round((parent.height - height) / 2 - app.hop)
                    width: root.icon; height: root.icon
                    source: AppIcons.source(app.modelData.icon)
                    sourceSize { width: Math.max(48, root.icon * 2); height: Math.max(48, root.icon * 2) }
                    smooth: true; mipmap: true; asynchronous: true
                    opacity: app.pressed ? 0.6 : 1
                }
                // running: short grey dash; focused: longer accent dash; launching: pulsing accent dash
                Rectangle {
                    id: dash
                    visible: app.modelData.wins.length > 0 || app.launching
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 1 }
                    width: app.focused ? 14 : 5; height: 3; radius: 1.5
                    color: app.focused || app.launching ? Theme.accent : Qt.alpha(Theme.text, 0.55)
                    Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    SequentialAnimation on opacity {
                        running: app.launching
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 320; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 320; easing.type: Easing.InOutSine }
                        onRunningChanged: if (!running) dash.opacity = 1
                    }
                }
                Rectangle {
                    visible: app.containsMouse
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.top; bottomMargin: 10 }
                    width: nameText.implicitWidth + 16; height: 22; radius: 6
                    color: Theme.menuBg
                    border { width: 1; color: Theme.menuEdge }
                    Text { id: nameText; anchors.centerIn: parent; text: app.modelData.name; color: Theme.menuText; font { family: root.family; weight: Theme.fontWeight; pixelSize: 11 } }
                }
            }
        }

        Sep {}

        // ── Status ────────────────────────────────────────────────────
        Repeater {
            model: SystemTray.items
            Btn {
                id: trayItem
                required property SystemTrayItem modelData
                width: root.tile
                active: root.isOpen("tray") && Popouts.trayItem === modelData
                onClicked: e => {
                    if (e.button === Qt.MiddleButton) modelData.secondaryActivate();
                    else if (e.button === Qt.RightButton || modelData.onlyMenu) { if (modelData.hasMenu) { Popouts.trayItem = modelData; root.bar.openFrom("tray", trayItem, "above"); } }
                    else modelData.activate();
                }
                Image {
                    anchors.centerIn: parent
                    width: Math.round(root.tile * 0.5); height: width
                    sourceSize { width: 64; height: 64 }
                    source: trayItem.modelData.icon
                    opacity: trayItem.modelData.status === Status.Passive ? 0.5 : 1
                    asynchronous: true
                }
            }
        }
        Glyph { id: wifi; text: Net.glyph; active: root.isOpen("network"); onClicked: root.bar.openFrom("network", wifi, "above") }
        Glyph {
            id: vol
            text: Audio.glyph
            active: root.isOpen("sound")
            onClicked: e => e.button === Qt.MiddleButton ? Audio.toggleMute() : root.bar.openFrom("sound", vol, "above")
            WheelHandler { onWheel: e => Audio.nudge(e.angleDelta.y > 0 ? 0.03 : -0.03) }
        }
        // Control Centre: the same toggles panel as the menu bar's, opening upwards from here.
        Glyph {
            id: cc
            text: ""
            active: root.isOpen("controls") || root.isOpen("media")
            onClicked: root.bar.openFrom("controls", cc, "above")
        }

        // CPU / RAM, two lines (click: Control Centre)
        Btn {
            id: stats
            visible: root.s.compactStats ?? true
            width: statsCol.width + 14
            active: false
            onClicked: root.bar.openFrom("controls", cc, "above")
            Column {
                id: statsCol
                anchors.centerIn: parent
                spacing: 0
                component Stat: Row {
                    property string label
                    property real value
                    spacing: 6
                    Text { text: parent.label; color: Theme.textDim; font { family: root.family; pixelSize: 10; weight: Theme.w(Font.DemiBold) } }
                    Text { width: 26; horizontalAlignment: Text.AlignRight; text: Math.round(parent.value * 100) + "%"; color: Theme.text
                        font { family: root.family; weight: Theme.fontWeight; pixelSize: 10; features: { "tnum": 1 } } }
                }
                Stat { label: "CPU"; value: SysStats.cpu }
                Stat { label: "RAM"; value: SysStats.mem }
            }
        }

        // Time over date (click: notifications, like the clock on the other bars; right-click: weather)
        Btn {
            id: clock
            width: clockCol.width + 14
            active: root.isOpen("weather") || root.isOpen("notifs")
            onClicked: e => e.button === Qt.RightButton ? root.bar.openFrom("weather", clock, "above") : root.bar.openFrom("notifs", clock, "above")
            Column {
                id: clockCol
                anchors.centerIn: parent
                spacing: 0
                Text { anchors.right: parent.right; text: Qt.formatDateTime(clockSrc.date, (root.s.clock24h ?? true) ? "HH:mm" : "h:mm AP"); color: Theme.text
                    font { family: root.family; pixelSize: 11; weight: Theme.w(Font.Medium) } }
                Text { anchors.right: parent.right; text: Qt.formatDate(clockSrc.date, Qt.locale().dateFormat(Locale.ShortFormat)); color: Theme.text
                    font { family: root.family; weight: Theme.fontWeight; pixelSize: 11 } }
            }
            Rectangle {
                visible: Notifs.unread > 0
                anchors { right: parent.right; top: parent.top; margins: 3 }
                width: 6; height: 6; radius: 3
                color: Notifs.dnd ? Theme.textDim : "#ff453a"
            }
            SystemClock { id: clockSrc; precision: SystemClock.Minutes }
        }
    }
}
