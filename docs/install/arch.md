# Install on Arch Linux and derivatives

This guide covers Arch Linux, CachyOS, EndeavourOS, Manjaro and Garuda. The package names are the same; on a derivative that lags behind, check the Quickshell version before continuing.

Island is a shell, not a compositor. Start with a working Wayland session on Hyprland, niri, Sway/SwayFX/Scroll or MangoWC.

## 1. Packages

```sh
sudo pacman -S --needed quickshell qt6-base qt6-declarative qt6-svg qt6-wayland qt6-tools \
  jq curl glib2 libnotify networkmanager bluez bluez-utils pipewire pipewire-pulse wireplumber \
  upower udisks2 grim slurp wl-clipboard cliphist matugen ddcutil python-pillow adwaita-fonts \
  ttf-jetbrains-mono-nerd foot kitty neovim sddm polkit-gnome awww
```

Island needs Quickshell 0.3 or newer:

```sh
qs --version
```

Optional extras: `mpvpaper` and `ffmpeg` for video wallpapers, `hyprlock` for the alternate locker, `swayidle` or `hypridle` for idle locking. `matugen`, `ddcutil` and `python-pillow` are only needed for wallpaper colours, monitor brightness and icon tinting. The shell runs without them.

## 2. Deploy the checkout

```sh
mkdir -p ~/src
git clone https://github.com/ItsFennik/island-dots ~/src/island-dots
cd ~/src/island-dots
./install.sh --dry-run
./install.sh
```

`install.sh` symlinks the checkout at `~/src/island-dots` to `~/.config/quickshell/island` and backs up an existing target. Use `./install.sh --copy` if you would rather keep a detached copy. The installer does not edit your compositor config.

## 3. Add the compositor autostart

Add one line to the compositor config. Use the matching file in [`examples/`](../../examples/): it also contains the keybinds and layer rules that make the bar, dock and Spotlight behave.

```sh
# Hyprland (~/.config/hypr/)
exec-once = ~/.config/quickshell/island/scripts/island-startup

# niri (~/.config/niri/config.kdl)
spawn-at-startup "sh" "-c" "~/.config/quickshell/island/scripts/island-startup"

# Sway (~/.config/sway/config)
exec ~/.config/quickshell/island/scripts/island-startup

# MangoWC (~/.config/mango/config.conf)
exec-once=~/.config/quickshell/island/scripts/island-startup
```

`island-startup` is idempotent. It creates `XDG_RUNTIME_DIR` when missing, starts a dbus session and PipeWire on systems without a user service manager, starts the clipboard watchers, restores the wallpaper and launches Quickshell.

## 4. First start

Log out and back in, or start it in the current session:

```sh
~/.config/quickshell/island/scripts/island-startup
qs -c island ipc call settings toggle
```

Check the result with:

```sh
qs log -c island
tail -40 ~/.local/state/island/logs/startup.log
```

Pick a theme, wallpaper and font in Settings. If the shell is running but the bar is invisible, confirm the compositor is loading the `examples/` layer rules and that the output is a Wayland session.

## 5. Optional pieces

To let systemd supervise the shell instead of the compositor:

```sh
./install.sh --autostart systemd --enable
```

Then remove the compositor's `island-startup` line. The unit runs `island-startup --foreground --no-pipewire`, so PipeWire stays with its own user units.

Apply a palette by hand, or refresh the login theme:

```sh
./apply-theme.sh orchid
./sddm/install.sh --theme    # theme only
./sddm/install.sh            # make SDDM the display manager (asks for sudo)
```

For a symlinked install, update with `git -C ~/src/island-dots pull`. For a copied install, update inside `~/.config/quickshell/island` instead.

## Rollback

The installer prints the backup path, normally `~/.local/state/island/install-backups/<timestamp>/island`. Remove the autostart line (and disable the user unit if you installed it), then restore the backup or remove `~/.config/quickshell/island`. Re-run `./apply-theme.sh <old-id>` to restore an older palette.
