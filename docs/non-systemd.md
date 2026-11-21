# Non-systemd sessions

Island does not require systemd. The compositor starts `scripts/island-startup`, which handles the user-session pieces that a systemd user manager would otherwise provide. systemd is detected and supported, but it is one path among several.

## What runs

```
island-session -- <compositor>       optional: creates XDG_RUNTIME_DIR and a dbus bus
  └─ compositor                       Hyprland, niri, Sway, MangoWC, ...
       └─ island-startup              from exec-once / spawn-at-startup
            ├─ XDG_RUNTIME_DIR
            ├─ dbus session bus       when missing
            ├─ PipeWire + WirePlumber when no systemd user manager
            ├─ cliphist watchers
            ├─ polkit agent           if one is installed and none is running
            ├─ wallpaper-set.sh --restore
            └─ qs -c island
```

`island-startup` is idempotent. It uses `$XDG_RUNTIME_DIR/island-startup.lock` to avoid running twice, and it skips services that are already running. Logs go to `$XDG_STATE_HOME/island/logs/startup.log`, normally `~/.local/state/island/logs/startup.log`. stdout is also used when `--foreground` is set.

## Session entry

The simplest non-systemd setup starts the compositor from a tty or display manager through `island-session`:

```sh
~/.config/quickshell/island/scripts/island-session -- mango
~/.config/quickshell/island/scripts/island-session -- Hyprland
~/.config/quickshell/island/scripts/island-session -- niri
~/.config/quickshell/island/scripts/island-session -- sway
```

It creates `XDG_RUNTIME_DIR` if needed and runs the compositor under `dbus-run-session`. That gives every app the compositor starts the same session bus. If `DBUS_SESSION_BUS_ADDRESS` already exists, it execs the compositor directly.

The compositor then runs `island-startup` from its exec-once line. This is already in `examples/`.

If you start the compositor without `island-session`, `island-startup` still starts a private bus for the shell and the helpers it launches, using `dbus-run-session` or `dbus-launch`. Apps launched directly by the compositor will not inherit that bus. Use `island-session` when you can.

## Power and session actions

All menus and keybinds call `scripts/island-power`:

```sh
scripts/island-power poweroff
scripts/island-power reboot
scripts/island-power suspend
scripts/island-power hibernate
scripts/island-power logout
scripts/island-power lock
scripts/island-power status
scripts/island-power --dry-run suspend
```

Backend detection:

1. `systemd` when `/run/systemd/system` exists and `systemctl` is available.
2. `logind` when `loginctl show-session self` works, which covers systemd-logind and elogind.
3. `openrc` when `openrc-shutdown` exists.
4. `generic` otherwise, using `shutdown`, `poweroff`, `reboot`, `zzz` or `pm-suspend` with `doas`, `sudo` or `pkexec`.

Hibernate has no portable fallback in plain init systems. Use logind/elogind, or set `ISLAND_HIBERNATE_CMD`. Every action also accepts an override:

```sh
export ISLAND_POWEROFF_CMD='openrc-shutdown --poweroff now'
export ISLAND_REBOOT_CMD='openrc-shutdown --reboot now'
export ISLAND_SUSPEND_CMD='zzz'
export ISLAND_HIBERNATE_CMD='zzz -Z'
export ISLAND_LOGOUT_CMD='mmsg quit'
```

From a GUI there is no terminal for a sudo prompt. The wrapper uses `doas -n` or `sudo -n` in that case. Configure a passwordless rule for the specific power command, or rely on elogind/logind, which uses polkit.

## Init-specific setup

### OpenRC (Artix, Alpine, Gentoo)

```sh
# System bus and services
rc-update add dbus default
rc-update add NetworkManager default
rc-update add bluetoothd default
rc-update add seatd default          # or rc-update add elogind default
rc-service dbus start
rc-service NetworkManager start
rc-service bluetoothd start
rc-service seatd start               # or rc-service elogind start
```

Add your user to the `seat` group when using seatd, then log out and back in. elogind provides `loginctl`, including `lock-session` and suspend/shutdown. Without elogind, use `island-power` for locks and shutdown.

Your display manager package provides an init script, for example `/etc/init.d/sddm`. `sddm/install.sh` uses `rc-update add sddm default` when it sees OpenRC.

### runit (Void, Artix-runit)

```sh
ln -s /etc/sv/dbus /var/service/dbus
ln -s /etc/sv/NetworkManager /var/service/NetworkManager
ln -s /etc/sv/bluetoothd /var/service/bluetoothd
ln -s /etc/sv/seatd /var/service/seatd          # or elogind
```

`island-startup` starts PipeWire, WirePlumber and `pipewire-pulse` for the user when no systemd user manager exists. Keep the system-level runit services for dbus, seatd/elogind and NetworkManager.

### s6

Enable your system's s6-rc services for dbus, NetworkManager, BlueZ and seatd or elogind. There is no user service tree in this repository because Island's processes are started by the compositor. Use `island-startup` in the compositor config and `island-session` as the session command.

### dinit

```sh
dinitctl enable dbus
dinitctl enable NetworkManager
dinitctl enable bluetoothd
dinitctl enable seatd          # or elogind
```

`sddm/install.sh` calls `dinitctl enable sddm` when it detects dinit.

### systemd

No change to the existing setup. Use the compositor autostart, or install the optional user unit:

```sh
./install.sh --autostart systemd --enable
```

The unit runs `island-startup --foreground --no-pipewire`, so systemd supervises Quickshell and PipeWire stays with its own user units. Remove the compositor's `island-startup` line if you use the unit.

## Command mapping

| systemd command | Replacement |
|---|---|
| `systemctl --user start island` | `scripts/island-startup` or `systemctl --user start island` when using the unit |
| `systemctl --user stop island` | `qs -c island kill` |
| `systemctl --user status island` | `qs list --all` and `qs log -c island` |
| `systemctl suspend` | `island-power suspend` |
| `systemctl reboot` | `island-power reboot` |
| `systemctl poweroff` | `island-power poweroff` |
| `loginctl lock-session` | `island-power lock` or `qs -c island ipc call lock lock` |
| `loginctl terminate-session` | `island-power logout` |
| `journalctl --user-unit island` | `qs log -c island`; startup helpers write `~/.local/state/island/logs/startup.log` |
| `systemd-run --user` | `setsid -f <command>` or `nohup <command> &`, as used by `island-startup` |
| `systemd-inhibit` | no direct replacement; use the compositor's idle inhibitor or `island-power` |
| `hostnamectl` | `hostname` and your distro's hostname file |
| `timedatectl` | `date`, `timedatectl` from util-linux, or your init's time service |
| `localectl` | edit `/etc/locale.conf` and your keyboard layout config |
| `systemctl enable sddm` | `sddm/install.sh` detects systemd, OpenRC, runit or dinit |
| `XDG_RUNTIME_DIR` from pam_systemd | `island-session` or `island-startup` creates it |
| dbus from systemd --user | `island-session` (preferred) or the startup fallback |
| PipeWire user units | `island-startup` starts PipeWire when no user manager exists |

## seat, logind and polkit

- **seatd**: gives the compositor access to input and DRM devices without logind. elogind/`loginctl` features such as `lock-session` and suspend are then unavailable; use `island-power` instead.
- **elogind**: provides logind on non-systemd systems, including `loginctl` and DBus lock/suspend signals. Island's lock screen listens for the logind `Lock` signal when `XDG_SESSION_ID` is set.
- **polkit**: GUI authentication needs an agent. `island-startup` starts one if `polkit-gnome-authentication-agent-1`, `lxpolkit`, `lxqt-policykit-agent` or `mate-polkit` is installed. Set `ISLAND_POLKIT_AGENT` to a command to override, or `--no-polkit` to disable.

## What was tested

- Fedora 45, systemd user manager, MangoWC: `island-startup --dry-run`, `island-power --dry-run/status`, Settings, lock preview and the shell were exercised.
- OpenRC, runit, s6, dinit and elogind/seatd were **not** tested on real machines. The detection and commands are best effort. `island-power` and `island-startup` are shellcheck clean and syntax checked.
- Run `scripts/island-power --dry-run <action>` and `scripts/island-startup --dry-run` on the target system before relying on them.
