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
    readonly property int tile: Math.round(height * 0.72)
    readonly property int icon: Math.round(tile * 0.78)
    implicitWidth: Math.ceil(row.width + 12)
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
        anchors.verticalCenter: parent.verticalCenter
        Rectangle {
            anchors.fill: parent
            radius: 7
            color: b.active || b.pressed ? Qt.alpha(Theme.text, 0.16) : b.containsMouse ? Qt.alpha(Theme.text, 0.08) : "transparent"
        }
    }
    component Glyph: Btn {
        property alias text: g.text
        property int px: 15
        width: 28; height: root.tile
        Text { id: g; anchors.centerIn: parent; color: Theme.text; font { family: root.glyphs; pixelSize: parent.px; hintingPreference: Font.PreferNoHinting } }
    }
    component Sep: Rectangle { width: 1; height: root.tile * 0.6; anchors.verticalCenter: parent.verticalCenter; color: Qt.alpha(Theme.text, 0.15) }

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
    function activate(it) {
        if (it.wins.length) {
            const i = it.wins.findIndex(w => w.activated);
            const next = i < 0 ? it.wins[0] : it.wins[(i + 1) % it.wins.length];
            if (next !== it.wins[i]) next.activate();
        } else if (it.entry) Apps.launch(it.entry, it.id);
    }

    Row {
        id: row
        x: 6
        height: parent.height
        spacing: 2

        // Start: Launchpad on click, logo menu on right-click.
        Btn {
            id: start
            width: root.tile; height: root.tile
            // Row ignored the inherited verticalCenter anchor (tile sat at y=0), so place it explicitly.
            anchors.verticalCenter: undefined
            y: Math.round((parent.height - height) / 2)
            active: Popouts.launchpad || root.isOpen("system")
            onClicked: e => e.button === Qt.RightButton ? root.bar.openFrom("system", start, "left") : Popouts.toggleLaunchpad()
            TextMetrics { id: logoInk; font: logoText.font; text: logoText.text }
            Text {
                id: logoText
                readonly property rect ink: logoInk.tightBoundingRect
                x: Math.round((parent.width - ink.width) / 2 - ink.x)
                y: Math.round((parent.height - ink.height) / 2 - ink.y - baselineOffset)
                text: osInfo.glyph
                color: Theme.accent
                font { family: root.glyphs; pixelSize: Math.round(root.tile * 0.58); hintingPreference: Font.PreferNoHinting }
            }
        }
        Glyph { text: "󰍉"; px: 17; width: root.tile; active: Popouts.spotlight; onClicked: Popouts.toggleSpotlight() }   // 󰍉
        Workspaces {
            id: wsInd
            visible: (root.s.barWorkspaces ?? true) && known.length > 0
            screenName: root.bar.screen?.name ?? ""
            family: root.family
            fontPx: 11
            barH: root.height
        }

        Item { width: 4; height: 1 }

        Repeater {
            model: root.apps
            Btn {
                id: app
                required property var modelData
                readonly property bool focused: modelData.wins.some(w => w.activated)
                width: root.tile; height: root.tile
                active: focused
                onClicked: e => {
                    if (e.button === Qt.MiddleButton) { if (modelData.entry) Apps.launch(modelData.entry, modelData.id); }
                    else if (e.button === Qt.RightButton) DockPins.toggle(modelData.id);
                    else root.activate(modelData);
                }
                Image {
                    anchors.centerIn: parent
                    width: root.icon; height: root.icon
                    source: AppIcons.source(app.modelData.icon)
                    sourceSize { width: Math.max(48, root.icon * 2); height: Math.max(48, root.icon * 2) }
                    smooth: true; mipmap: true; asynchronous: true
                    opacity: app.pressed ? 0.6 : 1
                }
                // running: short grey dash; focused: longer accent dash
                Rectangle {
                    visible: app.modelData.wins.length > 0
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 1 }
                    width: app.focused ? 14 : 5; height: 3; radius: 1.5
                    color: app.focused ? Theme.accent : Qt.alpha(Theme.text, 0.55)
                    Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                }
                Rectangle {
                    visible: app.containsMouse
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.top; bottomMargin: 10 }
                    width: nameText.implicitWidth + 16; height: 22; radius: 6
                    color: Theme.menuBg
                    border { width: 1; color: Theme.menuEdge }
                    Text { id: nameText; anchors.centerIn: parent; text: app.modelData.name; color: Theme.menuText; font { family: root.family; pixelSize: 11 } }
                }
            }
        }

        Item { width: 4; height: 1 }
        Sep {}
        Item { width: 2; height: 1 }

        // ── Status ────────────────────────────────────────────────────
        Repeater {
            model: SystemTray.items
            Btn {
                id: trayItem
                required property SystemTrayItem modelData
                width: 26; height: root.tile
                active: root.isOpen("tray") && Popouts.trayItem === modelData
                onClicked: e => {
                    if (e.button === Qt.MiddleButton) modelData.secondaryActivate();
                    else if (e.button === Qt.RightButton || modelData.onlyMenu) { if (modelData.hasMenu) { Popouts.trayItem = modelData; root.bar.openFrom("tray", trayItem, "right"); } }
                    else modelData.activate();
                }
                Image {
                    anchors.centerIn: parent
                    width: 16; height: 16
                    sourceSize { width: 32; height: 32 }
                    source: trayItem.modelData.icon
                    opacity: trayItem.modelData.status === Status.Passive ? 0.5 : 1
                    asynchronous: true
                }
            }
        }
        Glyph { id: wifi; text: Net.glyph; active: root.isOpen("network"); onClicked: root.bar.openFrom("network", wifi, "right") }
        Glyph {
            id: vol
            text: Audio.glyph
            active: root.isOpen("sound")
            onClicked: e => e.button === Qt.MiddleButton ? Audio.toggleMute() : root.bar.openFrom("sound", vol, "right")
            WheelHandler { onWheel: e => Audio.nudge(e.angleDelta.y > 0 ? 0.03 : -0.03) }
        }

        // CPU / RAM, two lines (click: Control Centre)
        Btn {
            id: stats
            visible: root.s.compactStats ?? true
            width: statsCol.width + 14; height: root.tile
            active: root.isOpen("controls")
            onClicked: root.bar.openFrom("controls", stats, "right")
            Column {
                id: statsCol
                anchors.centerIn: parent
                spacing: 0
                component Stat: Row {
                    property string label
                    property real value
                    spacing: 5
                    Text { width: 26; text: parent.label; color: Theme.textDim; font { family: root.family; pixelSize: 10; weight: Font.DemiBold } }
                    Text { width: 28; horizontalAlignment: Text.AlignRight; text: Math.round(parent.value * 100) + "%"; color: Theme.text
                        font { family: root.family; pixelSize: 10; features: { "tnum": 1 } } }
                }
                Stat { label: "CPU"; value: SysStats.cpu }
                Stat { label: "RAM"; value: SysStats.mem }
            }
        }

        // Time over date (click: weather; middle-click: notifications)
        Btn {
            id: clock
            width: clockCol.width + 16; height: root.tile
            active: root.isOpen("weather") || root.isOpen("notifs")
            onClicked: e => e.button === Qt.MiddleButton || e.button === Qt.RightButton ? root.bar.openFrom("notifs", clock, "right") : root.bar.openFrom("weather", clock, "right")
            Column {
                id: clockCol
                anchors.centerIn: parent
                spacing: 0
                Text { anchors.right: parent.right; text: Qt.formatDateTime(clockSrc.date, (root.s.clock24h ?? true) ? "HH:mm" : "h:mm AP"); color: Theme.text
                    font { family: root.family; pixelSize: 11; weight: Font.Medium } }
                Text { anchors.right: parent.right; text: Qt.formatDate(clockSrc.date, Qt.locale().dateFormat(Locale.ShortFormat)); color: Theme.text
                    font { family: root.family; pixelSize: 11 } }
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

    FileView {
        id: osInfo
        path: "/etc/os-release"
        readonly property string id_: (/^ID=("?)([^"\n]*)\1/m.exec(text() ?? "") ?? [])[2] ?? ""
        readonly property string glyph: ({ fedora: "", arch: "", cachyos: "", endeavouros: "", manjaro: "",
            debian: "", ubuntu: "", nixos: "", opensuse: "", "opensuse-tumbleweed": "", gentoo: "", void: "" })[id_] ?? ""
    }
}
