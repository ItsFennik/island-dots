# Scripts

| Script | Purpose |
|---|---|
| `scripts/island-startup` | Session startup: runtime dir, dbus, PipeWire, clipboard, polkit, wallpaper, shell |
| `scripts/island-session` | Runs a compositor under a private dbus session bus |
| `scripts/island-power` | Power and session actions with systemd, elogind, OpenRC and direct fallbacks |
| `scripts/wallpaper-set.sh` | Image/video wallpaper, restore, posters |
| `scripts/wallhaven.sh` | Wallhaven search and download |
| `scripts/matugen-theme.sh` | Material You palette from the wallpaper |
| `scripts/screenshot.sh` | grim/slurp capture, clipboard and save |
| `scripts/session-stamp.sh` | First-start-per-session marker for lock-on-login |
| `scripts/votd.sh` | Verse of the day with an offline pool |
| `scripts/displays.sh` | Hyprland display apply/save |
| `scripts/default-apps.sh` | MIME default app query/set |
| `scripts/brave-ntp.sh` | Brave new-tab background |
| `scripts/tint-icons.py` | Clear and tinted app icons |
| `scripts/theme-walls.py` | Theme wallpaper pairing helpers |
| `scripts/kvantum-theme.py` | Kvantum palette generator |
| `scripts/vscodium-theme.py` | VSCodium theme generator |

Run `scripts/island-power --help`, `scripts/island-startup --help` and the header comment of the other scripts for their exact arguments. The session scripts are documented in [Non-systemd](../non-systemd.md).
