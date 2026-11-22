# Screenshots

Current screenshots are real captures from a MangoWC session. Run `capture.sh` from this directory for the shell states, then add the missing app and overview shots by hand.

## Present

- `island-desktop.png`: empty workspace, bar, dock and widgets, desktop icons hidden
- `island-tiling.png`: terminal and Neovim tiled
- `island-terminal.png`: foot with the prompt
- `island-nvim.png`: Neovim editing README.md
- `island-bar.png`: crop of the menu bar
- `island-launcher.png`: Spotlight
- `island-settings.png`: System Settings on Appearance
- `island-control-center.png`: Control Centre
- `island-power-menu.png`: power menu
- `island-notifications.png`: a notification toast
- `island-theme-light.png`: Catppuccin Latte, dark wallpaper
- `island-lock.png`: real lock screen
- `island-lock-preview.png`: lock preview via IPC
- `island-login.png`: SDDM theme

## Still needed

| Filename | What must be on screen | State before capture |
|---|---|---|
| `island-launchpad.png` | Launchpad app grid | `qs -c island ipc call launchpad toggle` |
| `island-overview.png` | Overview with at least two workspaces and live previews | open two windows on different tags, `qs -c island ipc call overview toggle` |
| `island-wallpaper-picker.png` | Wallpaper picker with thumbnails | `qs -c island ipc call picker wallpapers` |
| `island-clipboard.png` | Clipboard history with several entries | copy a few short strings first, then `qs -c island ipc call menu clipboard` |
| `island-sound-menu.png` | Sound menu with at least two outputs | `qs -c island ipc call menu sound` |
| `island-media.png` | Media popout with a playing MPRIS app | start a track, `qs -c island ipc call menu media` |
| `island-widgets-editor.png` | Widget editor handles visible | `qs -c island ipc call widgets edit` |
| `island-sddm.png` | Optional alternate SDDM shot | log out and capture the greeter (cannot be taken from inside the session) |

## Colour variants

The repository has one palette per file in `themes/`. Capture one desktop shot per palette if you want a full gallery. Use the theme id as the file name:

`island-theme-abyss.png`, `island-theme-aurora.png`, `island-theme-catppuccin-latte.png`, `island-theme-catppuccin-macchiato.png`, `island-theme-catppuccin-mocha.png`, `island-theme-ember.png`, `island-theme-everforest.png`, `island-theme-gruvbox.png`, `island-theme-kanagawa.png`, `island-theme-macos.png`, `island-theme-macos-light.png`, `island-theme-matugen.png`, `island-theme-e-ink.png`, `island-theme-e-ink-light.png`, `island-theme-neon-dusk.png`, `island-theme-nord.png`, `island-theme-orchid.png`, `island-theme-rose-pine.png`, `island-theme-sakura.png`, `island-theme-space.png`, `island-theme-tokyo-night.png`.

`island-theme-light.png` already covers Catppuccin Latte. Use an empty workspace for every variant and hide desktop icons in Settings > Appearance to keep the gallery consistent.

## Capture notes

- Use an empty workspace. Do not include personal windows, messages or drive labels.
- Hide desktop icons, and disable the weather and music widgets unless the shot is about them.
- Turn off dock autohide for desktop and shell shots.
- Clear notifications before capturing unless the shot is about notifications.
- The lock screenshot must be a real lock or `qs -c island ipc call lock preview`; do not mock it.
- Do not add placeholder images. Every file in this directory should be a real capture.
