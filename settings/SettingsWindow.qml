import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.services

// System Settings, laid out like macOS: traffic lights, sidebar with search, an account card
// and grouped panes; a toolbar with back/forward; inset grouped rows. Changes apply on their
// own (no Save button). The window only exists while open (+20 s), so it costs nothing idle.
//   qs -c island ipc call settings toggle
//   qs -c island ipc call settings page appearance
Scope {
    id: root

    property bool open: false
    // Destroying a window whose text field has focus crashes Qt's input method, so focus is
    // moved off the text fields as soon as it hides (see onVisibleChanged).
    property bool loaded: false
    onOpenChanged: if (open) { unload.stop(); loaded = true; } else unload.restart()
    Timer { id: unload; interval: 20000; onTriggered: if (!root.open) { root.loaded = false; reclaim.restart(); } }
    Timer { id: reclaim; interval: 500; onTriggered: gc() }

    // ── Navigation (with back / forward like macOS) ───────────────────
    property string page: "general"
    property var back: []
    property var forward: []
    property bool navigating: false
    onPageChanged: if (!navigating) { back = back.concat([lastPage]).slice(-30); forward = []; lastPage = page; } else lastPage = page
    property string lastPage: "general"
    function goBack() { if (!back.length) return; navigating = true; forward = [page].concat(forward); page = back[back.length - 1]; back = back.slice(0, -1); navigating = false; }
    function goForward() { if (!forward.length) return; navigating = true; back = back.concat([page]); page = forward[0]; forward = forward.slice(1); navigating = false; }

    readonly property var transitions: [["fade", "Fade"], ["wipe", "Wipe"], ["wave", "Wave"], ["grow", "Grow"], ["outer", "Outer"], ["simple", "Cut"], ["random", "Random"]]

    // ── Every pane, as data. section: sidebar group. custom: settings/pages/<name>.qml ──
    readonly property var pages: [
        { id: "wifi", section: 0, text: "Wi-Fi", glyph: "", tint: "#0a84ff", custom: "WifiPage", keywords: "wireless network wlan ssid password join" },
        { id: "bluetooth", section: 0, text: "Bluetooth", glyph: "", tint: "#0a84ff", custom: "BluetoothPage", keywords: "devices pair headphones mouse keyboard" },
        { id: "network", section: 0, text: "Network", glyph: "", tint: "#0a84ff", custom: "NetworkPage", keywords: "ethernet wired lan ip address internet vpn wireguard openvpn tunnel" },

        { id: "notifications", section: 1, text: "Notifications", glyph: "", tint: "#ff3b30",
          about: "Banners slide in at the top right of the screen. Click the clock in the menu bar to open Notification Centre.",
          keywords: "notification daemon toast banner popup alerts timeout",
          groups: [
            { title: "Notification Centre", footer: "Critical notifications stay until dismissed and still show while Do Not Disturb is on.", rows: [
                { key: "notifTimeout", type: "slider", label: "Banner duration", sub: "Unless the app asks for its own", from: 2, to: 20, suffix: " s", minText: "2 s", maxText: "20 s" } ] } ] },
        { id: "sound", section: 1, text: "Sound", glyph: "", tint: "#ff2d55", custom: "SoundPage", keywords: "volume output speakers headphones mute audio" },
        { id: "focus", section: 1, text: "Focus", glyph: "", tint: "#5e5ce6",
          about: "Focus silences notification banners. They still collect in Notification Centre.",
          keywords: "do not disturb dnd quiet silence",
          groups: [ { title: "", rows: [ { key: "notifDnd", type: "switch", label: "Do Not Disturb", sub: "Also in Control Centre" } ] } ] },

        { id: "general", section: 2, text: "General", glyph: "", tint: "#8e8e93", custom: "GeneralPage", keywords: "about computer system info os kernel memory cpu storage reset" },
        { id: "appearance", section: 2, text: "Appearance", glyph: "", tint: "#3a3a3c", custom: "AppearancePage",
          keywords: "theme dark light accent colour color gtk icons cursor pointer matugen wallpaper material font catppuccin nord gruvbox",
          groups: [
            { title: "Colours from wallpaper", footer: "Builds a theme from the current wallpaper with matugen, and rebuilds it whenever the wallpaper changes. Choosing a theme above turns this off.", rows: [
                { key: "matugen", type: "switch", label: "Match the wallpaper" },
                { key: "matugenScheme", type: "list", label: "Scheme", when: "matugen", options: [["tonal-spot", "Tonal Spot"], ["content", "Content"], ["expressive", "Expressive"], ["fidelity", "Fidelity"], ["fruit-salad", "Fruit Salad"], ["rainbow", "Rainbow"], ["neutral", "Neutral"], ["monochrome", "Monochrome"]] },
                { key: "matugenMode", type: "choice", label: "Mode", when: "matugen", options: [["light", "Light"], ["dark", "Dark"]] },
                { key: "matugenPrefer", type: "list", label: "Pick colour by", when: "matugen", options: [["saturation", "Most saturated"], ["less-saturation", "Least saturated"], ["value", "Brightest"], ["darkness", "Darkest"], ["lightness", "Lightest"]] } ] },
            { title: "Look & feel", footer: "GTK apps pick these up live (GTK 4 apps may need a restart).", rows: [
                { key: "widgetFont", type: "font", label: "Interface font", sub: "Menu bar, menus, Dock, Spotlight and Settings" },
                { key: "gtkTheme", type: "list", label: "Application theme", sub: "adw-gtk3 is recoloured to match", source: "gtk" },
                { key: "iconTheme", type: "list", label: "Icons", source: "icons" },
                { key: "cursorTheme", type: "list", label: "Pointer", source: "cursors" },
                { key: "cursorSize", type: "slider", label: "Pointer size", from: 16, to: 64, step: 2, suffix: " px", minText: "Normal", maxText: "Large" } ] } ] },
        { id: "controlcentre", section: 2, text: "Control Centre", glyph: "", tint: "#8e8e93",
          about: "The menu bar runs across the top of the screen. Control Centre opens from the toggles icon next to the clock.",
          keywords: "menu bar clock time seconds 24 hour height opacity blur font size weather temperature",
          groups: [
            { title: "Menu Bar", rows: [
                { key: "barHeight", type: "slider", label: "Height", from: 22, to: 44, suffix: " px" },
                { key: "barOpacity", type: "slider", label: "Background opacity", from: 0, to: 1, step: 0.01, decimals: 2, minText: "Clear", maxText: "Solid" },
                { key: "barBlur", type: "switch", label: "Blur behind the menu bar" },
                { key: "barFontSize", type: "slider", label: "Text size", from: 10, to: 18, suffix: " px" },
                { key: "barWeather", type: "switch", label: "Show the weather", sub: "Click it for the forecast; location is set under Desktop & Dock" } ] },
            { title: "Clock", rows: [
                { key: "clock24h", type: "switch", label: "Use a 24-hour clock" },
                { key: "clockSeconds", type: "switch", label: "Display the time with seconds" } ] } ] },
        { id: "desktop", section: 2, text: "Desktop & Dock", glyph: "", tint: "#1c1c1e",
          keywords: "dock magnification autohide size widgets clock weather location city country units calendar music system windows gaps borders rounding layout tiling transparency opacity blur animations",
          groups: [
            { title: "Dock", rows: [
                { key: "dock", type: "switch", label: "Show the Dock" },
                { key: "dockSize", type: "slider", label: "Size", from: 32, to: 96, suffix: " px", minText: "Small", maxText: "Large", when: "dock" },
                { key: "dockMagnify", type: "switch", label: "Magnification", when: "dock" },
                { key: "dockMagnifySize", type: "slider", label: "Magnified size", from: 1.1, to: 2.5, step: 0.05, decimals: 2, suffix: "×", minText: "Small", maxText: "Large", when: "dockMagnify" },
                { key: "dockAutohide", type: "switch", label: "Automatically hide and show the Dock", when: "dock" },
                { key: "dockAllScreens", type: "switch", label: "Show on every display", when: "dock" },
                { key: "dockOpacity", type: "slider", label: "Background opacity", from: 0, to: 1, step: 0.01, decimals: 2, when: "dock" },
                { key: "dockMargin", type: "slider", label: "Distance from the edge", from: 0, to: 30, suffix: " px", when: "dock" } ] },
            { title: "Desktop", footer: "Widgets sit on the desktop, under your windows.", rows: [
                { key: "widgets", type: "switch", label: "Show widgets" },
                { key: "widgetsPosition", type: "list", label: "Position", when: "widgets", options: [["top-left", "Top Left"], ["top-right", "Top Right"], ["bottom-left", "Bottom Left"], ["bottom-right", "Bottom Right"]] },
                { key: "widgetsAllScreens", type: "switch", label: "Show on every display", when: "widgets" },
                { key: "widgetsMargin", type: "slider", label: "Distance from the edge", from: 0, to: 120, suffix: " px", when: "widgets" },
                { key: "widgetsOpacity", type: "slider", label: "Widget opacity", from: 0, to: 1, step: 0.01, decimals: 2, when: "widgets" },
                { key: "widgetClock", type: "switch", label: "Clock", when: "widgets" },
                { key: "widgetClockSeconds", type: "switch", label: "Second hand", when: "widgetClock" },
                { key: "widgetWeather", type: "switch", label: "Weather", when: "widgets" },
                { key: "weatherLocation", type: "text", label: "Weather location", sub: "Empty to use your approximate location", live: "weather", placeholder: "City, Country — or empty for automatic" },
                { key: "weatherUnits", type: "choice", label: "Units", sub: "Temperature and wind speed", options: [["c", "Celsius · km/h"], ["f", "Fahrenheit · mph"]] },
                { key: "widgetCalendar", type: "switch", label: "Calendar", when: "widgets" },
                { key: "widgetMusic", type: "switch", label: "Now Playing", when: "widgets" },
                { key: "widgetSystem", type: "switch", label: "System", sub: "CPU, memory, temperature and disk", when: "widgets" } ] },
            { title: "Windows", rows: [
                { key: "layout", type: "choice", label: "Tiling layout", options: [["dwindle", "Dwindle"], ["master", "Master"]] },
                { key: "gapsIn", type: "slider", label: "Space between windows", from: 0, to: 30, suffix: " px" },
                { key: "gapsOut", type: "slider", label: "Space around the screen edge", from: 0, to: 40, suffix: " px" },
                { key: "borderSize", type: "slider", label: "Border width", from: 0, to: 8, suffix: " px" },
                { key: "rounding", type: "slider", label: "Corner radius", from: 0, to: 24, suffix: " px" },
                { key: "activeOpacity", type: "slider", label: "Focused window opacity", from: 0.5, to: 1, step: 0.01, decimals: 2 },
                { key: "inactiveOpacity", type: "slider", label: "Other windows' opacity", from: 0.5, to: 1, step: 0.01, decimals: 2 },
                { key: "dimInactive", type: "switch", label: "Dim windows in the background" } ] },
            { title: "Blur", footer: "Blur shows through translucent windows, the menu bar, Dock and Spotlight. Higher values use more GPU.", rows: [
                { key: "blur", type: "switch", label: "Blur" },
                { key: "blurSize", type: "slider", label: "Strength", from: 1, to: 12, when: "blur", minText: "Subtle", maxText: "Strong" },
                { key: "blurPasses", type: "slider", label: "Passes", from: 1, to: 4, when: "blur" } ] },
            { title: "Animations", rows: [
                { key: "animations", type: "switch", label: "Animate windows and workspaces" },
                { key: "animCurve", type: "choice", label: "Feel", sub: "How motion eases in and out", options: [["smooth", "Smooth"], ["spring", "Springy"], ["classic", "Classic"]], when: "animations" },
                { key: "animSpeed", type: "slider", label: "Speed", from: 0.5, to: 10, step: 0.5, decimals: 1, minText: "Fast", maxText: "Slow", when: "animations" },
                { key: "windowAnim", type: "choice", label: "Windows", options: [["popin", "Pop In"], ["slide", "Slide"], ["gnomed", "Genie"]], when: "animations" },
                { key: "workspaceAnim", type: "choice", label: "Workspaces", options: [["slide", "Slide"], ["slidevert", "Vertical"], ["fade", "Fade"], ["slidefade", "Slide & Fade"]], when: "animations" } ] } ] },
        { id: "defaultapps", section: 2, text: "Default Apps", glyph: "\uf00a", tint: "#5856d6", custom: "DefaultAppsPage",
          keywords: "default browser web mail email file manager folder text editor image viewer video player music pdf archive open with xdg mime handler" },
        { id: "displays", section: 2, text: "Displays", glyph: "", tint: "#0a84ff", custom: "DisplaysPage", keywords: "monitor resolution refresh rate hz scale rotation rotate screen vrr adaptive sync" },
        { id: "wallpaper", section: 2, text: "Wallpaper", glyph: "", tint: "#32ade6",
          about: "Pick a picture or a video from your wallpaper folders. Super+W opens the picker.",
          keywords: "background picture folder transition video live animated mpvpaper wallhaven download api key",
          groups: [
            { title: "", rows: [
                { type: "button", label: "Wallpaper picker", sub: "Pictures, videos and Wallhaven", text: "Choose…", f: () => Popouts.open("wallpapers") },
                { key: "wallDir", type: "text", label: "Pictures folder", placeholder: "~/Pictures/Wallpapers" },
                { key: "videoDir", type: "text", label: "Videos folder", sub: "Played with mpvpaper", placeholder: "~/Videos/Wallpapers" },
                { key: "videoMpvOptions", type: "text", label: "mpv options", placeholder: "no-audio loop hwdec=auto panscan=1.0" },
                { key: "wallTransition", type: "list", label: "Transition", options: root.transitions },
                { key: "wallDuration", type: "slider", label: "Transition length", from: 0, to: 3, step: 0.1, decimals: 1, suffix: " s" } ] },
            { title: "Wallhaven", footer: "The API key is only needed for NSFW results or your account's blacklist. It's kept in ~/.config/island/wallhaven-api-key, readable only by you.", rows: [
                { key: "wallhavenApiKey", type: "secret", label: "API key", sub: "Press Return to save", placeholder: "Optional" },
                { key: "wallhavenQuery", type: "text", label: "Default search", placeholder: "Anything" },
                { key: "wallhavenSorting", type: "list", label: "Sort by", options: [["toplist", "Toplist"], ["date_added", "Newest"], ["random", "Random"], ["views", "Most Viewed"], ["favorites", "Most Favourited"], ["relevance", "Relevance"], ["hot", "Hot"]] },
                { key: "wallhavenTopRange", type: "list", label: "Toplist range", options: [["1d", "Day"], ["1w", "Week"], ["1M", "Month"], ["3M", "3 Months"], ["1y", "Year"]] },
                { key: "wallhavenGeneral", type: "switch", label: "General" },
                { key: "wallhavenAnime", type: "switch", label: "Anime" },
                { key: "wallhavenPeople", type: "switch", label: "People" },
                { key: "wallhavenSketchy", type: "switch", label: "Include sketchy" },
                { key: "wallhavenNsfw", type: "switch", label: "Include NSFW", sub: "Needs an API key" },
                { key: "wallhavenAtleast", type: "text", label: "Minimum resolution", placeholder: "1920x1080" },
                { key: "wallhavenRatios", type: "text", label: "Aspect ratios", sub: "e.g. 16x9,21x9", placeholder: "Any" } ] } ] },

        { id: "keyboard", section: 3, text: "Keyboard", glyph: "", tint: "#8e8e93", custom: "KeyboardShortcuts", customAfter: true,
          keywords: "key repeat delay numlock shortcuts keybinds",
          groups: [
            { title: "", rows: [
                { key: "repeatRate", type: "slider", label: "Key repeat rate", from: 10, to: 80, suffix: "/s", minText: "Slow", maxText: "Fast" },
                { key: "repeatDelay", type: "slider", label: "Delay until repeat", from: 150, to: 1000, step: 25, suffix: " ms", minText: "Short", maxText: "Long" },
                { key: "numlock", type: "switch", label: "Turn on Num Lock at login" } ] } ] },
        { id: "screenshots", section: 3, text: "Screenshots", glyph: "\uf030", tint: "#636366",
          about: "Print captures a selection, ⌥Print a window, ⇧Print the whole screen. ⇧⌘S opens the screenshot toolbar.",
          keywords: "screenshot screen capture print grim slurp snip region window clipboard thumbnail",
          groups: [
            { title: "", rows: [
                { type: "button", label: "Screenshot toolbar", sub: "Screen, window or selection, with a timer", text: "Open…", f: () => Screenshot.openToolbar() },
                { key: "screenshotDest", type: "list", label: "Save to", options: [["~/Pictures/Screenshots", "Screenshots folder"], ["~/Pictures", "Pictures"], ["~/Desktop", "Desktop"], ["clipboard", "Clipboard only"]] },
                { key: "screenshotCopy", type: "switch", label: "Also copy to the clipboard" },
                { key: "screenshotThumb", type: "switch", label: "Show floating thumbnail", sub: "Click it to open the screenshot" },
                { key: "screenshotPointer", type: "switch", label: "Show the mouse pointer" },
                { key: "screenshotSound", type: "switch", label: "Play sound" } ] } ] },
        { id: "mouse", section: 3, text: "Mouse", glyph: "", tint: "#8e8e93",
          keywords: "pointer tracking speed sensitivity acceleration scroll natural focus follows",
          groups: [
            { title: "", rows: [
                { key: "sensitivity", type: "slider", label: "Tracking speed", from: -1, to: 1, step: 0.05, decimals: 2, minText: "Slow", maxText: "Fast" },
                { key: "naturalScroll", type: "switch", label: "Natural scrolling", sub: "Content tracks finger movement" },
                { key: "accelProfile", type: "choice", label: "Pointer acceleration", options: [["flat", "Off"], ["adaptive", "On"]] },
                { key: "followMouse", type: "list", label: "Focus follows pointer", options: [[0, "Off"], [1, "Always"], [2, "Loosely"]] } ] } ] },

        { id: "terminal", section: 4, text: "Terminal", glyph: "", tint: "#1c1c1e",
          about: "Settings for foot. They apply to new terminal windows.",
          keywords: "foot font size opacity transparency padding",
          groups: [
            { title: "", rows: [
                { key: "termFont", type: "font", label: "Font" },
                { key: "termFontSize", type: "slider", label: "Font size", from: 8, to: 24, suffix: " pt" },
                { key: "termOpacity", type: "slider", label: "Background opacity", from: 0.3, to: 1, step: 0.01, decimals: 2 },
                { key: "termPadding", type: "slider", label: "Padding", from: 0, to: 40, suffix: " px" } ] } ] }
    ]
    readonly property var current: pages.find(p => p.id === page) ?? pages[0]

    // ── Search ────────────────────────────────────────────────────────
    property string query: ""                         // trimmed, lower-case
    function rowHit(r, q) { return (r.label + " " + (r.sub ?? "")).toLowerCase().includes(q); }
    function pageHit(p, q) {
        if (q === "") return true;
        if ((p.text + " " + p.keywords).toLowerCase().includes(q)) return true;
        return (p.groups ?? []).some(g => g.rows.some(r => rowHit(r, q)));
    }
    readonly property var hits: pages.filter(p => pageHit(p, query))
    onQueryChanged: if (hits.length > 0 && !hits.some(p => p.id === page)) page = hits[0].id
    function step(d) {
        const list = query ? hits : pages;
        const i = list.findIndex(p => p.id === page);
        if (list.length) page = list[Math.max(0, Math.min(list.length - 1, i + d))].id;
    }

    // The signed-in user, for the account card.
    property string userName: ""
    Process {
        running: root.loaded && root.userName === ""
        command: ["sh", "-c", 'n=$(getent passwd "$USER" | cut -d: -f5 | cut -d, -f1); echo "${n:-$USER}"']
        stdout: StdioCollector { onStreamFinished: root.userName = text.trim() }
    }

    signal escapeRequested()
    property bool escapeHandled: false

    LazyLoader {
        active: root.loaded

        FloatingWindow {
            id: window
            title: "System Settings"
            implicitWidth: 820
            implicitHeight: 640
            minimumSize: Qt.size(700, 460)
            color: Theme.bg
            visible: root.open
            onVisibleChanged: if (visible) search.forceActiveFocus(); else { contentItem.forceActiveFocus(); root.open = false; }

            Shortcut { sequences: ["Ctrl+F"]; context: Qt.WindowShortcut; onActivated: { search.forceActiveFocus(); search.selectAll(); } }
            Shortcut { sequences: ["Ctrl+W", "Ctrl+Q"]; context: Qt.WindowShortcut; onActivated: root.open = false }
            Shortcut { sequences: ["Alt+Left", "Ctrl+["]; context: Qt.WindowShortcut; onActivated: root.goBack() }
            Shortcut { sequences: ["Alt+Right", "Ctrl+]"]; context: Qt.WindowShortcut; onActivated: root.goForward() }
            Shortcut {
                sequences: ["Escape"]; context: Qt.WindowShortcut
                onActivated: {
                    root.escapeHandled = false;
                    root.escapeRequested();
                    if (root.escapeHandled) return;
                    if (search.text !== "") { search.text = ""; search.forceActiveFocus(); }
                }
            }
            Connections { target: root; function onPageChanged() { scroller.contentY = 0; } }

            // ── Sidebar ───────────────────────────────────────────────
            Rectangle {
                id: sidebar
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: 236
                color: Theme.sidebar
                Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: 1; color: Qt.alpha(Theme.text, 0.07) }

                // Traffic lights
                Row {
                    id: lights
                    x: 16; y: 16
                    spacing: 8
                    HoverHandler { id: lightsHover }
                    // Symbols are drawn as strokes (not font glyphs, which sit off-centre and
                    // vary by font): close ×, minimise −, zoom +.
                    Repeater {
                        model: [["#ff5f57", "close", () => root.open = false], ["#febc2e", "min", () => root.open = false],
                                ["#28c840", "zoom", () => Compositor.zoom()]]
                        MouseArea {
                            id: light
                            required property var modelData
                            width: 12; height: 12
                            onClicked: modelData[2]()
                            Rectangle { anchors.fill: parent; radius: width / 2; antialiasing: true; color: light.modelData[0]
                                border { width: 0.5; color: Qt.darker(light.modelData[0], 1.25) } }
                            Item {
                                anchors.fill: parent
                                visible: lightsHover.hovered
                                Repeater {
                                    model: light.modelData[1] === "close" ? [45, -45] : light.modelData[1] === "min" ? [0] : [0, 90]
                                    Rectangle {
                                        required property var modelData
                                        x: (12 - width) / 2; y: (12 - height) / 2
                                        width: light.modelData[1] === "close" ? 7 : 6.5; height: 1.3
                                        radius: 0.65; antialiasing: true
                                        rotation: modelData
                                        color: Qt.rgba(0, 0, 0, 0.55)
                                    }
                                }
                            }
                        }
                    }
                }

                // Search
                Rectangle {
                    id: searchBox
                    anchors { left: parent.left; right: parent.right; top: lights.bottom; margins: 10; topMargin: 16 }
                    height: 28; radius: 7
                    color: Qt.alpha(Theme.text, Theme.dark ? 0.08 : 0.06)
                    border { width: search.activeFocus ? 3 : 0; color: Theme.focusRing }
                    Text { id: glass; anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                        text: ""; color: Theme.textDim; font { family: Theme.mono; pixelSize: 11 } }
                    TextInput {
                        id: search
                        anchors { left: glass.right; leftMargin: 6; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        color: Theme.text; selectionColor: Theme.selection; selectedTextColor: Theme.onAccent
                        clip: true
                        font { family: Theme.font; pixelSize: 13 }
                        onTextChanged: root.query = text.trim().toLowerCase()
                        Keys.onUpPressed: root.step(-1)
                        Keys.onDownPressed: root.step(1)
                        Text { visible: search.text === ""; text: "Search"; color: Theme.textFaint; font: search.font }
                    }
                }

                Flickable {
                    anchors { left: parent.left; right: parent.right; top: searchBox.bottom; bottom: parent.bottom; topMargin: 10 }
                    contentHeight: side.height + 16
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    Column {
                        id: side
                        x: 10; width: parent.width - 20
                        spacing: 0

                        // Account card
                        MouseArea {
                            visible: root.query === ""
                            width: parent.width; height: 58
                            onClicked: root.page = "general"
                            Rectangle { anchors.fill: parent; radius: 8; color: "transparent" }
                            Rectangle {
                                id: avatar
                                x: 6; anchors.verticalCenter: parent.verticalCenter
                                width: 38; height: 38; radius: 19
                                gradient: Gradient { GradientStop { position: 0; color: "#a1a1a6" } GradientStop { position: 1; color: "#6e6e73" } }
                                Text { anchors.centerIn: parent; color: "white"; font { family: Theme.font; pixelSize: 15; weight: Font.DemiBold }
                                    text: root.userName.split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0].toUpperCase()).join("") }
                            }
                            Column {
                                anchors { left: avatar.right; leftMargin: 10; right: parent.right; verticalCenter: parent.verticalCenter }
                                Text { width: parent.width; text: root.userName; elide: Text.ElideRight; color: Theme.text
                                    font { family: Theme.font; pixelSize: 13; weight: Font.DemiBold } }
                                Text { text: "Local Account"; color: Theme.textDim; font { family: Theme.font; pixelSize: 11 } }
                            }
                        }

                        Repeater {
                            model: root.query === "" ? root.pages : root.hits
                            delegate: Column {
                                required property var modelData
                                required property int index
                                readonly property var list: root.query === "" ? root.pages : root.hits
                                width: side.width
                                Item { width: 1; height: index > 0 && root.query === "" && parent.list[index - 1].section !== modelData.section ? 12 : 0 }
                                SidebarItem {
                                    width: parent.width
                                    text: modelData.text; glyph: modelData.glyph; tint: modelData.tint
                                    current: root.page === modelData.id
                                    onClicked: root.page = modelData.id
                                }
                            }
                        }
                        Text {
                            visible: root.hits.length === 0
                            leftPadding: 8; topPadding: 6
                            text: "No Results"
                            color: Theme.textDim
                            font { family: Theme.font; pixelSize: 12 }
                        }
                    }
                }
            }

            // ── Content ───────────────────────────────────────────────
            Item {
                anchors { left: sidebar.right; right: parent.right; top: parent.top; bottom: parent.bottom }

                // Toolbar: ‹ ›  Title
                Item {
                    id: toolbar
                    width: parent.width; height: 52
                    Row {
                        id: nav
                        x: 14; anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Repeater {
                            model: [["", () => root.goBack(), root.back.length > 0], ["", () => root.goForward(), root.forward.length > 0]]
                            MouseArea {
                                required property var modelData
                                width: 26; height: 26
                                enabled: modelData[2]
                                hoverEnabled: true
                                onClicked: modelData[1]()
                                Rectangle { anchors.fill: parent; radius: 6; color: parent.containsMouse && parent.enabled ? Theme.hover : "transparent" }
                                Text { anchors.centerIn: parent; text: parent.modelData[0]; color: parent.enabled ? Theme.text : Theme.textFaint
                                    font { family: Theme.mono; pixelSize: 12 } }
                            }
                        }
                    }
                    Text {
                        anchors { left: nav.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        text: root.current.text
                        color: Theme.text
                        font { family: Theme.font; pixelSize: 15; weight: Font.Bold }
                    }
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 1; color: Qt.alpha(Theme.text, 0.08)
                        opacity: scroller.contentY > 2 ? 1 : 0
                    }
                }

                Flickable {
                    id: scroller
                    anchors { left: parent.left; right: parent.right; top: toolbar.bottom; bottom: parent.bottom }
                    contentHeight: body.height + 40
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    Column {
                        id: body
                        x: 24; y: 6
                        width: scroller.width - 48
                        spacing: 20

                        // Header card: big icon, title, description (pages that have one)
                        Rectangle {
                            visible: !!root.current.about
                            width: parent.width
                            height: visible ? Math.max(84, aboutText.implicitHeight + 50) : 0
                            radius: 10
                            color: Theme.dark ? Qt.alpha(Theme.text, 0.045) : Qt.alpha(Theme.text, 0.03)
                            border { width: 1; color: Qt.alpha(Theme.text, 0.07) }
                            Rectangle {
                                id: hero
                                x: 16; anchors.verticalCenter: parent.verticalCenter
                                width: 52; height: 52; radius: 12
                                gradient: Gradient { GradientStop { position: 0; color: Qt.lighter(root.current.tint, 1.15) } GradientStop { position: 1; color: root.current.tint } }
                                Text { anchors.centerIn: parent; text: root.current.glyph; color: "white"; font { family: Theme.mono; pixelSize: 26 } }
                            }
                            Column {
                                anchors { left: hero.right; leftMargin: 14; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                                spacing: 3
                                Text { text: root.current.text; color: Theme.text; font { family: Theme.font; pixelSize: 15; weight: Font.Bold } }
                                Text { id: aboutText; width: parent.width; text: root.current.about ?? ""; wrapMode: Text.WordWrap
                                    color: Theme.textDim; font { family: Theme.font; pixelSize: 12 } }
                            }
                        }

                        Loader {
                            width: parent.width
                            height: item ? item.implicitHeight : 0     // an unloaded Loader keeps its old height otherwise
                            active: !!root.current.custom && !root.current.customAfter
                            source: active ? Qt.resolvedUrl("pages/" + root.current.custom + ".qml") : ""
                        }

                        Repeater {
                            model: root.current.groups ?? []
                            delegate: Group {
                                required property var modelData
                                title: modelData.title
                                footer: modelData.footer ?? ""
                                Repeater {
                                    model: modelData.rows
                                    delegate: Loader {
                                        required property var modelData
                                        width: parent ? parent.width : 0
                                        sourceComponent: modelData.type === "button" ? buttonRow : settingRow
                                        Component { id: settingRow; Setting {
                                            id: row
                                            spec: modelData
                                            Connections { target: root; function onEscapeRequested() { if (row.fontOpen) { row.fontOpen = false; root.escapeHandled = true; } } }
                                        } }
                                        Component { id: buttonRow; SettingRow {
                                            title: modelData.label; subtitle: modelData.sub ?? ""
                                            PushButton { text: modelData.text; onClicked: modelData.f() }
                                        } }
                                    }
                                }
                            }
                        }

                        Loader {
                            width: parent.width
                            height: item ? item.implicitHeight : 0     // an unloaded Loader keeps its old height otherwise
                            active: !!root.current.custom && !!root.current.customAfter
                            source: active ? Qt.resolvedUrl("pages/" + root.current.custom + ".qml") : ""
                        }

                        // Restore Defaults for this pane (macOS puts this at the bottom right)
                        Item {
                            readonly property var keys: { const out = []; for (const g of (root.current.groups ?? [])) for (const r of g.rows) if (r.key) out.push(r.key); return out; }
                            visible: keys.some(k => !Config.isDefault(k))
                            width: parent.width; height: visible ? 24 : 0
                            PushButton {
                                anchors.right: parent.right
                                text: "Restore Defaults"
                                onClicked: { Config.reset(parent.keys); }
                            }
                        }
                    }
                }
            }

            // macOS window edge: a hairline just inside the corners Hyprland rounds (rule
            // island-settings in hypr/looks.lua, rounding 12).
            Rectangle {
                anchors.fill: parent
                z: 100
                radius: 12
                antialiasing: true
                color: "transparent"
                border { width: 1; color: Theme.dark ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(0, 0, 0, 0.12) }
            }
        }
    }
}
