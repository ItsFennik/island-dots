# Install on Gentoo (OpenRC or systemd)

Quickshell, `awww`, `matugen` and `cliphist` are in the [GURU overlay](https://github.com/gentoo/guru). The rest is in the main tree. Island is a shell, not a compositor; install and configure Hyprland, niri, Sway or MangoWC first.

## 1. Enable GURU

```sh
sudo emerge --ask app-eselect/eselect-repository
sudo eselect repository enable guru
sudo emaint sync -r guru
```

## 2. Packages

Choose one seat manager when you install: `sys-auth/elogind` for `loginctl` and lock/suspend integration, or `sys-auth/seatd` for a minimal setup. This command uses elogind:

```sh
sudo emerge --ask gui-apps/quickshell \
  dev-qt/qtbase dev-qt/qtdeclarative dev-qt/qtsvg dev-qt/qtwayland dev-qt/qttools \
  app-misc/jq net-misc/curl dev-libs/glib x11-libs/libnotify \
  net-misc/networkmanager net-wireless/bluez media-video/pipewire media-video/wireplumber \
  sys-power/upower sys-fs/udisks gui-apps/grim gui-apps/slurp gui-apps/wl-clipboard \
  app-misc/cliphist x11-misc/matugen gui-apps/awww app-misc/ddcutil dev-python/pillow \
  media-fonts/adwaita-fonts media-fonts/jetbrains-mono media-fonts/nerdfonts \
  gui-apps/foot x11-terms/kitty app-editors/neovim gui-apps/sddm \
  gnome-extra/polkit-gnome sys-auth/elogind
```

For seatd instead:

```sh
sudo emerge --ask sys-auth/seatd
sudo usermod -aG seat "$USER"
```

Optional extras: `gui-apps/mpvpaper` and `media-video/ffmpeg` for video wallpapers, and `gui-apps/swayidle` for idle locking. Install a locker such as hyprlock from an overlay if you use one. `qs --version` must report 0.3 or newer.

## 3. Enable the system services

OpenRC:

```sh
sudo rc-update add dbus default
sudo rc-update add NetworkManager default
sudo rc-update add bluetooth default
sudo rc-update add elogind default        # or: rc-update add seatd default
sudo rc-service dbus start
sudo rc-service NetworkManager start
sudo rc-service bluetooth start
sudo rc-service elogind start             # or: rc-service seatd start
```

systemd:

```sh
sudo systemctl enable --now NetworkManager
sudo systemctl enable --now bluetooth
sudo systemctl enable --now upower
sudo systemctl enable --now udisks2
```

`dbus` is normally socket-activated on Gentoo systemd. Keep your existing PipeWire launcher if you use one; otherwise `island-startup` starts PipeWire and WirePlumber for the session when no systemd user manager is present.

## 4. Deploy the checkout

```sh
mkdir -p ~/src
git clone https://github.com/ItsFennik/island-dots ~/src/island-dots
cd ~/src/island-dots
./install.sh --dry-run
./install.sh
```

The installer detects OpenRC or systemd and does not install a unit unless you ask for one. It symlinks the checkout by default and moves an existing target to `~/.local/state/island/install-backups/<timestamp>/island`.

## 5. Start the session

On OpenRC, start the compositor through `island-session` so every app it launches inherits the dbus session:

```sh
~/.config/quickshell/island/scripts/island-session -- Hyprland
~/.config/quickshell/island/scripts/island-session -- niri
~/.config/quickshell/island/scripts/island-session -- sway
~/.config/quickshell/island/scripts/island-session -- mango
```

On systemd, start the compositor normally. Then add the compositor autostart line from [`examples/`](../../examples/):

```sh
# Hyprland
exec-once = ~/.config/quickshell/island/scripts/island-startup

# niri
spawn-at-startup "sh" "-c" "~/.config/quickshell/island/scripts/island-startup"

# Sway
exec ~/.config/quickshell/island/scripts/island-startup

# MangoWC
exec-once=~/.config/quickshell/island/scripts/island-startup
```

`island-startup` is idempotent: it creates `XDG_RUNTIME_DIR` when needed, starts dbus and PipeWire when no user manager exists, starts the clipboard watchers, restores the wallpaper and launches Quickshell.

## 6. First start

Log out and back in, or start it in the current session:

```sh
~/.config/quickshell/island/scripts/island-startup
qs -c island ipc call settings toggle
```

Check both logs:

```sh
qs log -c island
tail -40 ~/.local/state/island/logs/startup.log
```

On OpenRC, `scripts/island-power status` shows the backend it will use for shutdown, reboot, suspend and lock. With seatd and no elogind, configure a passwordless `doas` or `sudo` rule for the power commands if you use the power menu.

## 7. Optional pieces

On systemd:

```sh
./install.sh --autostart systemd --enable   # optional user unit; remove the compositor line
```

On either init:

```sh
./apply-theme.sh orchid
./sddm/install.sh --theme                   # theme only
./sddm/install.sh                           # switch the display manager to SDDM
```

For a symlinked install, update with `git -C ~/src/island-dots pull`, then log out and back in.

## Rollback

Remove the autostart line (and disable `island.service` if you installed it), then restore the backup printed by `./install.sh` or remove `~/.config/quickshell/island`. Disable or remove the seat manager and services only if you no longer need them. Re-enable the previous display manager to undo the SDDM switch.
