# Spotlight and Launchpad

![Spotlight](../screenshots/island-launcher.png)

- `overlays/Spotlight.qml`: apps, files, math, `>` shell commands, web search, history
- `overlays/Launchpad.qml`: the full app grid
- `services/Apps.qml`: desktop-entry index, search and launch counts
- `services/SpotHistory.qml`: `~/.local/state/island/spotlight.json`

IPC:

```sh
qs -c island ipc call launcher toggle
qs -c island ipc call launchpad toggle
qs -c island ipc call menu launcher
```

Both overlays are created on open and destroyed on close. Search history and launch counts are stored under `~/.local/state/island/`. `Ctrl+F` pins a frequently used row. Spotlight's `>` mode runs the command with a shell in `$HOME`.

Bind them from your compositor with the commands above; the shipped examples use Super+D and Super+A. See [Keybinds](../keybinds.md).
