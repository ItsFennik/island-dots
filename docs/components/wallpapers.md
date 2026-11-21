# Wallpapers

![Wallpaper picker](../screenshots/island-wallpaper-picker.png)

- `scripts/wallpaper-set.sh`: set, random, restore, video posters
- `scripts/wallhaven.sh`: search, download, set
- `popouts/Picker.qml`: wallpaper and theme picker
- `services/Wallhaven.qml`, `services/ThemeWalls.qml`, `services/WallColors.qml`
- Settings: Wallpaper > folders and Wallhaven filters

Commands:

```sh
scripts/wallpaper-set.sh /path/to/image.jpg
scripts/wallpaper-set.sh --random
scripts/wallpaper-set.sh --restore
scripts/wallpaper-set.sh --thumbs
scripts/wallhaven.sh random
```

The last wallpaper is stored in `~/.local/state/island/wallpaper`. Images use `awww` (or `swww`), videos use `mpvpaper` with a poster frame from `ffmpeg`. `island-startup` calls `--restore` at login.

Wallpaper folders are `wallDir` and `videoDir`. Theme-paired wallpapers live in `~/.config/island/theme-walls.json`; press P in the picker to pair or unpair. When Material You is on, the wallpaper also rebuilds `themes/matugen.json`.

If no wallpaper appears, check that `awww` (or `swww`) and, for video, `mpvpaper` and `ffmpeg` are installed. The exact error is printed by `wallpaper-set.sh`.
