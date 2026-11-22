import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import qs.services
import qs.popouts
import qs.components

// macOS-style menu bar: logo menu and the focused app on the left; tray, status, Spotlight,
// Control Center and the clock on the right. Menus drop down under whatever opened them;
// notification banners slide in at the top right. The surface is only bar-tall while idle.
PanelWindow {
    id: win

    required property ShellScreen modelData
    screen: modelData

    readonly property var s: Config.saved
    // shellLayout "taskbar": one floating bar along the bottom (bar/Taskbar.qml) instead of the menu bar + Dock.
    // "compact": the same, but a content-sized pill centred along the bottom (bar/CompactBar.qml).
    readonly property bool compact: (s.shellLayout ?? "menubar") === "compact"
    readonly property bool taskbar: (s.shellLayout ?? "menubar") === "taskbar" || compact
    readonly property int tbGap: 8
    readonly property int tbH: s.taskbarHeight ?? 54
    readonly property int barH: taskbar ? tbH + tbGap : (s.barHeight ?? 30)
    // Skins of the menu bar (BarLayout.skins): "classic" full-width strip; "pills" one floating pill
    // per item; "island" nothing but a floating Dynamic Island capsule; "notch" nothing but a
    // MacBook-style notch flush with the top edge. The capsule and the notch grow for volume,
    // track changes, notifications and (hovered, with a player) media controls.
    readonly property string skin: taskbar ? "classic" : BarLayout.skin
    readonly property bool pills: skin === "pills"
    readonly property bool island: skin === "island"
    readonly property bool notch: skin === "notch"
    readonly property bool capsuleSkin: island || notch
    readonly property bool floating: pills || island
    readonly property int topPad: floating ? 6 : 0
    // Bottom of the bar's reserved strip: items are barH tall; floating skins hang topPad lower.
    readonly property int edge: barH + topPad
    // Room the capsule may grow into below the bar (fixed, so the surface never resizes).
    readonly property int capRoom: capsuleSkin ? 110 : 0
    readonly property color capFill: BarLayout.capsuleFill
    readonly property color pillFill: Qt.alpha(Theme.bg, Theme.glass(s.barOpacity ?? 0.55))
    readonly property color pillRim: Theme.liquid ? Theme.glassRim : Qt.alpha(Theme.text, 0.12)
    // Fixed room above the bottom bar for magnified app icons + name bubbles (never resizes).
    readonly property int tbHead: taskbar && tbLoader.item ? tbLoader.item.magHead : 0
    readonly property string family: s.widgetFont || "Adwaita Sans"
    readonly property string glyphs: "JetBrainsMono Nerd Font"
    readonly property int fontPx: s.barFontSize ?? 13
    readonly property int anim: 180

    // Popout state
    readonly property bool mine: Popouts.current !== "" && Popouts.screen === screen.name
    property string shown: ""
    property bool expanded: false
    readonly property var menus: ["system", "app", "go", "window", "help", "tray", "sound", "bluetooth", "network", "appctx"]
    readonly property bool isMenu: menus.includes(shown)

    // Where the open popout hangs from (window x), and which edge it lines up with.
    property real anchorL: 8
    property real anchorR: width - 8
    property string align: "right"
    property bool anchored: false           // set by a click; IPC opens fall back to defaults
    readonly property var defaultAlign: ({ system: "left", app: "left", go: "left", window: "left", help: "left", notifs: "right", controls: "right", sound: "right", bluetooth: "right", network: "right", media: "right", weather: "right",
                                           tray: "right", appctx: "center", power: "right", clipboard: "center", wallpapers: "center", wallhaven: "center", themes: "center" })

    function openFrom(name, item, how) {
        const p = item.mapToItem(null, 0, 0);
        anchorL = p.x; anchorR = p.x + item.width; align = how; anchored = true;
        Popouts.toggle(name, screen.name);
    }
    // macOS: with a menu open, moving across the menu titles switches menus.
    function slide(name, item) { if (expanded && isMenu && shown !== name && shown !== "tray") openFrom(name, item, "left"); }
    // Runs from both onMineChanged and onCurrentChanged, so it must be idempotent: a second call
    // for the same popout used to see `anchored` already spent and snap it to the screen edge.
    function sync() {
        if (mine) {
            if (expanded && shown === Popouts.current) { anchored = false; return; }
            // Not opened by a click (IPC, keys, or a popout opening another, like Control Centre
            // → Sound): stay where the open one was; from closed, use the bar's own edges
            // (the compact pill's, not the screen's).
            if (!anchored && !expanded) {
                align = defaultAlign[Popouts.current] ?? "center";
                anchorL = bar.x + 8; anchorR = bar.x + bar.width - 8;
            }
            anchored = false;
            shown = Popouts.current; expanded = true;
        } else if (expanded) {
            expanded = false;
            // Island / notch: the menu shrinks back into the capsule before its surface goes away.
            if (capsuleSkin) closeHold.restart(); else { shown = ""; reclaim.restart(); }
        }
        if (mine) closeHold.stop();
    }
    Timer { id: closeHold; interval: 450; onTriggered: if (!win.expanded) { win.shown = ""; reclaim.restart(); } }
    onMineChanged: sync()
    Connections { target: Popouts; function onCurrentChanged() { win.sync(); } }
    Timer { id: reclaim; interval: 500; onTriggered: gc() }

    // Banners
    readonly property var toast: !mine && shown === "" && Notifs.screen === screen.name ? Notifs.current : null
    property var toastShown: null
    onToastChanged: { if (toast) { toastHold.stop(); toastShown = toast; } else toastHold.restart(); }
    Timer { id: toastHold; interval: win.anim + 40; onTriggered: if (!win.toast) win.toastShown = null }

    // Surface
    anchors { top: !win.taskbar; bottom: win.taskbar; left: true; right: true }
    exclusiveZone: edge
    // Menus live in their own surface, so the bar never resizes (a layer resize flickers a half-drawn frame).
    // Where resizes smear (Compositor.smoothResize false) the banner room is kept permanently.
    implicitHeight: edge + Math.max(tbHead, capRoom, toastShown || !Compositor.smoothResize ? 200 : 0)
    color: "transparent"
    mask: Region {
        item: win.capsuleSkin ? null : bar      // island / notch: only the capsule takes input
        Region { item: banner }
        Region { item: tbLoader.item ? tbLoader.item.magHit : null }
        Region { item: win.capsuleSkin ? capsule : null }
    }

    WlrLayershell.namespace: "island-bar"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    property bool grabArmed: false
    onExpandedChanged: { grabArmed = false; if (expanded) arm.restart(); }
    Timer { id: arm; interval: 60; onTriggered: win.grabArmed = win.expanded }
    HyprlandFocusGrab { windows: menuLoader.item ? [win, menuLoader.item] : [win]; active: Compositor.focusGrab && win.grabArmed; onCleared: Popouts.close() }
    // Without focus grabs (anything but Hyprland) the menu surface is full-screen and catches
    // clicks everywhere except the bar itself, so a click elsewhere closes the popout while the
    // bar's items still switch menus. It's a fresh surface per menu, so nothing ever resizes.
    readonly property bool catchAll: !Compositor.focusGrab
    IdleInhibitor { window: win; enabled: Popouts.caffeine }

    // One menu-bar item: text or glyph, highlighted while its menu is open.
    component Item_: MouseArea {
        id: it
        property string text
        property bool glyph: false
        property bool bold: false
        property bool active: false
        property int pad: 9
        property bool shown: true          // false: the zone skips this item (no empty slot)
        implicitWidth: label.implicitWidth + pad * 2
        height: win.barH
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        Rectangle {
            anchors { fill: parent; topMargin: 3; bottomMargin: 3 }
            radius: win.floating ? height / 2 : 5
            color: it.active ? Qt.alpha(Theme.text, Theme.dark ? 0.2 : 0.14) : "transparent"
        }
        Text {
            id: label
            anchors.centerIn: parent
            text: it.text
            color: Theme.text
            font { family: it.glyph ? win.glyphs : win.family; pixelSize: it.glyph ? win.fontPx + 1 : win.fontPx; weight: it.bold ? Font.Bold : Font.Normal }
        }
    }

    // One zone of the menu bar: the items named in `ids`, in order (see BarLayout).
    // Pills skin: each item sits in its own floating pill.
    component Zone: Row {
        id: zone
        property var ids: []
        visible: !win.taskbar && ids.length > 0
        height: win.barH
        spacing: win.pills ? 6 : 0
        Repeater {
            model: zone.ids
            Item {
                id: slot
                required property string modelData
                visible: !!ld.item && (ld.item.shown ?? true)
                width: ld.width + (win.pills ? 4 : 0)
                height: win.barH
                Rectangle {
                    visible: win.pills
                    anchors.fill: parent
                    radius: height / 2
                    color: win.pillFill
                    border { width: 1; color: win.pillRim }
                }
                Loader {
                    id: ld
                    anchors.centerIn: parent
                    sourceComponent: win.items[slot.modelData] ?? null
                }
            }
        }
    }

    // The bar (floating skins: a transparent strip that only holds the zones)
    Rectangle {
        id: bar
        x: win.compact ? Math.round((parent.width - width) / 2) : win.taskbar ? win.tbGap : 0
        y: win.taskbar ? win.height - win.tbGap - win.tbH : win.topPad
        width: win.compact && tbLoader.item ? Math.min(parent.width - win.tbGap * 2, tbLoader.item.implicitWidth) : parent.width - (win.taskbar ? win.tbGap * 2 : 0)
        height: win.taskbar ? win.tbH : win.barH
        radius: win.compact ? Math.round(win.tbH * 0.32) : win.taskbar ? 18 : 0
        color: win.floating || win.capsuleSkin ? "transparent" : Qt.alpha(Theme.bg, Theme.glass(win.s.barOpacity ?? 0.55))
        border { width: win.taskbar ? 1 : 0; color: Theme.liquid ? Theme.glassRim : Qt.alpha(Theme.text, 0.12) }
        GlassSheen { visible: !win.floating && !win.capsuleSkin; radius: bar.radius }


        Loader {
            id: tbLoader
            anchors.fill: parent
            active: win.taskbar
            sourceComponent: win.compact ? compactComp : taskbarComp
            Component { id: taskbarComp; Taskbar { bar: win } }
            Component { id: compactComp; CompactBar { bar: win } }
        }

        // Items come from BarLayout (setting barItems): each zone lays out its ids in order.
        // Island / notch: nothing but the capsule.
        Zone { id: leftZone; ids: win.capsuleSkin ? [] : BarLayout.layout.left; anchors { left: parent.left; leftMargin: win.floating ? 12 : 8 } }
        Zone { ids: win.capsuleSkin ? [] : BarLayout.layout.center; anchors.horizontalCenter: parent.horizontalCenter }
        Zone { id: rightZone; ids: win.capsuleSkin ? [] : BarLayout.layout.right
               anchors { right: parent.right; rightMargin: win.floating ? 12 : 8 } }
    }

    // Dynamic Island / notch capsule. Idle: the time (clock24h / clockSeconds; click opens
    // notifications, or the player while something plays). It grows for a notification, a volume change, a new track, or (hovered while a
    // player exists) media controls. Menus opened from anywhere grow out of it (see `panel`).
    property bool capArmed: false                   // no volume/track flash while the shell starts
    Timer { running: win.capsuleSkin; interval: 2500; onTriggered: win.capArmed = true }
    Timer { id: capOsd; interval: 1600 }
    Timer { id: capTrack; interval: 3500 }
    property bool capHover: false
    Timer { id: capHoverDelay; interval: 280; onTriggered: win.capHover = capHoverH.hovered }
    Connections {
        target: Audio
        enabled: win.capsuleSkin && win.capArmed
        function onVolumeChanged() { capOsd.restart(); }
        function onMutedChanged() { capOsd.restart(); }
    }
    Connections {
        target: Media
        enabled: win.capsuleSkin && win.capArmed
        function onTitleChanged() { if (Media.title) capTrack.restart(); }
    }
    readonly property string capMode: !capsuleSkin ? ""
        : toastShown ? "toast"
        : capOsd.running ? "volume"
        : capTrack.running && Media.title ? "track"
        : capHover && Media.player ? "media"
        : "idle"
    readonly property int capIdleW: Math.max(island ? 104 : 190, capIdle.implicitWidth + 40)
    Binding { target: BarLayout; property: "capsuleIdleW"; value: win.capIdleW; when: win.capsuleSkin }
    readonly property int capW: ({ toast: 400, volume: 280, media: 420,
                                   track: Math.min(440, Math.max(capIdleW, capTrackRow.implicitWidth + 40)) })[capMode] ?? capIdleW
    readonly property int capH: capMode === "toast" ? Math.min(edge + capRoom - 6, capToast.implicitHeight + 22) : barH
    readonly property var capSpring: ({ duration: 340, overshoot: 1.15 })

    function capClick(e) {
        const m = capMode;
        if (e.button === Qt.RightButton) { openFrom("controls", capsule, "center"); return; }
        if (m === "toast") { const t = toastShown; Notifs.activate(t); Notifs.hide(t); return; }
        if (e.button === Qt.MiddleButton) { if (m === "volume") Audio.toggleMute(); else Media.playPause(); return; }
        if (m === "volume") openFrom("sound", capsule, "center");
        else if (Media.player && (m !== "idle" || Media.playing)) openFrom("media", capsule, "center");
        else openFrom("notifs", capsule, "center");
    }

    // One fading layer of capsule content.
    component CapLayer: Item {
        property string mode
        anchors.fill: parent
        opacity: win.capMode === mode ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
    }
    component CapButton: MouseArea {
        property string glyph
        width: 28; height: win.barH
        cursorShape: Qt.PointingHandCursor
        Text { anchors.centerIn: parent; text: parent.glyph; color: Theme.text; font { family: win.glyphs; pixelSize: win.fontPx + 1 } }
    }

    Rectangle {
        id: capsule
        visible: win.capsuleSkin
        width: win.capW
        height: win.capH
        x: Math.round((win.width - width) / 2)
        y: win.island ? win.topPad : 0
        radius: win.notch ? 12 : Math.min(height / 2, 22)
        color: win.capFill
        clip: true
        Behavior on width { NumberAnimation { duration: win.capSpring.duration; easing.type: Easing.OutBack; easing.overshoot: win.capSpring.overshoot } }
        Behavior on height { NumberAnimation { duration: win.capSpring.duration; easing.type: Easing.OutBack; easing.overshoot: win.capSpring.overshoot } }

        // Notch: flush with the screen edge, so only the bottom corners are round.
        Rectangle { visible: win.notch; anchors { left: parent.left; right: parent.right; top: parent.top } height: parent.radius; color: parent.color }

        HoverHandler {
            id: capHoverH
            onHoveredChanged: { if (hovered) capHoverDelay.restart(); else { capHoverDelay.stop(); win.capHover = false; } }
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: e => win.capClick(e)
            onWheel: e => Audio.nudge(e.angleDelta.y > 0 ? 0.03 : -0.03)
        }

        CapLayer {
            mode: "idle"
            Text {
                id: capIdle
                anchors.centerIn: parent
                text: Qt.formatDateTime(capClock.date, ((win.s.clock24h ?? true) ? "HH:mm" : "h:mm")
                      + ((win.s.clockSeconds ?? false) ? ":ss" : "") + ((win.s.clock24h ?? true) ? "" : " AP"))
                color: Theme.text
                font { family: win.family; pixelSize: win.fontPx; weight: Theme.w(Font.DemiBold); features: { "tnum": 1 } }
                SystemClock { id: capClock; enabled: win.capsuleSkin; precision: (win.s.clockSeconds ?? false) ? SystemClock.Seconds : SystemClock.Minutes }
            }
        }
        CapLayer {
            mode: "volume"
            Row {
                anchors.centerIn: parent
                spacing: 10
                Text { anchors.verticalCenter: parent.verticalCenter; text: Audio.glyph; color: Theme.text; font { family: win.glyphs; pixelSize: win.fontPx + 2 } }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 150; height: 5; radius: 2.5
                    color: Qt.alpha(Theme.text, 0.18)
                    Rectangle {
                        width: parent.width * Math.min(1, Audio.muted ? 0 : Audio.volume); height: parent.height; radius: parent.radius
                        color: Theme.accent
                        Behavior on width { NumberAnimation { duration: 120 } }
                    }
                }
                Text { anchors.verticalCenter: parent.verticalCenter; width: 34; text: Audio.muted ? "Off" : Math.round(Audio.volume * 100) + "%"; color: Theme.textDim
                    font { family: win.family; pixelSize: win.fontPx - 1 } }
            }
        }
        CapLayer {
            mode: "track"
            Row {
                id: capTrackRow
                anchors.centerIn: parent
                spacing: 8
                Text { anchors.verticalCenter: parent.verticalCenter; text: "󰝚"; color: Theme.accent; font { family: win.glyphs; pixelSize: win.fontPx + 1 } }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, 380)
                    elide: Text.ElideRight
                    text: Media.title + (Media.artist ? " — " + Media.artist : "")
                    color: Theme.text
                    font { family: win.family; pixelSize: win.fontPx; weight: Theme.w(Font.Medium) }
                }
            }
        }
        CapLayer {
            mode: "media"
            Text {
                anchors { left: parent.left; leftMargin: 18; right: capCtl.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                elide: Text.ElideRight
                text: Media.label + (Media.artist ? " — " + Media.artist : "")
                color: Theme.text
                font { family: win.family; pixelSize: win.fontPx }
            }
            Row {
                id: capCtl
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                CapButton { glyph: ""; onClicked: Media.previous() }
                CapButton { glyph: Media.playing ? "" : ""; onClicked: Media.playPause() }
                CapButton { glyph: ""; onClicked: Media.next() }
            }
        }
        CapLayer {
            mode: "toast"
            NotifCard {
                id: capToast
                visible: !!win.toastShown
                x: 12; y: 11
                width: parent.width - 24
                entry: win.toastShown
                card: false
                bodyLines: 2
            }
        }
    }

    // Bar items, by id
    readonly property var items: ({ logo: iLogo, appmenus: iAppMenus, workspaces: iWorkspaces, media: iMedia, tray: iTray, battery: iBattery,
                                    sound: iSound, network: iNetwork, spotlight: iSpotlight, weather: iWeather,
                                    controls: iControls, clock: iClock, power: iPower })

    Component {
        id: iLogo
        Item_ {
            id: logo
            glyph: true; pad: 12
            text: osGlyph.glyph
            active: win.shown === "system" && win.expanded
            onClicked: win.openFrom("system", logo, "left")
            onEntered: win.slide("system", logo)
            FileView {
                id: osGlyph
                path: "/etc/os-release"
                readonly property string id_: (/^ID=("?)([^"\n]*)\1/m.exec(text() ?? "") ?? [])[2] ?? ""
                readonly property string glyph: ({ fedora: "\uf30a", arch: "\uf303", cachyos: "\uf303", endeavouros: "\uf322", manjaro: "\uf312",
                    debian: "\uf306", ubuntu: "\uf31b", nixos: "\uf313", opensuse: "\uf314", "opensuse-tumbleweed": "\uf314", gentoo: "\uf30d", void: "\uf32e" })[id_] ?? "\uf17c"
            }
        }
    }
    Component {
        id: iAppMenus
        Row {
            height: win.barH
            Item_ {
                id: appName
                readonly property var tl: ToplevelManager.activeToplevel
                readonly property var entry: tl ? DesktopEntries.heuristicLookup(tl.appId) : null
                bold: true; pad: 10
                text: entry?.name || tl?.appId || "Desktop"
                active: win.shown === "app" && win.expanded
                onClicked: win.openFrom("app", appName, "left")
                onEntered: win.slide("app", appName)
            }
            // Finder-style Go menu with Files or the desktop focused
            Item_ {
                id: goMenu
                visible: !appName.tl || /nautilus|thunar|nemo|dolphin/i.test(appName.tl.appId)
                text: "Go"
                active: win.shown === "go" && win.expanded
                onClicked: win.openFrom("go", goMenu, "left")
                onEntered: win.slide("go", goMenu)
            }
            Item_ {
                id: windowMenu
                text: "Window"
                active: win.shown === "window" && win.expanded
                onClicked: win.openFrom("window", windowMenu, "left")
                onEntered: win.slide("window", windowMenu)
            }
            Item_ {
                id: helpMenu
                text: "Help"
                active: win.shown === "help" && win.expanded
                onClicked: win.openFrom("help", helpMenu, "left")
                onEntered: win.slide("help", helpMenu)
            }
        }
    }
    Component {
        id: iWorkspaces
        Workspaces {
            property bool shown: known.length > 0
            screenName: win.screen.name
            family: win.family
            fontPx: win.fontPx
            barH: win.barH
        }
    }
    // Now playing: play state + "Title — Artist"; click opens the player, middle-click plays/pauses.
    Component {
        id: iMedia
        Item_ {
            id: np
            shown: !!Media.player
            pad: 10
            implicitWidth: npRow.implicitWidth + pad * 2
            active: win.shown === "media" && win.expanded
            onClicked: e => e.button === Qt.MiddleButton ? Media.playPause() : win.openFrom("media", np, "left")
            Row {
                id: npRow
                anchors.centerIn: parent
                spacing: 6
                Text { anchors.verticalCenter: parent.verticalCenter; text: Media.playing ? "" : ""; color: Theme.accent
                    font { family: win.glyphs; pixelSize: win.fontPx - 2 } }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, 260)
                    elide: Text.ElideRight
                    text: Media.label + (Media.artist ? " — " + Media.artist : "")
                    color: Theme.text
                    font { family: win.family; pixelSize: win.fontPx }
                }
            }
        }
    }
    // Tray (menu extras)
    Component {
        id: iTray
        Row {
            height: win.barH
            Repeater {
                model: SystemTray.items
                MouseArea {
                    id: trayItem
                    required property SystemTrayItem modelData
                    width: 28; height: win.barH
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: e => {
                        if (e.button === Qt.MiddleButton) modelData.secondaryActivate();
                        else if (e.button === Qt.RightButton || modelData.onlyMenu) { if (modelData.hasMenu) { Popouts.trayItem = modelData; win.openFrom("tray", trayItem, "left"); } }
                        else modelData.activate();
                    }
                    Rectangle { anchors { fill: parent; topMargin: 3; bottomMargin: 3 } radius: 5
                        color: win.shown === "tray" && win.expanded && Popouts.trayItem === trayItem.modelData ? Theme.control : "transparent" }
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
        }
    }
    Component {
        id: iBattery
        Item_ {
            readonly property var bat: UPower.displayDevice
            readonly property int pct: Math.round((bat?.percentage ?? 0) <= 1 ? (bat?.percentage ?? 0) * 100 : bat.percentage)
            readonly property bool charging: bat?.state === UPowerDeviceState.Charging || bat?.state === UPowerDeviceState.FullyCharged
            shown: bat?.isLaptopBattery ?? false
            text: pct + "%  " + (charging ? "\uf0e7" : ["\uf244", "\uf243", "\uf242", "\uf241", "\uf240"][Math.min(4, Math.floor(pct / 20))])
            glyph: true
        }
    }
    Component {
        id: iSound
        Item_ {
            id: vol
            glyph: true
            text: Audio.glyph
            active: win.shown === "sound" && win.expanded
            onClicked: e => e.button === Qt.MiddleButton ? Audio.toggleMute() : win.openFrom("sound", vol, "right")
            WheelHandler { onWheel: e => Audio.nudge(e.angleDelta.y > 0 ? 0.03 : -0.03) }
        }
    }
    Component {
        id: iNetwork
        Item_ {
            id: wifi
            glyph: true
            text: Net.glyph
            active: win.shown === "network" && win.expanded
            onClicked: win.openFrom("network", wifi, "right")
        }
    }
    Component {
        id: iSpotlight
        Item_ {
            glyph: true
            text: "\uf002"
            active: Popouts.spotlight
            onClicked: Popouts.toggleSpotlight()
        }
    }
    Component {
        id: iWeather
        Item_ {
            id: wx
            shown: Weather.ok
            implicitWidth: wxRow.implicitWidth + pad * 2
            Row {
                id: wxRow
                anchors.centerIn: parent
                spacing: 5
                Text { anchors.verticalCenter: parent.verticalCenter; text: Weather.glyph(Weather.code, Weather.isDay); color: Theme.text
                    font { family: win.glyphs; pixelSize: win.fontPx + 1 } }
                Text { anchors.verticalCenter: parent.verticalCenter; text: Weather.temp + "°"; color: Theme.text
                    font { family: win.family; pixelSize: win.fontPx; weight: Theme.w(Font.Normal) } }
            }
            active: win.shown === "weather" && win.expanded
            onClicked: e => e.button === Qt.MiddleButton ? Weather.refresh() : win.openFrom("weather", wx, "right")
        }
    }
    Component {
        id: iControls
        Item_ {
            id: cc
            glyph: true
            text: "\uf205"
            active: (win.shown === "controls" || win.shown === "media") && win.expanded
            onClicked: win.openFrom("controls", cc, "right")
        }
    }
    Component {
        id: iClock
        Item_ {
            id: clockItem
            pad: 10
            // clockDate: "full" (Sat Nov 21), "weekday" (Sat) or "none"; the clock menu then shows the date.
            text: Qt.formatDateTime(clockSrc.date, ({ full: "ddd MMM d   ", weekday: "ddd  ", none: "" })[win.s.clockDate ?? "full"]
                  + ((win.s.clock24h ?? true) ? "HH:mm" : "h:mm")
                  + ((win.s.clockSeconds ?? false) ? ":ss" : "") + ((win.s.clock24h ?? true) ? "" : " AP"))
            active: win.shown === "notifs" && win.expanded
            onClicked: win.openFrom("notifs", clockItem, "right")
            SystemClock { id: clockSrc; precision: (win.s.clockSeconds ?? false) ? SystemClock.Seconds : SystemClock.Minutes }
        }
    }
    Component {
        id: iPower
        Item_ {
            id: powerItem
            glyph: true
            text: ""
            active: win.shown === "power" && win.expanded
            onClicked: e => e.button === Qt.MiddleButton ? Audio.toggleMute() : win.openFrom("power", powerItem, "right")
            WheelHandler { onWheel: e => Audio.nudge(e.angleDelta.y > 0 ? 0.03 : -0.03) }
        }
    }

    // Dropdown
    Component { id: cSystem; SystemMenu {} }
    Component { id: cApp; AppMenu {} }
    Component { id: cGo; GoMenu {} }
    Component { id: cWindow; WindowMenu {} }
    Component { id: cHelp; HelpMenu {} }
    Component { id: cControls; ControlCenter { screenName: win.screen.name } }
    Component { id: cClipboard; Clipboard {} }
    Component { id: cPower; Power {} }
    Component { id: cPicker; Picker {} }
    Component { id: cNotifs; Notifications {} }
    Component { id: cMedia; Media {} }
    Component { id: cWeather; Forecast {} }
    Component { id: cTray; TrayMenu {} }
    Component { id: cSound; SoundMenu {} }
    Component { id: cBluetooth; BluetoothMenu {} }
    Component { id: cNetwork; NetworkMenu {} }
    Component { id: cAppCtx; AppContext {} }

    // The dropdown: its own fixed-size layer surface, only while a menu is open; the compositor fades it.
    // Without focus grabs, a full-screen invisible surface one layer below catches outside clicks.
    LazyLoader {
        active: win.catchAll && win.shown !== ""
        PanelWindow {
            screen: win.screen
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "island-menu-catcher"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {
                item: menuCatcher
                Region {
                    intersection: Intersection.Subtract
                    x: 0; width: win.width
                    y: win.taskbar ? win.screen.height - win.barH - win.tbHead : 0
                    height: win.edge + (win.taskbar ? win.tbHead : 0)
                }
            }
            MouseArea { id: menuCatcher; anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: Popouts.close() }
        }
    }
    LazyLoader {
        id: menuLoader
        active: win.shown !== ""
        PanelWindow {
            id: menuWin
            screen: win.screen
            anchors { top: !win.taskbar; bottom: win.taskbar; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            implicitHeight: win.edge + Math.round(win.screen.height * 0.8)
            color: "transparent"
            mask: Region { item: panel }
            // Island / notch: Qt grows the menu out of the capsule, so the compositor must not fade it too.
            WlrLayershell.namespace: win.capsuleSkin ? "island-capsule-menu" : "island-menu"
            WlrLayershell.layer: win.catchAll ? WlrLayer.Overlay : WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            // macOS menus float on a soft shadow (drawn under the panel; faint enough that
            // Hyprland's blur, ignore_alpha 0.3, leaves it alone).
            Repeater {
                model: panel.open && !panel.bare && !panel.morph ? [[14, 0.035], [8, 0.05], [3, 0.08]] : []
                Rectangle {
                    required property var modelData
                    x: panel.x - modelData[0]; y: panel.y - modelData[0] + 4
                    width: panel.width + modelData[0] * 2; height: panel.height + modelData[0] * 2
                    radius: panel.radius + modelData[0]
                    color: Qt.rgba(0, 0, 0, modelData[1])
                }
            }
            Rectangle {
                id: panel
                readonly property Item content: pop.item
                // Island / notch: every menu grows out of the capsule (same spot, size and colour),
                // springs open, and shrinks back into it on close (sync() holds the surface meanwhile).
                readonly property bool morph: win.capsuleSkin
                readonly property bool tiles: content?.bare ?? false         // content draws its own tiles
                readonly property bool bare: tiles && !morph
                readonly property int pad: tiles ? (morph ? 10 : 0) : content?.pad ?? (win.isMenu ? 5 : 14)
                readonly property int pw: content ? Math.max(content.implicitWidth + pad * 2, morph ? win.capIdleW : 0) : 0
                readonly property int ph: content ? content.implicitHeight + pad * 2 : 0
                readonly property bool open: win.expanded && !!content
                property bool grown: false
                onOpenChanged: if (!open) grown = false
                // Start growing only once the menu surface has really rendered a few frames: a fixed
                // delay fired before the window was mapped and the content built, eating the first
                // half of the animation (the choppy start).
                FrameAnimation {
                    property int frames: 0
                    running: panel.morph && panel.open && !panel.grown
                    onRunningChanged: frames = 0
                    onTriggered: if (++frames >= 3) panel.grown = true
                }

                x: morph ? Math.round((menuWin.width - width) / 2)
                 : win.align === "left" ? Math.max(6, Math.min(menuWin.width - pw - 6, win.anchorL - 2))
                 : win.align === "right" ? Math.max(6, Math.min(menuWin.width - pw - 6, win.anchorR - pw + 2))
                 : win.align === "above" ? Math.max(6, Math.min(menuWin.width - pw - 6, Math.round((win.anchorL + win.anchorR - pw) / 2)))
                 : (menuWin.width - pw) / 2
                y: morph ? capsule.y
                 : win.taskbar ? menuWin.height - win.barH - height - (bare ? 8 : 6)
                 : win.edge + (bare ? 8 : win.isMenu ? (win.floating ? 4 : 1) : 4)
                width: morph ? (grown ? pw : capsule.width) : open ? pw : 0
                height: morph ? (grown ? ph : capsule.height) : open && content ? ph : 0
                Behavior on width { enabled: panel.morph; NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 0.7 } }
                Behavior on height { enabled: panel.morph; NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 0.7 } }
                radius: morph ? (win.notch ? 16 : Math.min(height / 2, 26)) : win.isMenu ? 10 : 20
                clip: morph
                // Menus: thin translucent "vibrancy" over Hyprland's blur, a dark outer edge and a
                // light inner edge, like AppKit. Popouts stay more opaque.
                color: morph ? win.capFill : bare ? "transparent" : Theme.menuBg
                border { width: bare || morph ? 0 : 1; color: Theme.menuEdge }
                Rectangle {
                    visible: !panel.bare && !panel.morph
                    anchors { fill: parent; margins: 1 }
                    radius: parent.radius - 1
                    color: "transparent"
                    border { width: 1; color: Theme.menuInner }
                }
                GlassSheen { visible: !panel.bare && !panel.morph; radius: panel.radius; strength: Theme.dark ? 0.10 : 0.3 }
                // Notch: square top corners, flush with the screen edge like the capsule.
                Rectangle { visible: panel.morph && win.notch; anchors { left: parent.left; right: parent.right; top: parent.top } height: panel.radius; color: panel.color }

                // Pointer leaving a popout that has been entered closes it (not menus you're reading).
                HoverHandler {
                    property bool entered: false
                    onHoveredChanged: {
                        if (hovered) { entered = true; leave.stop(); }
                        else if (entered && win.expanded && !win.isMenu && (panel.content?.closeOnLeave ?? false)) leave.restart();
                    }
                }
                Timer { id: leave; interval: 400; onTriggered: Popouts.close() }
                Connections { target: win; function onExpandedChanged() { leave.stop(); } }

                Loader {
                    id: pop
                    readonly property var map: ({ system: cSystem, app: cApp, go: cGo, window: cWindow, help: cHelp, controls: cControls, clipboard: cClipboard, power: cPower,
                                                  wallpapers: cPicker, wallhaven: cPicker, themes: cPicker, notifs: cNotifs, media: cMedia, weather: cWeather, tray: cTray, sound: cSound, bluetooth: cBluetooth, network: cNetwork, appctx: cAppCtx })
                    active: win.shown !== ""
                    sourceComponent: map[win.shown] ?? null
                    focus: true
                    x: panel.morph ? Math.round((panel.width - width) / 2) : panel.pad
                    y: panel.pad
                    width: item ? item.implicitWidth : 0
                    opacity: !panel.morph || panel.grown ? 1 : 0
                    Behavior on opacity { enabled: panel.morph; NumberAnimation { duration: 180 } }
                    onLoaded: item.forceActiveFocus()
                    onSourceComponentChanged: if (item) item.forceActiveFocus()
                    Keys.onEscapePressed: Popouts.close()
                }
            }
        }
    }

    // Notification banner (top right). Island and notch skins show notifications in the capsule.
    Rectangle {
        id: banner
        readonly property bool on: win.toast !== null && !win.capsuleSkin
        visible: !win.capsuleSkin
        x: win.width - width - 10
        y: win.taskbar ? win.height - win.barH - 8 - height : win.edge + 8
        width: win.toastShown ? 360 : 0
        height: win.toastShown && toastCard ? toastCard.implicitHeight + 20 : 0
        radius: 16
        color: Qt.alpha(Theme.bg, 0.9)
        border { width: 1; color: Qt.alpha(Theme.text, 0.12) }
        opacity: on ? 1 : 0
        transform: Translate { x: banner.on ? 0 : 40; Behavior on x { NumberAnimation { duration: win.anim; easing.type: Easing.OutCubic } } }
        Behavior on opacity { NumberAnimation { duration: win.anim } }
        clip: true

        NotifCard {
            id: toastCard
            visible: !!win.toastShown
            x: 10; y: 10
            width: parent.width - 20
            entry: win.toastShown
            card: false
            bodyLines: 3
        }
        Text {
            readonly property int n: Notifs.popups.length - 1
            visible: n > 0
            anchors { bottom: parent.bottom; bottomMargin: 6; right: parent.right; rightMargin: 12 }
            text: "+" + n + " more"
            color: Theme.textFaint
            font { family: win.family; pixelSize: 10; weight: Theme.w(Font.Bold) }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Popouts.open("notifs", win.screen.name) }
        }
    }
}
