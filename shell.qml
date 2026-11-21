// Software rendering: the bar is a small surface and the compositor does the blur, so the GPU
// buys nothing here, while loading NVIDIA's GL stack costs ~180 MB of RAM.
//@ pragma DefaultEnv QT_QUICK_BACKEND=software
// Fewer malloc arenas, so memory freed after closing a popout goes back to the system.
//@ pragma DefaultEnv MALLOC_ARENA_MAX=2
//@ pragma DefaultEnv MALLOC_TRIM_THRESHOLD_=131072
// Fixed mmap threshold: big buffers (decoded images, the grown surface) get their own mapping
// and go straight back to the system when freed, instead of glibc keeping them in the heap.
//@ pragma DefaultEnv MALLOC_MMAP_THRESHOLD_=65536
//@ pragma IconTheme MacTahoe
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs.services
import qs.settings
import qs.bar
import qs.widgets
import qs.dock
import qs.overlays

// Island: macOS-style menu bar, dock, desktop widgets, Spotlight, Launchpad and Settings, in one process.
//   qs -c island ipc call launcher toggle      (Spotlight)
//   qs -c island ipc call launchpad toggle
//   qs -c island ipc call overview toggle     (niri-style workspace overview)
//   qs -c island ipc call menu <system|app|notifs|controls|clipboard|power|sound|bluetooth|network|close>
//   qs -c island ipc call picker <wallpapers|wallhaven|themes|toggle|close>
//   qs -c island ipc call settings toggle
//   qs -c island ipc call notifs <toggle|dnd|clear|dismiss>
//   qs -c island ipc call media <toggle|playPause|next|previous|stop>
//   qs -c island ipc call volume <up|down|mute>
//   qs -c island ipc call widgets <toggle|show|hide>
//   qs -c island ipc call dock <toggle|autohide>
//   qs -c island ipc call lock <lock|preview|previewOff|previewOpen|status>
//   qs -c island ipc call screenshot <toolbar|region|window|screen|all>
// Popout contents only exist while open, so the idle cost is the bar itself.
ShellRoot {
    id: root

    // Drives (automount / mount at login) has to exist from the start; it idles while both are off.
    readonly property bool drivesWatching: Drives.watching

    Variants {
        model: Quickshell.screens
        Bar {}
    }

    // Desktop widgets (below windows, above the wallpaper)
    Variants {
        model: Quickshell.screens
        Widgets {}
    }

    // App icons on the desktop (Appearance → Layout); nothing is created while it's off.
    Variants {
        model: (Config.saved.desktopIcons ?? false) ? Quickshell.screens : []
        DesktopIcons {}
    }

    // Spotlight and Launchpad: created on open, destroyed (and collected) on close.
    readonly property var overlayScreen: Quickshell.screens.find(s => s.name === Popouts.overlayScreen) ?? Compositor.mainScreen
    LazyLoader { active: Popouts.spotlight; Spotlight { screen: root.overlayScreen } }
    LazyLoader { active: Popouts.launchpad; Launchpad { screen: root.overlayScreen } }
    LazyLoader { active: Popouts.overview; Overview { screen: root.overlayScreen } }
    Connections {
        target: Popouts
        function onSpotlightChanged() { if (!Popouts.spotlight) reclaim.restart(); }
        function onLaunchpadChanged() { if (!Popouts.launchpad) reclaim.restart(); }
        function onOverviewChanged() { if (!Popouts.overview) reclaim.restart(); }
    }
    Timer { id: reclaim; interval: 500; onTriggered: gc() }

    // Screenshots: toolbar (⇧⌘S) and the floating thumbnail, each only alive while shown.
    LazyLoader { active: Screenshot.toolbar; ScreenshotBar { screen: Quickshell.screens.find(s => s.name === Screenshot.toolbarScreen) ?? Compositor.mainScreen } }
    LazyLoader { active: Screenshot.shot !== ""; ScreenshotThumb { screen: Quickshell.screens.find(s => s.name === Screenshot.thumbScreen) ?? Compositor.mainScreen } }
    Connections {
        target: Screenshot
        function onToolbarChanged() { if (!Screenshot.toolbar) reclaim.restart(); }
        function onShotChanged() { if (Screenshot.shot === "") reclaim.restart(); }
    }
    IpcHandler {
        target: "screenshot"
        function toolbar(): void { Screenshot.toggleToolbar(); }
        function region(): void { Screenshot.capture("region"); }
        function window(): void { Screenshot.capture("window"); }
        function screen(): void { Screenshot.capture("screen"); }
        function all(): void { Screenshot.capture("all"); }
    }

    // In-place reload: new code, same surfaces, so windows don't re-tile (no lag like kill + start).
    // New fonts still need a full restart (Qt reads the font list once at launch).
    IpcHandler {
        target: "shell"
        function reload(): void { Quickshell.reload(false); }
    }

    IpcHandler {
        target: "overview"
        function toggle(): void { Popouts.toggleOverview(); }
        function open(): void { Popouts.openOverlay("overview"); }
        function close(): void { Popouts.closeOverlays(); }
    }

    IpcHandler {
        target: "launchpad"
        function toggle(): void { Popouts.toggleLaunchpad(); }
        function close(): void { Popouts.closeOverlays(); }
    }

    // Dock
    Variants {
        model: Quickshell.screens
        Dock {}
    }

    SettingsWindow { id: settings }
    // Hyprland global shortcuts (quickshell:launcher, …), bound in hypr/island.lua
    Shortcuts { settingsWin: settings }

    // Lock screen (ext-session-lock; any compositor). Also locks on `loginctl lock-session`.
    Lock { id: lock }
    IpcHandler {
        target: "lock"
        function lock(): void { Compositor.lock(); }
        function preview(): void { lock.previewing = !lock.previewing; }
        function previewOff(): void { lock.previewing = false; }
        function previewOpen(): bool { return lock.previewing; }
        function status(): string { return LockState.locked ? "locked" : "unlocked"; }
    }
    Connections { target: Popouts; function onSettingsRequested() { if (Popouts.settingsPage) settings.page = Popouts.settingsPage; Popouts.settingsPage = ""; settings.open = true; } }

    IpcHandler {
        target: "launcher"
        function toggle(): void { Popouts.toggleSpotlight(); }
        function open(): void { Popouts.openOverlay("spotlight"); }
        function close(): void { Popouts.closeOverlays(); }
    }

    IpcHandler {
        target: "menu"
        function launcher(): void { Popouts.toggleSpotlight(); }
        function dash(): void { Popouts.toggle("notifs"); }
        function notifs(): void { Popouts.toggle("notifs"); }
        function system(): void { Popouts.toggle("system"); }
        function app(): void { Popouts.toggle("app"); }
        function controls(): void { Popouts.toggle("controls"); }
        function media(): void { Popouts.toggle("media"); }
        function clipboard(): void { Popouts.toggle("clipboard"); }
        function power(): void { Popouts.toggle("power"); }
        function sound(): void { Popouts.toggle("sound"); }
        function bluetooth(): void { Popouts.toggle("bluetooth"); }
        function network(): void { Popouts.toggle("network"); }
        function close(): void { Popouts.close(); }
    }

    IpcHandler {
        target: "picker"
        function wallpapers(): void { Popouts.toggle("wallpapers"); }
        function wallhaven(): void { Popouts.toggle("wallhaven"); }
        function themes(): void { Popouts.toggle("themes"); }
        function toggle(): void { ["wallpapers", "wallhaven", "themes"].includes(Popouts.current) ? Popouts.close() : Popouts.open("wallpapers"); }
        function close(): void { Popouts.close(); }
    }

    IpcHandler {
        target: "settings"
        function toggle(): void { settings.open = !settings.open; }
        function open(): void { settings.open = true; }
        function close(): void { settings.open = false; }
        function page(name: string): void { settings.page = name; settings.open = true; }
        // qs -c island ipc call settings set gapsIn 8      (values are JSON; bare words are strings)
        function set(key: string, value: string): string {
            if (!(key in Config.defaults)) return "unknown setting: " + key;
            let v; try { v = JSON.parse(value); } catch (e) { v = value; }
            Config.commit(key, v);     // IPC changes apply immediately, without saving staged UI edits
            return "ok";
        }
        function get(key: string): string { return JSON.stringify(Config.values[key]); }
    }

    IpcHandler {
        target: "notifs"
        function toggle(): void { Popouts.toggle("notifs"); }
        function dnd(): void { Notifs.setDnd(!Notifs.dnd); }
        function clear(): void { Notifs.clear(); }
        function dismiss(): void { Notifs.dismissLatest(); }
    }

    IpcHandler {
        target: "media"
        function toggle(): void { Popouts.toggle("media"); }
        function playPause(): void { Media.playPause(); }
        function next(): void { Media.next(); }
        function previous(): void { Media.previous(); }
        function stop(): void { Media.stop(); }
        function status(): string { return Media.player ? (Media.playing ? "playing: " : "paused: ") + Media.title + (Media.artist ? " - " + Media.artist : "") : "none"; }
    }

    // qs -c island ipc call weather location "Lisbon, Portugal"   ("" = automatic)
    IpcHandler {
        target: "weather"
        function toggle(): void { Popouts.toggle("weather"); }
        function refresh(): void { Weather.refresh(); }
        function location(place: string): void { Config.commit("weatherLocation", place.trim()); }
        function units(u: string): void { if (u === "c" || u === "f") Config.commit("weatherUnits", u); }
        function status(): string {
            return Weather.badLocation ? "unknown location: " + Weather.location : Weather.ok ? Weather.place + ": " + Weather.temp + "°, " + Weather.desc + " (H " + Weather.hi + "° L " + Weather.lo + "°)"
                              : Weather.failed ? "unavailable" : "loading";
        }
    }

    IpcHandler {
        target: "volume"
        function up(): void { Audio.nudge(0.05); }
        function down(): void { Audio.nudge(-0.05); }
        function mute(): void { Audio.toggleMute(); }
    }

    IpcHandler {
        target: "widgets"
        function toggle(): void { Config.commit("widgets", !(Config.saved.widgets ?? true)); }
        function show(): void { Config.commit("widgets", true); }
        function hide(): void { Config.commit("widgets", false); }
        function edit(): void { WidgetLayout.edit(""); }
        function reset(): void { WidgetLayout.reset(); }
        function style(): void { Config.commit("widgetStyle", WidgetLayout.tahoe ? "classic" : "tahoe"); }
    }

    IpcHandler {
        target: "dock"
        function toggle(): void { Config.commit("dock", !(Config.saved.dock ?? true)); }
        function autohide(): void { Config.commit("dockAutohide", !(Config.saved.dockAutohide ?? false)); }
    }

    // qs -c island ipc call tray menu 0   (opens the Nth tray icon's menu)
    IpcHandler {
        target: "tray"
        function menu(i: int): void { const it = SystemTray.items.values[i]; if (it?.hasMenu) Popouts.trayMenu(it); }
        function list(): string { return SystemTray.items.values.map((it, i) => i + ": " + (it.tooltipTitle || it.title || it.id)).join("\n"); }
    }

    IpcHandler {
        target: "caffeine"
        function toggle(): void { Popouts.caffeine = !Popouts.caffeine; }
    }

    // Switching workspace closes whatever is open.
    Connections {
        target: Compositor
        function onWorkspaceChanged() { Popouts.close(); Popouts.closeOverlays(); settings.open = false; }
    }
}
