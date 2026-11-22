# Menu bar

The menu bar is `bar/Bar.qml`; `CompactBar.qml` and `Taskbar.qml` are the two alternate layouts.

- Config: `bar/`, layout in `~/.config/island/settings.json`
- Surface namespace: `island-bar`
- Settings: Appearance > Layout, Menu Bar, Menu Bar Items
- IPC: `qs -c island ipc call bar <skin NAME|next|previous>`; menus open through `qs -c island ipc call menu ...`

The left zone holds the logo menu and the focused app's menu, the centre holds workspaces, the right holds tray, status, weather and the clock. Moving across menu titles switches menus. `services/BarLayout.qml` stores the item order for the editor.

## Skins

Setting `barSkin` (Appearance > Layout, or type "skin" in Spotlight) restyles the menu bar layout:

| Skin | Look |
|---|---|
| `classic` | the full-width strip |
| `pills` | every item in its own floating pill (add **Now playing** under Menu Bar Items for the song) |
| `island` | nothing but a black capsule in the centre showing the time (no other items) |
| `notch` | nothing but a black MacBook-style notch at the top edge showing the time (no other items) |

In both, the capsule grows for a
notification, a volume change, a new track, or media controls while hovered with a player. Every
menu grows out of the capsule and shrinks back into it. Click the capsule for notifications (or the
player while music plays), right-click for Control Centre, scroll for volume.

`apply-settings.sh` writes the bar height and blur values into the compositor config. Hyprland and niri layer rules for `island-bar` live in `examples/`. MangoWC blurs whole surfaces, so its Island layers use `no_blur`.

Keybinds are in [Keybinds](../keybinds.md).
