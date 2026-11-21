# Troubleshooting

Check `qs log -c island` first. A clean load ends with `Configuration Loaded`; a QML error keeps the old version running.

## `Could not find "default" config directory or shell.qml in any valid config path.`

Quickshell was started without a matching config. Island lives at `~/.config/quickshell/island` and must be started with `qs -c island`, not bare `qs`. Re-run the installer or create the symlink:

```sh
ln -sfn /path/to/island-dots ~/.config/quickshell/island
qs -c island
```

## Settings is empty, "No Results", or `ReferenceError: Compositor is not defined`

This is a hot-reload race: the Settings window was created while the `Compositor` singleton was reloading. The shell can recover without losing the session:

```sh
qs -c island ipc call shell reload
```

If it persists, restart the shell:

```sh
qs -c island kill
~/.config/quickshell/island/scripts/island-startup
```

Do not use `pkill -f "qs -c island"`; the pattern matches the shell that runs the command.

## `error: neither awww nor swww found`

Install the wallpaper backend:

```sh
# Arch
sudo pacman -S awww
# Fedora
sudo dnf install awww
# Void
sudo xbps-install awww
# Alpine
sudo apk add awww
```

Debian and Ubuntu may need a build from source. The older `swww` command is also accepted.

## `No wallpaper backend`

Same cause as above. `wallpaper-set.sh` prints the notification `No wallpaper backend` when neither command exists.

## `matugen not installed`

Material You is optional. Either install matugen or turn off Settings > Appearance > Match the wallpaper. A theme without matugen works normally.

## Videos do not play as wallpaper

Install `mpvpaper` and `ffmpeg`. Video wallpapers also need the poster cache; run:

```sh
~/.config/quickshell/island/scripts/wallpaper-set.sh --thumbs
```

## Power menu, Sleep, Restart or Shut Down do nothing

Test the backend in a terminal:

```sh
~/.config/quickshell/island/scripts/island-power status
~/.config/quickshell/island/scripts/island-power --dry-run suspend
```

If it reports `generic` and a missing root helper, install `elogind`, configure passwordless `doas`/`sudo` for the command, or set `ISLAND_SUSPEND_CMD`, `ISLAND_REBOOT_CMD` and `ISLAND_POWEROFF_CMD`. See [Non-systemd](non-systemd.md).

## Notifications do not appear

Another daemon may own `org.freedesktop.Notifications`. Stop `dunst`, `mako`, `swaync` or whichever starts in your compositor. Test with:

```sh
notify-send -a Island "Island" "Test"
```

In Island, `qs -c island ipc call notifs toggle` opens the centre.

## Clipboard history is empty

Install `cliphist` and `wl-clipboard`. The watchers are started by `island-startup`; check for `wl-paste --type text --watch cliphist store` in `pgrep -af wl-paste`.

## Lock screen does not open from `loginctl lock-session`

`loginctl` needs logind or elogind and a listener with `XDG_SESSION_ID`. Use Island directly:

```sh
qs -c island ipc call lock lock
# or
scripts/island-power lock
```

## `SDDM isn't installed (e.g. sudo dnf install sddm / pacman -S sddm / apt install sddm).`

Install SDDM before running `sddm/install.sh`. The theme is optional; Island's own lock screen does not need SDDM.

## `Could not detect how to enable SDDM.`

The installer did not find systemd, OpenRC, runit or dinit. Enable the `sddm` service with your init system after the theme is installed. Use `./sddm/install.sh --theme` to skip display-manager switching.

## Screenshots fail or slurp cancels

`scripts/screenshot.sh` needs `grim`, `slurp` and `wl-clipboard`. The log is `$XDG_RUNTIME_DIR/island-screenshot.log`. A cancelled selection exits 1 by design.

## `island-startup: no dbus session bus and no dbus-run-session/dbus-launch`

Install the dbus user tools or start the session through `scripts/island-session`, which wraps the compositor in `dbus-run-session`.

## XDG_RUNTIME_DIR is missing

`island-startup` and `island-session` create it if needed. If you launch Quickshell directly, export it yourself or use the startup script.

## Polkit prompts never open

Start a polkit agent. `island-startup` starts one if it finds `polkit-gnome-authentication-agent-1`, `lxpolkit`, `lxqt-policykit-agent` or `mate-polkit`. Install one or set `ISLAND_POLKIT_AGENT`.
