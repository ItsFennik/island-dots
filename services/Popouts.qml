pragma Singleton
import QtQuick
import Quickshell

// Which bar popout is open, and on which monitor. Every menu grows out of the bar,
// so only one can be open at a time (menus drop down from the menu bar). Opening the open one again closes it.
//   names: system | app | controls | clipboard | power | wallpapers | wallhaven | themes | notifs | media | weather | tray
Singleton {
    id: root

    property string current: ""
    property string screen: ""            // ShellScreen.name the popout lives on
    property bool caffeine: false         // idle inhibitor (held by the bar)
    property var trayItem: null           // SystemTrayItem whose menu the "tray" popout shows
    signal settingsRequested()
    property string settingsPage: ""      // page for the next settingsRequested ("" = keep)
    function openSettings(page) { settingsPage = page || ""; settingsRequested(); }
    property int ddc: -2                  // monitor brightness via ddcutil: -2 unknown, -1 unsupported

    function toggle(name, screenName) {
        if (current === name) { close(); return; }
        open(name, screenName);
    }
    function open(name, screenName) {
        screen = screenName || Compositor.screenName();
        current = name;
    }
    function close() { current = ""; }

    // Full-screen / floating overlays (separate windows, created only while open).
    property bool spotlight: false
    property bool launchpad: false
    property bool overview: false
    property string overlayScreen: ""
    function openOverlay(which) {
        close();
        overlayScreen = Compositor.screenName();
        spotlight = which === "spotlight";
        launchpad = which === "launchpad";
        overview = which === "overview";
    }
    function toggleSpotlight() { spotlight ? closeOverlays() : openOverlay("spotlight"); }
    function toggleLaunchpad() { launchpad ? closeOverlays() : openOverlay("launchpad"); }
    function toggleOverview() { overview ? closeOverlays() : openOverlay("overview"); }
    function closeOverlays() { spotlight = false; launchpad = false; overview = false; }
    // Right-click on a tray icon: open its menu; the same icon again closes it.
    function trayMenu(item, screenName) {
        if (current === "tray" && trayItem === item) { close(); return; }
        trayItem = item;
        open("tray", screenName);
    }
}
