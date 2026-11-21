# Shell

`shell.qml` creates one window per screen for the bar and widgets, the dock, and the lazy overlays. It also owns every IPC target.

- Config: `shell.qml`
- Start: `scripts/island-startup` or `qs -c island`
- Logs: `qs log -c island`
- Reload: `qs -c island ipc call shell reload`
- Stop: `qs -c island kill`

IPC targets are declared in `shell.qml` and listed in the README and `docs/keybinds.md`. A few examples:

```sh
qs -c island ipc call launcher toggle
qs -c island ipc call menu notifs
qs -c island ipc call menu controls
qs -c island ipc call settings page appearance
qs -c island ipc call lock lock
qs -c island ipc call screenshot region
```

Popouts and overlays are created only while open. Keep new surfaces lazy; the idle cost should stay at the bar.

Settings are read through `Config.saved` and `Config.values`. Writes use `Config.commit(key, value)`. See [Settings](settings.md).

## Compositor and session

The shell never calls `systemctl` directly. Power and logout go through `scripts/island-power`. Compositor-specific behaviour lives in `services/Compositor.qml`. The lock screen and notifications listen to normal Wayland and D-Bus protocols, so they survive a compositor restart where the protocol allows it.

Startup is described in [Non-systemd](../non-systemd.md).
