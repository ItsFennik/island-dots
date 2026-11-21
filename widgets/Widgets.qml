import QtQuick
import Quickshell
import qs.services

// Desktop widgets, each in its own small layer surface above the wallpaper.
// Right-click one (or `ipc call widgets edit`) to move them; positions live in WidgetLayout.
Scope {
    id: root

    required property ShellScreen modelData
    readonly property var s: Config.saved
    readonly property bool primary: Quickshell.screens.length === 0 || Compositor.mainScreen === modelData
    readonly property bool shown: (s.widgets ?? true) && ((s.widgetsAllScreens ?? false) || primary)

    Component { id: cWeather; WeatherWidget { size: WidgetLayout.size("weather") } }
    Component { id: cCalendar; CalendarWidget { size: WidgetLayout.size("calendar"); screenName: root.modelData.name } }
    Component { id: cClock; ClockWidget { size: WidgetLayout.size("clock") } }
    Component { id: cMusic; MusicWidget { size: WidgetLayout.size("music"); screenName: root.modelData.name } }
    Component { id: cSystem; SystemWidget { size: WidgetLayout.size("system") } }
    Component { id: cVerse; VerseWidget { size: WidgetLayout.size("verse") } }
    readonly property var comps: ({ weather: cWeather, calendar: cCalendar, clock: cClock, music: cMusic, system: cSystem, verse: cVerse })

    Variants {
        model: root.shown ? WidgetLayout.ids : []
        WidgetWin {
            required property var modelData
            wid: modelData
            screen: root.modelData
            content: root.comps[modelData]
        }
    }

    // Edit Widgets: on the monitor it was opened from (IPC: the primary one).
    LazyLoader {
        active: WidgetLayout.editing && root.shown
                && (WidgetLayout.editScreen ? WidgetLayout.editScreen === root.modelData.name : root.primary)
        WidgetEditor { screen: root.modelData }
    }
}
