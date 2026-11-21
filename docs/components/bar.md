# Menu bar

The menu bar is `bar/Bar.qml`; `CompactBar.qml` and `Taskbar.qml` are the two alternate layouts.

- Config: `bar/`, layout in `~/.config/island/settings.json`
- Surface namespace: `island-bar`
- Settings: Appearance > Layout, Menu Bar, Menu Bar Items
- IPC: none dedicated; menus open through `qs -c island ipc call menu ...`

The left zone holds the logo menu and the focused app's menu, the centre holds workspaces, the right holds tray, status, weather and the clock. Moving across menu titles switches menus. `services/BarLayout.qml` stores the item order for the editor.

`apply-settings.sh` writes the bar height and blur values into the compositor config. Hyprland and niri layer rules for `island-bar` live in `examples/`. MangoWC blurs whole surfaces, so its Island layers use `no_blur`.

Keybinds are in [Keybinds](../keybinds.md).
