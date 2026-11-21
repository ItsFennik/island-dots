import QtQuick
import Quickshell
import Quickshell.Io
import qs.components
import qs.services

// System Settings, laid out like macOS Tahoe: a floating rounded sidebar (traffic lights,
// capsule search, account card), a capsule back/forward toolbar, a centred header card on
// every pane and rounded grouped rows, kept to a readable width. Changes apply on their
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
    readonly property var aliases: ({ controlcentre: "menubar" })
    onPageChanged: if (aliases[page]) page = aliases[page]; else if (!navigating) { back = back.concat([lastPage]).slice(-30); forward = []; lastPage = page; } else lastPage = page
    property string lastPage: "general"
    function goBack() { if (!back.length) return; navigating = true; forward = [page].concat(forward); page = back[back.length - 1]; back = back.slice(0, -1); navigating = false; }
    function goForward() { if (!forward.length) return; navigating = true; back = back.concat([page]); page = forward[0]; forward = forward.slice(1); navigating = false; }

    readonly property var transitions: [["fade", "Fade"], ["wipe", "Wipe"], ["wave", "Wave"], ["grow", "Grow"], ["cursor", "Grow from Cursor"], ["any", "Grow from Random Spot"], ["outer", "Outer"], ["simple", "Cut"], ["random", "Random"]]

    // ── Every pane, as data. section: sidebar group. custom: settings/pages/<name>.qml ──
    readonly property var pages: [
        { id: "wifi", section: 0, text: "Wi-Fi", glyph: "", tint: "#0a84ff", about: "Join wireless networks. Networks you've used before connect on their own.", custom: "WifiPage", keywords: "wireless network wlan ssid password join" },
        { id: "bluetooth", section: 0, text: "Bluetooth", glyph: "", tint: "#0a84ff", about: "Pair and connect headphones, mice, keyboards and other devices.", custom: "BluetoothPage", keywords: "devices pair headphones mouse keyboard" },
        { id: "network", section: 0, text: "Network", glyph: "", tint: "#0a84ff", about: "Wired connections, IP details and VPNs.", custom: "NetworkPage", keywords: "ethernet wired lan ip address internet vpn wireguard openvpn tunnel" },

        { id: "notifications", section: 1, text: "Notifications", glyph: "", tint: "#ff3b30",
          about: "Banners slide in at the top right of the screen. Click the clock in the menu bar to open Notification Centre.",
          keywords: "notification daemon toast banner popup alerts timeout",
          groups: [
            { title: "Notification Centre", footer: "Critical notifications stay until dismissed and still show while Do Not Disturb is on.", rows: [
                { key: "notifTimeout", type: "slider", label: "Banner duration", sub: "Unless the app asks for its own", from: 2, to: 20, suffix: " s", minText: "2 s", maxText: "20 s" } ] } ] },
        { id: "sound", section: 1, text: "Sound", glyph: "", tint: "#ff2d55", about: "Choose where sound plays and which microphone listens.", custom: "SoundPage", keywords: "volume output speakers headphones mute audio" },
        { id: "focus", section: 1, text: "Focus", glyph: "", tint: "#5e5ce6",
          about: "Focus silences notification banners. They still collect in Notification Centre.",
          keywords: "do not disturb dnd quiet silence",
          groups: [ { title: "", rows: [ { key: "notifDnd", type: "switch", label: "Do Not Disturb", sub: "Also in Control Centre" } ] } ] },

        { id: "general", section: 2, text: "General", glyph: "", tint: "#8e8e93", custom: "GeneralPage", keywords: "about computer system info os kernel memory cpu storage reset" },
        { id: "appearance", section: 2, text: "Appearance", glyph: "", tint: "#3a3a3c", about: "Theme, accent and text colour, the layout of the desktop, and how apps, icons and the pointer look.", custom: "AppearancePage",
          keywords: "theme dark light accent text colour color black white gtk icons cursor pointer matugen wallpaper material font catppuccin nord gruvbox",
          groups: [
            { title: "Colours from wallpaper", footer: "Builds a theme from the current wallpaper with matugen, and rebuilds it whenever the wallpaper changes. Choosing a theme above turns this off.", rows: [
                { key: "matugen", type: "switch", label: "Match the wallpaper" },
                { key: "matugenScheme", type: "list", label: "Scheme", when: "matugen", options: [["tonal-spot", "Tonal Spot"], ["content", "Content"], ["expressive", "Expressive"], ["fidelity", "Fidelity"], ["fruit-salad", "Fruit Salad"], ["rainbow", "Rainbow"], ["neutral", "Neutral"], ["monochrome", "Monochrome"]] },
                { key: "matugenMode", type: "choice", label: "Mode", when: "matugen", options: [["light", "Light"], ["dark", "Dark"]] },
                { key: "matugenPrefer", type: "list", label: "Pick colour by", when: "matugen", options: [["saturation", "Most saturated"], ["less-saturation", "Least saturated"], ["value", "Brightest"], ["darkness", "Darkest"], ["lightness", "Lightest"]] } ] },
            { title: "Look & feel", footer: "GTK apps pick these up live (GTK 4 apps may need a restart).", rows: [
                { key: "widgetFont", type: "font", label: "Interface font", sub: "Menu bar, menus, Dock, Spotlight and Settings" },
                { key: "widgetFontWeight", type: "list", label: "Weight", sub: "Bold text stays at least this heavy", source: "fontWeights" },
                { key: "textColor", type: "choice", label: "Text colour", sub: "Menu bar, menus, Dock, widgets and Settings", options: [["auto", "Auto"], ["white", "White"], ["black", "Black"]] },
                { key: "gtkTheme", type: "list", label: "Application theme", sub: "adw-gtk3 is recoloured to match", source: "gtk" },
                { key: "iconTheme", type: "list", label: "Icons", source: "icons" },
                { key: "cursorTheme", type: "list", label: "Pointer", source: "cursors" },
                { key: "cursorSize", type: "slider", label: "Pointer size", from: 16, to: 64, step: 2, suffix: " px", minText: "Normal", maxText: "Large" } ] } ] },
        { id: "menubar", section: 2, text: "Menu Bar", custom: "BarItems", customAfter: true, glyph: "", tint: "#8e8e93",
          about: "Menus, status items and the clock across the top of the screen. Control Centre opens from the toggles icon next to the clock.",
          keywords: "workspaces workspace tags dots numbers control centre center menu bar clock time seconds 24 hour height opacity blur font size weather temperature",
          groups: [
            { title: "Menu Bar", rows: [
                { key: "barHeight", type: "slider", label: "Height", from: 22, to: 44, suffix: " px" },
                { key: "barOpacity", type: "slider", label: "Background opacity", from: 0, to: 1, step: 0.01, decimals: 2, minText: "Clear", maxText: "Solid" },
                { key: "barBlur", type: "switch", label: "Blur behind the menu bar" },
                { key: "barFontSize", type: "slider", label: "Text size", from: 10, to: 18, suffix: " px" } ] },
            { title: "Workspaces", footer: "Click to switch, scroll to step through, right-click for the Overview.", rows: [
                { key: "barWorkspaces", type: "switch", label: "Show workspaces", sub: "In the menu bar, bottom bar and compact bar" },
                { key: "barWorkspaceStyle", type: "wsstyle", label: "Style", when: "barWorkspaces", options: [["numbers", "Numbers"], ["dots", "Dots"], ["pill", "Pill"], ["glide", "Glide"], ["line", "Line"], ["activity", "Activity"], ["kanji", "Kanji"], ["roman", "Roman"]] },
                { key: "barWorkspaceCount", type: "slider", label: "Always show", from: 1, to: 10, suffix: "", minText: "1", maxText: "10", when: "barWorkspaces" } ] },
            { title: "Clock", rows: [
                { key: "clockDate", type: "list", label: "Date", sub: "Click the clock for the full date", options: [["full", "Sat Nov 21"], ["weekday", "Sat"], ["none", "Time only"]] },
                { key: "clock24h", type: "switch", label: "Use a 24-hour clock" },
                { key: "clockSeconds", type: "switch", label: "Display the time with seconds" } ] } ] },
        { id: "dock", section: 2, text: "Dock", glyph: "", tint: "#1c1c1e",
          about: "Your apps along the bottom of the screen. Drag icons to reorder them, or drag an open app in to keep it there.",
          keywords: "dock magnification magnify autohide hide size pinned apps edge",
          groups: [
            { title: "", rows: [
                { key: "dock", type: "switch", label: "Show the Dock" } ] },
            { title: "Size", rows: [
                { key: "dockSize", type: "slider", label: "Size", from: 32, to: 96, suffix: " px", minText: "Small", maxText: "Large", when: "dock" },
                { key: "dockMagnify", type: "switch", label: "Magnification", sub: "Icons grow under the pointer", when: "dock" },
                { key: "dockMagnifySize", type: "slider", label: "Magnified size", from: 1.1, to: 2.5, step: 0.05, decimals: 2, suffix: "×", minText: "Small", maxText: "Large", when: "dockMagnify" } ] },
            { title: "Behaviour", rows: [
                { key: "dockAutohide", type: "switch", label: "Automatically hide and show the Dock", when: "dock" },
                { key: "dockAllScreens", type: "switch", label: "Show on every display", when: "dock" },
                { key: "dockOpacity", type: "slider", label: "Background opacity", from: 0, to: 1, step: 0.01, decimals: 2, minText: "Clear", maxText: "Solid", when: "dock" },
                { key: "dockMargin", type: "slider", label: "Distance from the edge", from: 0, to: 30, suffix: " px", when: "dock" } ] } ] },
        { id: "desktop", section: 2, text: "Desktop & Widgets", glyph: "", tint: "#30d158",
          about: "Widgets sit on the desktop under your windows. Drag one anywhere, or right-click it to change its size.",
          keywords: "widgets clock weather location city country units celsius fahrenheit calendar music now playing system cpu verse bible esv scripture lock screen locker hyprlock autologin login session start style tahoe classic opacity corner colours colors wallpaper tint accent matugen",
          groups: [
            { title: "", rows: [
                { key: "widgets", type: "switch", label: "Show widgets" },
                { key: "widgetStyle", type: "choice", label: "Style", when: "widgets", options: [["tahoe", "Tahoe"], ["classic", "Classic"]] },
                { key: "widgetColors", type: "choice", label: "Colours", sub: "Accents and tint. Wallpaper picks them from your wallpaper", when: "widgets", options: [["system", "System"], ["theme", "Theme"], ["wallpaper", "Wallpaper"]] },
                { key: "widgetsOpacity", type: "slider", label: "Widget opacity", from: 0, to: 1, step: 0.01, decimals: 2, minText: "Clear", maxText: "Solid", when: "widgets" } ] },
            { title: "Widgets", rows: [
                { key: "widgetClock", type: "switch", label: "Clock", when: "widgets" },
                { key: "widgetClockSeconds", type: "switch", label: "Second hand", when: "widgetClock" },
                { key: "widgetWeather", type: "switch", label: "Weather", when: "widgets" },
                { key: "widgetCalendar", type: "switch", label: "Calendar", when: "widgets" },
                { key: "widgetMusic", type: "switch", label: "Now Playing", when: "widgets" },
                { key: "widgetSystem", type: "switch", label: "System", sub: "CPU, memory, temperature and disk", when: "widgets" },
                { key: "widgetVerse", type: "switch", label: "Verse of the Day", sub: "ESV, from Bible Gateway", when: "widgets" } ] },
            { title: "Lock Screen", footer: "hyprlock reads ~/.config/hypr/hyprlock.conf, which apply-theme.sh keeps in the current palette.", rows: [
                { key: "lockScreen", type: "choice", label: "Locker", options: [["island", "Island"], ["hyprlock", "hyprlock"]] },
                { key: "lockOnStart", type: "switch", label: "Lock when the session starts", sub: "Use with SDDM autologin: log in automatically, then unlock Island" },
                { key: "lockVerse", type: "switch", label: "Verse on the lock screen", sub: "Island's lock screen only; it sits above the picture" } ] },
            { title: "Arrangement", footer: "Widgets you haven't moved stack in the chosen corner.", rows: [
                { type: "button", label: "Arrange widgets", sub: "Or just drag a widget on the desktop", text: "Edit Widgets…", f: () => WidgetLayout.edit("") },
                { type: "button", label: "Widget positions", sub: "Stack them in the corner again", text: "Reset", f: () => WidgetLayout.reset() },
                { key: "widgetsPosition", type: "list", label: "Corner", when: "widgets", options: [["top-left", "Top Left"], ["top-right", "Top Right"], ["bottom-left", "Bottom Left"], ["bottom-right", "Bottom Right"]] },
                { key: "widgetsMargin", type: "slider", label: "Distance from the edge", from: 0, to: 120, suffix: " px", when: "widgets" },
                { key: "widgetsAllScreens", type: "switch", label: "Show on every display", when: "widgets" } ] },
            { title: "Weather", footer: "Used by the weather widget, the menu bar and the forecast.", rows: [
                { key: "weatherLocation", type: "text", label: "Location", sub: "Empty to use your approximate location", live: "weather", placeholder: "City, Country — or empty for automatic" },
                { key: "weatherUnits", type: "choice", label: "Units", sub: "Temperature and wind speed", options: [["c", "Celsius · km/h"], ["f", "Fahrenheit · mph"]] } ] } ] },
        { id: "windows", section: 2, text: "Windows", glyph: "", tint: "#30b0c7",
          about: "How " + Compositor.displayName + " tiles, spaces and rounds your windows, and the blur behind translucent ones.",
          keywords: "windows gaps borders rounding corner radius layout tiling dwindle master scroller scrolling grid monocle deck tile tabbed transparency opacity dim blur",
          groups: [
            { title: "Tiling", rows: [
                { key: "layout", type: "choice", label: "Tiling layout", options: Compositor.layouts, norm: v => Compositor.layoutHere(v),
                  sub: Compositor.niri ? "niri always scrolls" : "Options for " + Compositor.displayName + ", detected automatically" },
                { key: "gapsIn", type: "slider", label: "Space between windows", from: 0, to: 30, suffix: " px" },
                { key: "gapsOut", type: "slider", label: "Space around the screen edge", from: 0, to: 40, suffix: " px" } ] },
            { title: "Look", rows: [
                { key: "borderSize", type: "slider", label: "Border width", from: 0, to: 8, suffix: " px" },
                { key: "rounding", type: "slider", label: "Corner radius", from: 0, to: 24, suffix: " px" },
                { key: "activeOpacity", type: "slider", label: "Focused window opacity", from: 0.5, to: 1, step: 0.01, decimals: 2 },
                { key: "inactiveOpacity", type: "slider", label: "Other windows' opacity", from: 0.5, to: 1, step: 0.01, decimals: 2 },
                { key: "dimInactive", type: "switch", label: "Dim windows in the background" } ] },
            { title: "Blur", footer: "Blur shows through translucent windows, the menu bar, Dock and Spotlight. Higher values use more GPU.", rows: [
                { key: "blur", type: "switch", label: "Blur" },
                { key: "blurSize", type: "slider", label: "Strength", from: 1, to: 12, when: "blur", minText: "Subtle", maxText: "Strong" },
                { key: "blurPasses", type: "slider", label: "Passes", from: 1, to: 4, when: "blur" } ] } ] },
        { id: "animations", section: 2, text: "Animations", glyph: "", tint: "#ff9f0a",
          about: "How windows and workspaces move, and how quickly.",
          keywords: "animations motion speed curve spring smooth genie popin slide workspaces fade",
          groups: [
            { title: "", rows: [
                { key: "animations", type: "switch", label: "Animate windows and workspaces" },
                { key: "animCurve", type: "choice", label: "Feel", sub: "How motion eases in and out", options: [["smooth", "Smooth"], ["spring", "Springy"], ["classic", "Classic"]], when: "animations" },
                { key: "animSpeed", type: "slider", label: "Speed", from: 0.5, to: 10, step: 0.5, decimals: 1, minText: "Fast", maxText: "Slow", when: "animations" } ] },
            { title: "Style", rows: [
                { key: "windowAnim", type: "choice", label: "Windows", options: [["popin", "Pop In"], ["slide", "Slide"], ["gnomed", "Genie"]], when: "animations" },
                { key: "workspaceAnim", type: "choice", label: "Workspaces", options: [["slide", "Slide"], ["slidevert", "Vertical"], ["fade", "Fade"], ["slidefade", "Slide & Fade"]], when: "animations" } ] } ] },
        { id: "defaultapps", section: 2, text: "Default Apps", glyph: "\uf00a", tint: "#5856d6", about: "The apps that open links, mail, folders and files.", custom: "DefaultAppsPage",
          keywords: "default browser web mail email file manager folder text editor image viewer video player music pdf archive open with xdg mime handler" },
        { id: "drives", section: 2, text: "Drives", glyph: "󰋊", tint: "#636366", about: "Mount drives automatically when they're plugged in or when you log in, and mount, unmount or eject them here.", custom: "DrivesPage", keywords: "automount mount unmount eject usb stick disk drive external sd card storage udisks login partition" },
        { id: "displays", section: 2, text: "Displays", glyph: "", tint: "#0a84ff", about: "Resolution, refresh rate, scale and rotation. Changes revert after 15 seconds unless you keep them.", custom: "DisplaysPage", keywords: "monitor resolution refresh rate hz scale rotation rotate screen vrr adaptive sync" },
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

        { id: "keyboard", section: 3, text: "Keyboard", glyph: "", tint: "#8e8e93", about: "Key repeat, Num Lock and Island's keyboard shortcuts.", custom: "KeyboardShortcuts", customAfter: true,
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
        { id: "mouse", section: 3, text: "Mouse", glyph: "", tint: "#8e8e93", about: "Pointer speed, acceleration, scrolling and focus.",
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
            implicitWidth: 880
            implicitHeight: 660
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
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 8 }
                width: 232
                radius: 12
                antialiasing: true
                // Tahoe's sidebar floats over the window as its own lighter pane.
                color: Theme.dark ? Qt.tint(Theme.bg, Qt.alpha(Theme.pal.fg, 0.07)) : Qt.tint(Theme.bg, Qt.rgba(1, 1, 1, 0.6))
                border { width: 1; color: Qt.alpha(Theme.pal.fg, Theme.dark ? 0.09 : 0.1) }

                // Traffic lights
                Row {
                    id: lights
                    x: 14; y: 14
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
                    anchors { left: parent.left; right: parent.right; top: lights.bottom; margins: 10; topMargin: 14 }
                    height: 30; radius: 10
                    antialiasing: true
                    color: search.activeFocus ? Qt.alpha(Theme.pal.fg, Theme.dark ? 0.11 : 0.04) : Qt.alpha(Theme.pal.fg, Theme.dark ? 0.07 : 0.06)
                    border { width: search.activeFocus ? 2 : 1; color: search.activeFocus ? Theme.focusRing : Qt.alpha(Theme.pal.fg, 0.06) }
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text { id: glass; anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        text: ""; color: search.activeFocus ? Theme.text : Theme.textDim; font { family: Theme.mono; pixelSize: 11 } }
                    // Clear ×
                    MouseArea {
                        id: clearBtn
                        visible: search.text !== ""
                        anchors { right: parent.right; rightMargin: 7; verticalCenter: parent.verticalCenter }
                        width: 16; height: 16
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { search.text = ""; search.forceActiveFocus(); }
                        Rectangle { anchors.fill: parent; radius: 8; antialiasing: true; color: Qt.alpha(Theme.pal.fg, clearBtn.pressed ? 0.45 : 0.3) }
                        Repeater {
                            model: [45, -45]
                            Rectangle { required property var modelData; x: 4.5; y: 7.4; width: 7; height: 1.2; radius: 0.6
                                antialiasing: true; rotation: modelData; color: Theme.bg }
                        }
                    }
                    TextInput {
                        id: search
                        anchors { left: glass.right; leftMargin: 7; right: clearBtn.visible ? clearBtn.left : parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                        color: Theme.text; selectionColor: Theme.selection; selectedTextColor: Theme.onAccent
                        clip: true
                        font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 13 }
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
                            id: account
                            visible: root.query === ""
                            width: parent.width; height: 60
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.page = "general"
                            Rectangle {
                                anchors.fill: parent; radius: 10; antialiasing: true
                                color: account.pressed ? Qt.alpha(Theme.pal.fg, 0.1) : account.containsMouse ? Theme.hover : "transparent"
                                Behavior on color { ColorAnimation { duration: 110 } }
                            }
                            // Drawn as a Badge (a Shape) so the round edge stays smooth in the software renderer.
                            Badge {
                                id: avatar
                                x: 8; anchors.verticalCenter: parent.verticalCenter
                                width: 40; height: 40; radius: 20
                                tint: Qt.darker(Theme.accent, Theme.dark ? 1.5 : 1.15); topColor: Theme.accent
                                glyph: ""
                                Text { anchors.centerIn: parent; color: "white"; font { family: Theme.font; pixelSize: 15; weight: Theme.w(Font.DemiBold) }
                                    text: root.userName.split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0].toUpperCase()).join("") }
                            }
                            Column {
                                anchors { left: avatar.right; leftMargin: 11; right: chev.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                spacing: 1
                                Text { width: parent.width; text: root.userName; elide: Text.ElideRight; color: Theme.text
                                    font { family: Theme.font; pixelSize: 13; weight: Theme.w(Font.DemiBold) } }
                                Text { text: "Local Account"; color: Theme.textDim; font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 11 } }
                            }
                            Text { id: chev; anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                text: ""; color: Theme.textFaint; font { family: Theme.mono; pixelSize: 10 } }
                        }
                        Rectangle {
                            visible: root.query === ""
                            x: 8; width: parent.width - 16; height: 1
                            color: Qt.alpha(Theme.pal.fg, 0.08)
                        }
                        Item { visible: root.query === ""; width: 1; height: 8 }

                        Repeater {
                            model: root.query === "" ? root.pages : root.hits
                            delegate: Column {
                                required property var modelData
                                required property int index
                                readonly property var list: root.query === "" ? root.pages : root.hits
                                width: side.width
                                Item { width: 1; height: index > 0 && root.query === "" && parent.list[index - 1].section !== modelData.section ? 12 : 1 }
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
                            font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 12 }
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
                    width: parent.width; height: 56
                    // Above the scroller with an opaque fill: the software renderer doesn't clip
                    // Shapes (Badge), so a header icon scrolled up used to smear over the toolbar.
                    z: 1
                    Rectangle { anchors.fill: parent; color: Theme.bg }
                    Rectangle {
                        anchors.fill: nav; anchors.margins: -2
                        radius: height / 2; antialiasing: true
                        color: Qt.alpha(Theme.pal.fg, Theme.dark ? 0.07 : 0.05)
                        border { width: 1; color: Qt.alpha(Theme.pal.fg, 0.07) }
                    }
                    Row {
                        id: nav
                        x: 16; anchors.verticalCenter: parent.verticalCenter
                        spacing: 0
                        Repeater {
                            model: [["", () => root.goBack(), root.back.length > 0], ["", () => root.goForward(), root.forward.length > 0]]
                            MouseArea {
                                required property var modelData
                                width: 30; height: 28
                                enabled: modelData[2]
                                hoverEnabled: true
                                onClicked: modelData[1]()
                                Rectangle { anchors.fill: parent; radius: 14; antialiasing: true; color: parent.containsMouse && parent.enabled ? Theme.hover : "transparent" }
                                Text { anchors.centerIn: parent; text: parent.modelData[0]; color: parent.enabled ? Theme.text : Theme.textFaint
                                    font { family: Theme.mono; pixelSize: 12 } }
                            }
                        }
                    }
                    Text {
                        anchors { left: nav.right; leftMargin: 14; verticalCenter: parent.verticalCenter }
                        text: root.current.text
                        color: Theme.text
                        font { family: Theme.font; pixelSize: 17; weight: Theme.w(Font.Bold) }
                        // shows once the header card has scrolled away (Tahoe)
                        opacity: !heroCard.visible || scroller.contentY > heroCard.height - 20 ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }
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
                        width: Math.min(scroller.width - 48, 640)
                        x: (scroller.width - width) / 2; y: 4
                        spacing: 22

                        // Pane header: icon beside the title and description, left-aligned. Every
                        // pane but General, which draws its own.
                        Item {
                            id: heroCard
                            visible: root.current.id !== "general"
                            width: parent.width
                            height: visible ? Math.max(heroIcon.height, heroCol.implicitHeight) + 6 : 0
                            Badge {
                                id: heroIcon
                                x: 4; y: 2
                                width: 48; height: 48; radius: 12; glyphSize: 24
                                tint: root.current.tint; topColor: Qt.lighter(root.current.tint, 1.25); glyph: root.current.glyph
                            }
                            Column {
                                id: heroCol
                                anchors { left: heroIcon.right; leftMargin: 14; right: parent.right; rightMargin: 4 }
                                y: heroCol.implicitHeight < heroIcon.height ? heroIcon.y + (heroIcon.height - implicitHeight) / 2 : 0
                                spacing: 3
                                Text { text: root.current.text; color: Theme.text
                                    font { family: Theme.font; pixelSize: 22; weight: Theme.w(Font.Bold) } }
                                Text { width: parent.width; visible: text !== ""; text: root.current.about ?? ""
                                    wrapMode: Text.WordWrap; lineHeight: 1.15
                                    color: Theme.textDim; font { family: Theme.font; weight: Theme.fontWeight; pixelSize: 12 } }
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
            // island-settings in hypr/looks.lua, rounding 16).
            Rectangle {
                anchors.fill: parent
                z: 100
                radius: 16
                antialiasing: true
                color: "transparent"
                border { width: 1; color: Theme.dark ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(0, 0, 0, 0.12) }
            }
        }
    }
}
