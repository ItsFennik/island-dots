# Desktop widgets

Widgets sit below windows and above the wallpaper: clock, weather, calendar, now playing, system stats and verse of the day.

- Config: `widgets/`, `services/WidgetLayout.qml`, `widgets/WidgetEditor.qml`
- Settings: Desktop & Widgets
- IPC: `qs -c island ipc call widgets <toggle|show|hide|edit|reset|style>`

Positions are stored in `widgetPos` and sizes in `widgetSize`. Empty positions stack in the `widgetsPosition` corner. Drag a widget to move it, right-click it to edit, or use Settings > Widgets > Arrange widgets.

Two styles exist: Tahoe (frosted, monochrome) and Classic (material, colour accents). Widget colours follow the system, the theme, or the wallpaper via `services/WallColors.qml`. The weather uses wttr.in; the verse uses `scripts/votd.sh` and falls back to a bundled verse offline.

Widgets are created only while `widgets` is true. Surface namespace: `island-widgets`.
