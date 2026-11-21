import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Bluetooth
import qs.services
import qs.components

// "Bottom bar" layout (setting shellLayout = "taskbar"): one floating glass bar along the bottom.
// Left: logo menu + now playing. Middle: the Dock's apps. Right: tray, Bluetooth / Wi-Fi / sound /
// weather, Spotlight, notifications, Control Centre (a battery ring on laptops) and the clock —
// each opens its own menu and has a hover label. Lives inside Bar.qml's surface, so every popout
// opens (upwards) from here as usual.
Item {
    id: root
    required property var bar                     // the Bar window (openFrom, shown, expanded)

    readonly property var s: Config.saved
    readonly property string family: Theme.font
    readonly property string glyphs: "JetBrainsMono Nerd Font"
    readonly property int tile: Math.round(height * 0.74)
    function isOpen(name) { return bar.expanded && bar.shown === name; }

    // A round-cornered hover/press highlight used by every button here. Set `tip` (and
    // optionally `tipSub`) to show a small label above the bar on hover — the right-hand status
    // icons use it to say what they are and what state they're in.
    component Btn: MouseArea {
        id: b
        property bool active: false
        property string tip: ""
        property string tipSub: ""
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        Rectangle {
            anchors.fill: parent
            radius: 9
            color: b.active ? Qt.alpha(Theme.text, 0.18) : b.containsMouse ? Qt.alpha(Theme.text, 0.08) : "transparent"
        }
        Rectangle {
            id: tipBox
            visible: b.tip !== "" && b.containsMouse && !root.bar.expanded
            width: Math.min(270, Math.max(tipTitle.implicitWidth, tipSubText.implicitWidth) + 18)
            height: tipCol.implicitHeight + 10
            // Keep the bubble on screen for the icons at the far right.
            x: {
                const abs = (b.parent ? b.parent.x : 0) + b.x;
                return Math.max(4 - abs, Math.min(root.width - width - 4 - abs, b.width / 2 - width / 2));
            }
            y: -height - 9
            radius: 7
            color: Theme.menuBg
            border { width: 1; color: Theme.menuEdge }
            z: 1000
            Column {
                id: tipCol
                anchors.centerIn: parent
                spacing: 0
                Text {
                    id: tipTitle
                    width: Math.min(252, implicitWidth)
                    text: b.tip
                    elide: Text.ElideRight
                    color: Theme.menuText
                    font { family: root.family; pixelSize: 11; weight: Theme.w(Font.DemiBold) }
                }
                Text {
                    id: tipSubText
                    visible: b.tipSub !== ""
                    width: Math.min(252, implicitWidth)
                    text: b.tipSub
                    elide: Text.ElideRight
                    color: Qt.alpha(Theme.menuText, 0.6)
                    font { family: root.family; weight: Theme.fontWeight; pixelSize: 10 }
                }
            }
        }
    }
    component Glyph: Btn {
        property alias text: g.text
        property int px: 15
        width: 30; height: root.height - 12
        anchors.verticalCenter: parent.verticalCenter
        Text { id: g; anchors.centerIn: parent; color: Theme.text; font { family: root.glyphs; pixelSize: parent.px; hintingPreference: Font.PreferNoHinting } }
    }

    // ── Left: logo + now playing ──────────────────────────────────────
    Row {
        id: left
        anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
        spacing: 10

        Btn {
            id: logo
            width: root.tile; height: root.tile
            // Row ignored the inherited verticalCenter anchor (tile sat at y=0), so place it explicitly.
            anchors.verticalCenter: undefined
            y: Math.round((left.height - height) / 2)
            active: root.isOpen("system")
            onClicked: root.bar.openFrom("system", logo, "left")
            // Nerd Font logos sit off-centre in their text box, so centre the glyph's ink instead.
            TextMetrics { id: logoInk; font: logoText.font; text: logoText.text }
            Text {
                id: logoText
                readonly property rect ink: logoInk.tightBoundingRect
                x: Math.round((parent.width - ink.width) / 2 - ink.x)
                y: Math.round((parent.height - ink.height) / 2 - ink.y - baselineOffset)
                text: osInfo.glyph
                color: Theme.text
                font { family: root.glyphs; pixelSize: Math.round(root.tile * 0.6); hintingPreference: Font.PreferNoHinting }
            }
        }

        // Workspaces (same setting and style as the menu bar's indicator).
        Workspaces {
            id: wsInd
            visible: (root.s.barWorkspaces ?? true) && known.length > 0
            screenName: root.bar.screen?.name ?? ""
            family: root.family
            fontPx: 12
            barH: root.height
        }

        Rectangle { visible: media.visible; width: 1; height: root.tile * 0.7; anchors.verticalCenter: parent.verticalCenter; color: Qt.alpha(Theme.text, 0.15) }

        Item {
            id: media
            visible: !!Media.player
            width: visible ? mediaRow.width : 0
            height: root.height
            readonly property var p: Media.player

            // MPRIS doesn't push positions; poll while something plays.
            Timer { interval: 1000; repeat: true; running: Media.playing && media.visible; onTriggered: media.p?.positionChanged() }

            Row {
                id: mediaRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 7
                Btn {
                    id: art
                    width: Math.round(root.tile * 0.78); height: width
                    anchors.verticalCenter: parent.verticalCenter
                    active: root.isOpen("media")
                    onClicked: e => e.button === Qt.MiddleButton ? Media.previous() : root.bar.openFrom("media", art, "left")
                    Rectangle {
                        anchors.fill: parent; radius: 6
                        color: Qt.alpha(Theme.text, 0.1)
                        clip: true
                        Image {
                            anchors.fill: parent
                            source: media.p?.trackArtUrl ?? ""
                            sourceSize { width: 96; height: 96 }
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 112
                    spacing: 0
                    Text { width: parent.width; text: Media.label; elide: Text.ElideRight; color: Theme.text
                        font { family: root.family; pixelSize: 12; weight: Theme.w(Font.DemiBold) } }
                    Text { width: parent.width; text: Media.artist; visible: text !== ""; elide: Text.ElideRight; color: Theme.textDim
                        font { family: root.family; weight: Theme.fontWeight; pixelSize: 11 } }
                }
                // play/pause + next only (previous is in the media popout / middle-click the art)
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    Glyph { width: 24; text: Media.playing ? "󰏤" : "󰐊"; px: 15; onClicked: Media.playPause() }   // 󰏤 / 󰐊
                    Glyph { width: 24; text: "󰒭"; px: 13; onClicked: Media.next() }          // 󰒭
                }
            }
        }
    }

    // ── Middle: the Dock's apps ───────────────────────────────────────
    readonly property var parked: Hyprland.toplevels.values
        .filter(h => h.workspace?.name === "special:browser" && h.wayland).map(h => h.wayland)
    readonly property var apps: {
        void DesktopEntries.applications.values; // rebuild (fresh entry objects) after a rescan
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
        } else launch(it);
    }

    // Launch bounce, like the Dock: bounces until the app's first window shows (then one more
    // beat), or gives up after 2.4 s.
    function launch(it) {
        if (!it.entry) return;
        Apps.launch(it.entry, it.id);
        if (!(s.taskbarBounce ?? true)) return;
        bounceStop.interval = 2400;
        bouncing = it.id; bounceStop.restart();
    }
    property string bouncing: ""
    Timer { id: bounceStop; interval: 2400; onTriggered: root.bouncing = "" }
    onAppsChanged: {
        if (bouncing && apps.some(a => a.id === bouncing && a.wins.length > 0)) bounceStop.interval = 700;
        // keep the open right-click menu's app fresh, and close it if the app went away
        if (Popouts.ctxApp && root.isOpen("appctx")) Popouts.ctxApp = apps.find(a => a.id === Popouts.ctxApp.id) ?? null;
    }

    // Magnification (own settings, taskbarMagnify/-Size): icons grow upwards out of the bar under the
    // pointer. Bar.qml keeps fixed headroom above the bar (magHead) so the surface never resizes.
    readonly property real mag: (s.taskbarMagnify ?? true) ? (s.taskbarMagnifySize ?? 1.7) : 1
    readonly property int magHead: Math.ceil(tile * (mag - 1)) + 34     // + room for the name bubble
    readonly property int gap: 8
    readonly property real baseTotal: apps.length * tile + Math.max(0, apps.length - 1) * gap
    property real px: -1e4                                               // pointer x, root coords
    property real hoverAmt: dockHover.hovered && !bar.expanded ? 1 : 0
    Behavior on hoverAmt { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    function sizeAt(i) {
        if (mag <= 1) return tile;
        const c = (width - baseTotal) / 2 + i * (tile + gap) + tile / 2;   // unmagnified centre
        const d = Math.abs(px - c), range = tile * 2.6;
        const f = d < range ? (Math.cos(Math.PI * d / range) + 1) / 2 : 0;
        return tile * (1 + (mag - 1) * f * hoverAmt);
    }

    // Hover area around the apps; reaches up over the grown icons while hovered (Bar adds it to
    // the input mask, so the strip above the bar only takes input then).
    property alias magHit: dockArea
    Item {
        id: dockArea
        readonly property real padX: root.tile / 2
        x: (root.width - width) / 2
        y: dockHover.hovered && root.mag > 1 ? -root.magHead : 0
        width: middle.width + padX * 2
        height: root.height - y
        HoverHandler { id: dockHover; onPointChanged: root.px = point.position.x + dockArea.x }

    Row {
        id: middle
        x: dockArea.padX
        y: -dockArea.y
        height: root.height
        spacing: root.gap
        Repeater {
            model: root.apps
            Item {
                id: cell
                required property var modelData
                required property int index
                readonly property real size: root.sizeAt(index)
                width: size; height: middle.height
            Btn {
                id: app
                readonly property var modelData: cell.modelData
                width: cell.size; height: cell.size
                y: Math.round((parent.height + root.tile) / 2 - height - bounce.offset)   // bottom stays put, grows upwards
                QtObject { id: bounce; property real offset: 0 }
                SequentialAnimation {
                    running: root.bouncing === app.modelData.id
                    loops: Animation.Infinite
                    NumberAnimation { target: bounce; property: "offset"; to: root.tile * 0.45; duration: 300; easing.type: Easing.OutQuad }
                    NumberAnimation { target: bounce; property: "offset"; to: 0; duration: 300; easing.type: Easing.InQuad }
                    onRunningChanged: if (!running) bounce.offset = 0
                }
                onClicked: e => {
                    if (e.button === Qt.MiddleButton) root.launch(modelData);
                    else if (e.button === Qt.RightButton) { Popouts.ctxApp = modelData; root.bar.openFrom("appctx", app, "above"); }
                    else root.activate(modelData);
                }
                Image {
                    anchors.fill: parent
                    source: AppIcons.source(app.modelData.icon)
                    sourceSize { width: Math.max(64, Math.ceil(root.tile * Math.max(2, root.mag))); height: Math.max(64, Math.ceil(root.tile * Math.max(2, root.mag))) }
                    smooth: true; mipmap: true
                    asynchronous: true
                    opacity: app.pressed ? 0.6 : 1
                }
                Rectangle {
                    visible: app.modelData.wins.length > 0
                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.bottom; topMargin: 2 }
                    width: 4; height: 4; radius: 2
                    color: Qt.alpha(Theme.text, 0.85)
                }
                // name bubble
                Rectangle {
                    visible: app.containsMouse
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.top; bottomMargin: 8 }
                    width: nameText.implicitWidth + 16; height: 22; radius: 6
                    color: Theme.menuBg
                    border { width: 1; color: Theme.menuEdge }
                    Text { id: nameText; anchors.centerIn: parent; text: app.modelData.name; color: Theme.menuText; font { family: root.family; weight: Theme.fontWeight; pixelSize: 11 } }
                }
            }
            }
        }
    }
    }

    // ── Right: tray, status, Spotlight, clock ────────────────────────
    Row {
        id: right
        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
        spacing: 6

        Repeater {
            model: SystemTray.items
            Btn {
                id: trayItem
                required property SystemTrayItem modelData
                width: 28; height: root.height - 12
                anchors.verticalCenter: parent.verticalCenter
                active: root.isOpen("tray") && Popouts.trayItem === modelData
                tip: modelData.tooltipTitle || modelData.title || "Tray"
                tipSub: modelData.tooltipDescription || ""
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

        Glyph {
            id: bt
            readonly property var adapter: Bluetooth.defaultAdapter
            readonly property var connected: adapter ? adapter.devices.values.filter(d => d.connected) : []
            visible: !!adapter
            text: adapter?.enabled ? "󰂯" : "󰂲"     // 󰂯 / 󰂲
            active: root.isOpen("bluetooth")
            tip: "Bluetooth"
            tipSub: !adapter ? "Unavailable" : !adapter.enabled ? "Off"
                 : connected.length ? connected.map(d => d.name || d.address).join(", ") : "On"
            onClicked: root.bar.openFrom("bluetooth", bt, "right")
        }
        Glyph {
            id: wifi
            text: Net.glyph
            active: root.isOpen("network")
            tip: Net.wired ? "Ethernet" : "Wi-Fi"
            tipSub: Net.label
            onClicked: root.bar.openFrom("network", wifi, "right")
        }
        Glyph {
            id: vol
            text: Audio.glyph
            active: root.isOpen("sound")
            tip: "Sound"
            tipSub: Audio.muted ? "Muted" : Math.round(Math.min(1, Audio.volume) * 100) + "% · " + Audio.name
            onClicked: e => e.button === Qt.MiddleButton ? Audio.toggleMute() : root.bar.openFrom("sound", vol, "right")
            WheelHandler { onWheel: e => Audio.nudge(e.angleDelta.y > 0 ? 0.03 : -0.03) }
        }
        Btn {
            id: wx
            visible: (root.s.barWeather ?? true) && Weather.ok
            width: wxRow.implicitWidth + 14; height: root.height - 12
            anchors.verticalCenter: parent.verticalCenter
            active: root.isOpen("weather")
            tip: "Weather"
            tipSub: Weather.temp + "° · " + Weather.desc
            onClicked: root.bar.openFrom("weather", wx, "right")
            Row {
                id: wxRow
                anchors.centerIn: parent
                spacing: 5
                Text { anchors.verticalCenter: parent.verticalCenter; text: Weather.glyph(Weather.code, Weather.isDay); color: Theme.text
                    font { family: root.glyphs; pixelSize: 14; hintingPreference: Font.PreferNoHinting } }
                Text { anchors.verticalCenter: parent.verticalCenter; text: Weather.temp + "°"; color: Theme.text
                    font { family: root.family; weight: Theme.fontWeight; pixelSize: 12 } }
            }
        }
        Glyph {
            id: search
            text: ""; px: 15
            active: Popouts.spotlight
            tip: "Spotlight"
            tipSub: "Apps, files, commands and math"
            onClicked: Popouts.toggleSpotlight()
        }
        Glyph {
            id: bell
            text: Notifs.dnd ? "󰂛" : "󰂚"                    // 󰂛 / 󰂚
            active: root.isOpen("notifs")
            tip: "Notifications"
            tipSub: Notifs.dnd ? "Do Not Disturb" : Notifs.unread > 0 ? Notifs.unread + " unread" : "None"
            onClicked: e => e.button === Qt.MiddleButton ? Notifs.setDnd(!Notifs.dnd) : root.bar.openFrom("notifs", bell, "right")
            Rectangle {
                visible: Notifs.unread > 0
                x: parent.width / 2 + 3; y: parent.height / 2 - 9
                width: 7; height: 7; radius: 3.5
                color: "#ff453a"
            }
        }

        // Battery ring on laptops; on desktops the slot is the Control Centre (the ring used to
        // duplicate the volume icon and open the Control Centre anyway).
        Btn {
            id: ring
            readonly property var bat: UPower.displayDevice
            readonly property bool battery: bat?.isLaptopBattery ?? false
            readonly property bool charging: bat?.state === UPowerDeviceState.Charging || bat?.state === UPowerDeviceState.FullyCharged
            readonly property real frac: battery ? ((bat.percentage <= 1 ? bat.percentage : bat.percentage / 100))
                                                 : (Audio.muted ? 0 : Math.min(1, Audio.volume))
            visible: battery
            width: root.tile; height: root.tile
            anchors.verticalCenter: parent.verticalCenter
            active: root.isOpen("controls")
            tip: "Battery"
            tipSub: Math.round(frac * 100) + "%" + (charging ? " · Charging" : "")
            onClicked: root.bar.openFrom("controls", ring, "right")
            onFracChanged: dial.requestPaint()
            Canvas {
                id: dial
                anchors { fill: parent; margins: 4 }
                renderStrategy: Canvas.Immediate
                onPaint: {
                    const c = getContext("2d"), r = width / 2 - 2;
                    c.reset();
                    c.lineWidth = 2.5; c.lineCap = "round";
                    c.strokeStyle = Qt.alpha(Theme.text, 0.2);
                    c.beginPath(); c.arc(width / 2, height / 2, r, 0, Math.PI * 2); c.stroke();
                    c.strokeStyle = Theme.text;
                    c.beginPath(); c.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * ring.frac); c.stroke();
                }
                Connections { target: Theme; function onTextChanged() { dial.requestPaint(); } }
            }
            Column {
                anchors.centerIn: parent
                spacing: -2
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: ring.charging ? "" : ["", "", "", "", ""][Math.min(4, Math.floor(ring.frac * 5))]
                    color: Theme.textDim
                    font { family: root.glyphs; pixelSize: 8; hintingPreference: Font.PreferNoHinting }
                }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(ring.frac * 100); color: Theme.text
                    font { family: root.family; pixelSize: 11; weight: Theme.w(Font.DemiBold) } }
            }
        }
        Glyph {
            id: cc
            visible: !ring.battery
            text: ""; px: 16
            active: root.isOpen("controls") || root.isOpen("media")
            tip: "Control Centre"
            tipSub: "Display, sound and quick toggles"
            onClicked: root.bar.openFrom("controls", cc, "right")
        }

        Btn {
            id: clock
            width: clockText.implicitWidth + 18; height: root.height - 12
            anchors.verticalCenter: parent.verticalCenter
            active: root.isOpen("notifs")
            tip: Qt.formatDate(clockSrc.date, "dddd d MMMM")
            tipSub: "Notifications"
            onClicked: root.bar.openFrom("notifs", clock, "right")
            Text {
                id: clockText
                anchors.centerIn: parent
                text: Qt.formatDateTime(clockSrc.date, (root.s.clock24h ?? true) ? "HH:mm" : "h:mm AP")
                color: Theme.text
                font { family: root.family; pixelSize: 15; weight: Theme.w(Font.Medium) }
            }
            SystemClock { id: clockSrc; precision: SystemClock.Minutes }
        }
    }

    // ── Sources ───────────────────────────────────────────────────────
    FileView {
        id: osInfo
        path: "/etc/os-release"
        readonly property string id_: (/^ID=("?)([^"\n]*)\1/m.exec(text() ?? "") ?? [])[2] ?? ""
        readonly property string glyph: ({ fedora: "", arch: "", cachyos: "", endeavouros: "", manjaro: "",
            debian: "", ubuntu: "", nixos: "", opensuse: "", "opensuse-tumbleweed": "", gentoo: "", void: "" })[id_] ?? ""
    }
    FileView {
        id: wallInfo
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/island/wallpaper"
        watchChanges: true
        onFileChanged: reload()
        readonly property string file: (text() ?? "").trim()
        readonly property string thumb: /\.(mp4|webm|mkv|mov|m4v|avi)$/i.test(file)
            ? (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/island/video-thumbs/" + Qt.md5(file) + ".jpg"
            : file
    }
}
