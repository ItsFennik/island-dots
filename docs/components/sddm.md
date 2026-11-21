# SDDM login theme

`sddm/island/` is a QML greeter theme. `sddm/install.sh` installs it and optionally makes SDDM the display manager.

```sh
./sddm/install.sh --theme    # install or refresh the theme only
./sddm/install.sh            # install and enable SDDM (asks for sudo)
```

The installer:

- copies the theme to `/usr/share/sddm/themes/island`;
- uses the current Island wallpaper as the greeter background;
- copies `~/.face.icon` or `~/.face` into `/usr/share/sddm/faces/`;
- reads `clock24h` and `cursorTheme` from Island settings;
- writes `/etc/sddm.conf.d/zz-island.conf`;
- enables SDDM through systemd, OpenRC, runit or dinit.

Undo with the command printed by the installer. On systemd the old display manager is usually `greetd.service`, `gdm.service` or `lightdm.service`.

The greeter runs as the `sddm` user and cannot read files in your home directory, which is why the wallpaper and face are copied.
