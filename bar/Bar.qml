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
    // layout "taskbar": one floating bar along the bottom (bar/Taskbar.qml) instead of the menu bar + Dock.
    readonly property bool taskbar: (s.layout ?? "menubar") === "taskbar"
    readonly property int tbGap: 8
    readonly property int tbH: s.taskbarHeight ?? 54
    readonly property int barH: taskbar ? tbH + tbGap : (s.barHeight ?? 30)
    readonly property string family: s.widgetFont || "Adwaita Sans"
    readonly property string glyphs: "JetBrainsMono Nerd Font"
    readonly property int fontPx: s.barFontSize ?? 13
    readonly property int anim: 180

    // ── Popout state ──────────────────────────────────────────────────
    readonly property bool mine: Popouts.current !== "" && Popouts.screen === screen.name
    property string shown: ""
    property bool expanded: false
    readonly property var menus: ["system", "app", "go", "window", "help", "tray", "sound", "network"]
    readonly property bool isMenu: menus.includes(shown)

    // Where the open popout hangs from (window x), and which edge it lines up with.
    property real anchorL: 8
    property real anchorR: width - 8
    property string align: "right"
    property bool anchored: false           // set by a click; IPC opens fall back to defaults
    readonly property var defaultAlign: ({ system: "left", app: "left", go: "left", window: "left", help: "left", notifs: "right", controls: "right", sound: "right", network: "right", media: "right", weather: "right",
                                           tray: "right", power: "right", clipboard: "center", wallpapers: "center", wallhaven: "center", themes: "center" })

    function openFrom(name, item, how) {
        const p = item.mapToItem(null, 0, 0);
        anchorL = p.x; anchorR = p.x + item.width; align = how; anchored = true;
        Popouts.toggle(name, screen.name);
    }
    // macOS: with a menu open, moving across the menu titles switches menus.
    function slide(name, item) { if (expanded && isMenu && shown !== name && shown !== "tray") openFrom(name, item, "left"); }
    function sync() {
        if (mine) {
            if (!anchored) { align = defaultAlign[Popouts.current] ?? "center"; anchorL = 8; anchorR = width - 8; }
            anchored = false;
            shown = Popouts.current; expanded = true;
        } else if (expanded) { expanded = false; shown = ""; reclaim.restart(); }
    }
    onMineChanged: sync()
    Connections { target: Popouts; function onCurrentChanged() { win.sync(); } }
    Timer { id: reclaim; interval: 500; onTriggered: gc() }

    // ── Banners ───────────────────────────────────────────────────────
    readonly property var toast: !mine && shown === "" && Notifs.screen === screen.name ? Notifs.current : null
    property var toastShown: null
    onToastChanged: { if (toast) { toastHold.stop(); toastShown = toast; } else toastHold.restart(); }
    Timer { id: toastHold; interval: win.anim + 40; onTriggered: if (!win.toast) win.toastShown = null }

    // ── Surface ───────────────────────────────────────────────────────
    anchors { top: !win.taskbar; bottom: win.taskbar; left: true; right: true }
    exclusiveZone: barH
    // Menus live in their own surface (below), so opening/closing one never resizes the bar —
    // a layer-surface resize shows a half-drawn frame, which was the flicker.
    implicitHeight: catchAll ? screen.height : barH + (toastShown ? 200 : 0)
    color: "transparent"
    mask: Region { item: bar; Region { item: banner } Region { item: win.catchAll ? catcher : null } }

    WlrLayershell.namespace: "island-bar"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    property bool grabArmed: false
    onExpandedChanged: { grabArmed = false; if (expanded) arm.restart(); }
    Timer { id: arm; interval: 60; onTriggered: win.grabArmed = win.expanded }
    HyprlandFocusGrab { windows: menuLoader.item ? [win, menuLoader.item] : [win]; active: Compositor.focusGrab && win.grabArmed; onCleared: Popouts.close() }
    // Without focus grabs (anything but Hyprland): while a popout is open, every bar covers its
    // screen with a transparent catcher, so a click anywhere else closes it.
    readonly property bool catchAll: !Compositor.focusGrab && Popouts.current !== ""
    MouseArea {
        id: catcher
        anchors.fill: parent
        z: -1
        visible: win.catchAll
        acceptedButtons: Qt.AllButtons
        onPressed: Popouts.close()
    }
    IdleInhibitor { window: win; enabled: Popouts.caffeine }

    // One menu-bar item: text or glyph, highlighted while its menu is open.
    component Item_: MouseArea {
        id: it
        property string text
        property bool glyph: false
        property bool bold: false
        property bool active: false
        property int pad: 9
        implicitWidth: label.implicitWidth + pad * 2
        height: win.barH
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        Rectangle {
            anchors { fill: parent; topMargin: 3; bottomMargin: 3 }
            radius: 5
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

    // ── The bar ───────────────────────────────────────────────────────
    Rectangle {
        id: bar
        x: win.taskbar ? win.tbGap : 0
        y: win.taskbar ? win.height - win.tbGap - win.tbH : 0
        width: parent.width - x * 2
        height: win.taskbar ? win.tbH : win.barH
        radius: win.taskbar ? 18 : 0
        color: Qt.alpha(Theme.bg, win.s.barOpacity ?? 0.55)
        border { width: win.taskbar ? 1 : 0; color: Qt.alpha(Theme.text, 0.12) }

        Loader {
            anchors.fill: parent
            active: win.taskbar
            sourceComponent: Taskbar { bar: win }
        }

        Row {
            visible: !win.taskbar
            anchors { left: parent.left; leftMargin: 8 }
            height: parent.height

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
                    readonly property string glyph: ({ fedora: "", arch: "", cachyos: "", endeavouros: "", manjaro: "",
                        debian: "", ubuntu: "", nixos: "", opensuse: "", "opensuse-tumbleweed": "", gentoo: "", void: "" })[id_] ?? ""
                }
            }
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

        Row {
            visible: !win.taskbar
            anchors { right: parent.right; rightMargin: 8 }
            height: parent.height
            spacing: 0

            // Tray (menu extras)
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

            Item_ {
                readonly property var bat: UPower.displayDevice
                readonly property int pct: Math.round((bat?.percentage ?? 0) <= 1 ? (bat?.percentage ?? 0) * 100 : bat.percentage)
                readonly property bool charging: bat?.state === UPowerDeviceState.Charging || bat?.state === UPowerDeviceState.FullyCharged
                visible: bat?.isLaptopBattery ?? false
                text: pct + "%  " + (charging ? "" : ["", "", "", "", ""][Math.min(4, Math.floor(pct / 20))])
                glyph: true
            }
            Item_ {
                id: vol
                glyph: true
                text: Audio.glyph
                active: win.shown === "sound" && win.expanded
                onClicked: e => e.button === Qt.MiddleButton ? Audio.toggleMute() : win.openFrom("sound", vol, "right")
                WheelHandler { onWheel: e => Audio.nudge(e.angleDelta.y > 0 ? 0.03 : -0.03) }
            }
            Item_ {
                id: wifi
                glyph: true
                text: Net.glyph
                active: win.shown === "network" && win.expanded
                onClicked: win.openFrom("network", wifi, "right")
            }
            Item_ {
                glyph: true
                text: ""
                active: Popouts.spotlight
                onClicked: Popouts.toggleSpotlight()
            }
            Item_ {
                id: wx
                visible: (win.s.barWeather ?? true) && Weather.ok
                implicitWidth: wxRow.implicitWidth + pad * 2
                Row {
                    id: wxRow
                    anchors.centerIn: parent
                    spacing: 5
                    Text { anchors.verticalCenter: parent.verticalCenter; text: Weather.glyph(Weather.code, Weather.isDay); color: Theme.text
                        font { family: win.glyphs; pixelSize: win.fontPx + 1 } }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: Weather.temp + "°"; color: Theme.text
                        font { family: win.family; pixelSize: win.fontPx; weight: Font.Normal } }
                }
                active: win.shown === "weather" && win.expanded
                onClicked: e => e.button === Qt.MiddleButton ? Weather.refresh() : win.openFrom("weather", wx, "right")
            }
            Item_ {
                id: cc
                glyph: true
                text: ""
                active: (win.shown === "controls" || win.shown === "media") && win.expanded
                onClicked: win.openFrom("controls", cc, "right")
            }
            Item_ {
                id: clockItem
                pad: 10
                text: Qt.formatDateTime(clockSrc.date, "ddd MMM d   " + ((win.s.clock24h ?? true) ? "HH:mm" : "h:mm")
                      + ((win.s.clockSeconds ?? false) ? ":ss" : "") + ((win.s.clock24h ?? true) ? "" : " AP"))
                active: win.shown === "notifs" && win.expanded
                onClicked: win.openFrom("notifs", clockItem, "right")
                SystemClock { id: clockSrc; precision: (win.s.clockSeconds ?? false) ? SystemClock.Seconds : SystemClock.Minutes }
            }
            Item_ {
                id: powerItem
                glyph: true
                text: "\uf011"
                active: win.shown === "power" && win.expanded
                onClicked: e => e.button === Qt.MiddleButton ? Audio.toggleMute() : win.openFrom("power", powerItem, "right")
                WheelHandler { onWheel: e => Audio.nudge(e.angleDelta.y > 0 ? 0.03 : -0.03) }
            }
        }
    }

    // ── Dropdown ──────────────────────────────────────────────────────
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
    Component { id: cNetwork; NetworkMenu {} }

    // The dropdown: a separate layer surface that only exists while a menu is open, at a fixed
    // size so switching menus doesn't resize it either. Hyprland fades it in/out on the GPU
    // (layer rule island-menu in hypr/island.lua), so Qt draws no fade frames.
    LazyLoader {
        id: menuLoader
        active: win.shown !== ""
        PanelWindow {
            id: menuWin
            screen: win.screen
            anchors { top: !win.taskbar; bottom: win.taskbar; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            implicitHeight: win.barH + Math.round(win.screen.height * 0.8)
            color: "transparent"
            mask: Region { item: panel }
            WlrLayershell.namespace: "island-menu"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            // macOS menus float on a soft shadow (drawn under the panel; faint enough that
            // Hyprland's blur, ignore_alpha 0.3, leaves it alone).
            Repeater {
                model: panel.open && !panel.bare ? [[14, 0.035], [8, 0.05], [3, 0.08]] : []
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
                readonly property bool bare: content?.bare ?? false          // content draws its own tiles
                readonly property int pad: bare ? 0 : content?.pad ?? (win.isMenu ? 5 : 14)
                readonly property int pw: content ? content.implicitWidth + pad * 2 : 0
                readonly property bool open: win.expanded && !!content

                x: win.align === "left" ? Math.max(6, Math.min(menuWin.width - pw - 6, win.anchorL - 2))
                 : win.align === "right" ? Math.max(6, Math.min(menuWin.width - pw - 6, win.anchorR - pw + 2))
                 : (menuWin.width - pw) / 2
                y: win.taskbar ? menuWin.height - win.barH - height - (bare ? 8 : 6)
                              : win.barH + (bare ? 8 : win.isMenu ? 1 : 4)
                width: open ? pw : 0
                height: open && content ? content.implicitHeight + pad * 2 : 0
                radius: win.isMenu ? 10 : 20
                // Menus: thin translucent "vibrancy" over Hyprland's blur, a dark outer edge and a
                // light inner edge, like AppKit. Popouts stay more opaque.
                color: bare ? "transparent" : Theme.menuBg
                border { width: bare ? 0 : 1; color: Theme.menuEdge }
                Rectangle {
                    visible: !panel.bare
                    anchors { fill: parent; margins: 1 }
                    radius: parent.radius - 1
                    color: "transparent"
                    border { width: 1; color: Theme.menuInner }
                }

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
                                                  wallpapers: cPicker, wallhaven: cPicker, themes: cPicker, notifs: cNotifs, media: cMedia, weather: cWeather, tray: cTray, sound: cSound, network: cNetwork })
                    active: win.shown !== ""
                    sourceComponent: map[win.shown] ?? null
                    focus: true
                    x: panel.pad; y: panel.pad
                    width: item ? item.implicitWidth : 0
                    onLoaded: item.forceActiveFocus()
                    onSourceComponentChanged: if (item) item.forceActiveFocus()
                    Keys.onEscapePressed: Popouts.close()
                }
            }
        }
    }

    // ── Notification banner (top right) ───────────────────────────────
    Rectangle {
        id: banner
        readonly property bool on: win.toast !== null
        x: win.width - width - 10
        y: win.taskbar ? win.height - win.barH - 8 - height : win.barH + 8
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
            font { family: win.family; pixelSize: 10; weight: Font.Bold }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Popouts.open("notifs", win.screen.name) }
        }
    }
}
