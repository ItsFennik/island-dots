# Spotlight and Launchpad

![Spotlight](../screenshots/island-launcher.png)

- `island-spotlight` (Rust, `rust/`): apps, files, math, `>` shell commands, web
  search, history and the bar-skin switcher. Reads `~/.config/island/settings.json`
  and the active theme, so it follows every bar layout.
- `overlays/Launchpad.qml`: the full app grid.
- `services/Apps.qml`: desktop-entry index, search and launch counts.
- `services/SpotHistory.qml`: `~/.local/state/island/spotlight.json` (also used by
  the Rust Spotlight).

IPC:

```sh
qs -c island ipc call launcher toggle
qs -c island ipc call launcher open
qs -c island ipc call launcher close
qs -c island ipc call launchpad toggle
qs -c island ipc call menu launcher
```

The Rust Spotlight is created on open and lingers for two minutes for instant
reopens; writing `settings.json` restarts it, so a new style or skin applies on
the next open. Auto opens the macOS card at the top on every bar (translucent,
frosted where the compositor blurs layer surfaces). Dynamic Island and Notch can grow it out of the capsule instead
(`spotlightFromCapsule`), and `spotlightStyle` can force Attached, Floating or
Capsule. `spotlightMonitor` picks the display: Auto follows the pointer on Mango
and Hyprland, Focused follows the active output, Main display follows
`mainScreen`, or a named output can be pinned. The monitor is re-resolved on
every open, including from the running window. `spotlightWidth`, `spotlightRows`,
`spotlightFiles`, `spotlightCommands` and `spotlightWeb` are the other relevant
settings.

History and launch counts live under `~/.local/state/island/`. `Ctrl+F` pins the
selected row; `Shift+Delete` forgets it. Spotlight's `>` mode runs the command with
a shell in `$HOME`.

Bind them from your compositor with the commands above; the shipped examples use
Super+D and Super+A. See [Keybinds](../keybinds.md).
