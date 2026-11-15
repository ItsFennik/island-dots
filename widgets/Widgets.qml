import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// Desktop widgets (macOS style) on the layer just above the wallpaper, below windows.
// One stack per monitor, pinned to the corner picked in Settings → Widgets.
//   qs -c island ipc call widgets toggle
PanelWindow {
    id: win

    required property ShellScreen modelData
    screen: modelData

    readonly property var s: Config.saved
    readonly property string corner: s.widgetsPosition ?? "top-left"
    readonly property bool onRight: corner.endsWith("right")
    readonly property int margin: s.widgetsMargin ?? 24
    readonly property bool all: s.widgetsAllScreens ?? false
    readonly property bool primary: Quickshell.screens.length === 0 || Quickshell.screens[0] === modelData

    readonly property bool wClock: s.widgetClock ?? true
    readonly property bool wWeather: s.widgetWeather ?? true
    readonly property bool wCalendar: s.widgetCalendar ?? true
    readonly property bool wMusic: s.widgetMusic ?? true
    readonly property bool wSystem: s.widgetSystem ?? true

    visible: (s.widgets ?? true) && (all || primary) && (wClock || wWeather || wCalendar || wMusic || wSystem)

    anchors { top: corner.startsWith("top"); bottom: corner.startsWith("bottom"); left: !onRight; right: onRight }
    // the surface reaches `shadow` px past the cards so their shadows aren't cut off
    readonly property int shadow: 14
    margins { top: Math.max(0, margin - shadow); bottom: Math.max(0, margin - shadow); left: Math.max(0, margin - shadow); right: Math.max(0, margin - shadow) }
    exclusionMode: ExclusionMode.Normal      // stay clear of the bar
    exclusiveZone: 0
    implicitWidth: stack.implicitWidth + shadow * 2
    implicitHeight: stack.implicitHeight + shadow * 2
    color: "transparent"

    WlrLayershell.namespace: "island-widgets"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Column {
        id: stack
        x: win.shadow; y: win.shadow
        spacing: 14

        // Small pair; whichever is alone takes the full width.
        Row {
            visible: win.wClock || win.wWeather
            spacing: 14
            layoutDirection: win.onRight ? Qt.RightToLeft : Qt.LeftToRight
            Loader { active: win.wClock; visible: active; sourceComponent: ClockWidget {} }
            Loader { active: win.wWeather; visible: active; sourceComponent: WeatherWidget { wide: !win.wClock } }
        }
        Loader { active: win.wCalendar; visible: active; sourceComponent: CalendarWidget { wide: true; screenName: win.screen.name } }
        Loader { active: win.wMusic; visible: active; sourceComponent: MusicWidget { screenName: win.screen.name } }
        Loader { active: win.wSystem; visible: active; sourceComponent: SystemWidget {} }
    }
}
