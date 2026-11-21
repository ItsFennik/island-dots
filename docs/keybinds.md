# Keybinds

Every Island action is an IPC call, so the same command works from any compositor:

```sh
qs -c island ipc call <target> <function> [args]
```

## Compositor binds shipped in `examples/`

| Action | Keys | IPC command | Hyprland | niri | Sway | MangoWC |
|---|---|---|:-:|:-:|:-:|:-:|
| Spotlight | Super+D | `launcher toggle` | yes | yes | yes | yes |
| Launchpad | Super+A | `launchpad toggle` | yes | yes | yes | yes |
| Notification Centre | Super+C | `menu notifs` | yes | yes | yes | yes |
| Clipboard history | Super+V | `menu clipboard` | yes | yes | yes | yes |
| Media | Super+M | `menu media` | yes | yes | yes | yes |
| System Settings | Super+I | `settings toggle` | yes | yes | yes | yes |
| Wallpaper picker | Super+W | `picker wallpapers` | yes | yes | yes | yes |
| Theme picker | Super+Alt+W | `picker themes` | yes | yes | yes | yes |
| Power menu | Super+Escape | `menu power` | yes | yes | yes | yes |
| Lock | Super+Ctrl+Q | `lock lock` | yes | yes | yes | yes |
| Random wallpaper | Super+Shift+W | `scripts/wallpaper-set.sh --random` | yes | no | no | no |
| Random Wallhaven | Super+Ctrl+W | `scripts/wallhaven.sh random` | yes | no | no | no |
| Volume up | XF86AudioRaiseVolume | `volume up` | not in example | yes | yes | yes |
| Volume down | XF86AudioLowerVolume | `volume down` | not in example | yes | yes | yes |
| Mute | XF86AudioMute | `volume mute` | not in example | yes | yes | yes |
| Play/pause | XF86AudioPlay | `media playPause` | not in example | yes | yes | yes |
| Next track | XF86AudioNext | `media next` | not in example | yes | yes | yes |
| Previous track | XF86AudioPrev | `media previous` | not in example | yes | yes | yes |

Hyprland's example uses `hl.bind`. If you use the global-shortcut interface instead, `Shortcuts.qml` publishes `quickshell:<name>` names through `hl.dsp.global("quickshell:<name>")`.

## Island shortcut names

`Shortcuts.qml` exposes these names on the Hyprland global-shortcut protocol and on `$XDG_RUNTIME_DIR/island.sock` for Mango:

| Name | Action |
|---|---|
| `launcher` | Spotlight |
| `launchpad` | Launchpad |
| `overview` | Workspace overview |
| `notifs` | Notification Centre |
| `dnd` | Toggle Do Not Disturb |
| `clipboard` | Clipboard history |
| `power` | Power menu |
| `controlcenter` | Control Centre |
| `media` | Media popout |
| `wallpaper` | Wallpaper picker |
| `theme` | Theme picker |
| `settings` | System Settings |
| `lock` | Lock screen |
| `screenshot` | Selection screenshot |
| `screenshotWindow` | Window screenshot |
| `screenshotScreen` | Screen screenshot |
| `screenshotToolbar` | Screenshot toolbar |
| `volumeUp`, `volumeDown`, `volumeMute` | Audio |
| `mediaPlayPause`, `mediaNext`, `mediaPrevious`, `mediaStop` | Media |

Mango's helper writes the name to the socket. Hyprland binds the name, for example:

```lua
hl.bind("SUPER + D", hl.dsp.global("quickshell:launcher"))
```

## Shortcuts suggested by Settings

Settings > Keyboard > Keyboard Shortcuts lists the layout the shell is designed for. These are suggestions; only the binds in your compositor file are active.

| Action | Keys |
|---|---|
| Spotlight | Super+D |
| Launchpad | Super+A |
| Notification Centre | Super+C |
| Control Centre, Music | Super+M |
| System Settings | Super+I |
| Clipboard history | Super+V |
| Wallpaper | Super+W |
| Random wallpaper | Super+Shift+W |
| Themes | Super+Alt+W |
| Power | Super+Escape |
| Screenshot selection, window, screen | Print, Alt+Print, Shift+Print |
| Screenshot toolbar | Super+Shift+S |
| Terminal | Super+T |
| Files | Super+E |
| Browser | Super+B |
| Close window, fullscreen, float, pin | Super+Q, Super+F, Super+Shift+T, Super+P |
| Desktop 1 to 9, move window to desktop | Super+1 to 9, Super+Shift+1 to 9 |
| Scratch desktop, send window to it | Super+Space, Super+Shift+Space |
| Focus and move windows | Super+arrows or H J K L, Shift+Super+arrows or H J K L |

## Terminal and editor

Terminal and editor configs are not part of this repository. Island only chooses the terminal command through `TERMINAL` (falling back to `foot`) and themes kitty, Foot and Neovim. Add your own kitty, Foot and Neovim binds in their own configuration files; they are not managed by Island.

## Power and session commands

| Command | Does |
|---|---|
| `scripts/island-power lock` | Locks through Island, then loginctl, then hyprlock |
| `scripts/island-power logout` | Leaves the compositor session |
| `scripts/island-power suspend` | Suspends through systemd, logind, OpenRC or the fallback |
| `scripts/island-power reboot` | Reboots |
| `scripts/island-power poweroff` | Powers off |
| `scripts/island-power status` | Prints the detected backend |
| `scripts/island-power --dry-run <action>` | Prints the command without running it |

Use these in idle daemons instead of `loginctl`, for example `swayidle timeout 300 'island-power lock'`.
