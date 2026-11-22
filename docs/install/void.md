# Install on Void Linux (runit)

Void packages Quickshell 0.3.2 in the main repository. Island is a shell, not a compositor; start with a working Wayland session on Hyprland, niri, Sway/SwayFX/Scroll or MangoWC.

## 1. Packages

```sh
sudo xbps-install -S quickshell qt6-base qt6-declarative qt6-svg qt6-wayland qt6-tools \
  jq curl glib libnotify NetworkManager bluez pipewire wireplumber upower udisks2 \
  grim slurp wl-clipboard cliphist matugen ddcutil python3-Pillow adwaita-fonts \
  nerd-fonts foot kitty neovim sddm polkit-gnome awww dbus seatd
```

`qs --version` must report 0.3 or newer. Optional extras: `mpvpaper` and `ffmpeg` for video wallpapers, `swayidle` for idle locking.

Void's `pipewire` package also installs a session manager; keep `wireplumber` installed. `island-startup` starts both for the session when no systemd user manager is present.

If you prefer logind features such as `loginctl` and session locking, install `elogind` instead of `seatd`:

```sh
sudo xbps-install -S elogind
```

## 2. Enable the system services

runit services are symlinked into `/var/service`:

```sh
sudo ln -s /etc/sv/dbus /var/service/
sudo ln -s /etc/sv/NetworkManager /var/service/
sudo ln -s /etc/sv/bluetoothd /var/service/
sudo ln -s /etc/sv/seatd /var/service/        # or: /etc/sv/elogind
```

With seatd, add your user to the `_seatd` group, then log out and back in:

```sh
sudo usermod -aG _seatd "$USER"
```

Do not enable both seatd and elogind. The services start immediately when linked. Check them with `sv status dbus NetworkManager bluetoothd seatd`.

## 3. Deploy the checkout

```sh
mkdir -p ~/src
git clone https://github.com/ItsFennik/island-dots ~/src/island-dots
cd ~/src/island-dots
./install.sh --dry-run
./install.sh
```

The installer detects runit and does not install a systemd unit. It symlinks the checkout by default and moves an existing target to `~/.local/state/island/install-backups/<timestamp>/island`. Pass `--init runit` if detection is wrong.

## 4. Start the session

Start the compositor through `island-session` so every app it launches inherits the dbus session:

```sh
~/.config/quickshell/island/scripts/island-session -- Hyprland
~/.config/quickshell/island/scripts/island-session -- niri
~/.config/quickshell/island/scripts/island-session -- sway
~/.config/quickshell/island/scripts/island-session -- mango
```

Use this from a TTY or as the session command in your display manager. If you use turnstile as your session manager, its user bus can replace the wrapper. Then add the compositor autostart line from [`examples/`](../../examples/):

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

## 5. First start

Log out and back in, or start the shell in the current session:

```sh
~/.config/quickshell/island/scripts/island-startup
qs -c island ipc call settings toggle
```

Check both logs:

```sh
qs log -c island
tail -40 ~/.local/state/island/logs/startup.log
```

## 6. Power and session actions

Every Island menu and keybind goes through `scripts/island-power`:

```sh
scripts/island-power status
scripts/island-power suspend
scripts/island-power reboot
scripts/island-power poweroff
```

With elogind, logout, lock and suspend use logind. With seatd only, `island-power` falls back to userland commands; configure a passwordless rule for `doas` or `sudo` if you use the power menu, or install elogind instead. `scripts/island-power --dry-run <action>` shows the command it would run.

## 7. Optional SDDM theme

```sh
./sddm/install.sh --theme    # theme only
./sddm/install.sh            # switch the display manager to SDDM
```

The script detects runit and links the service into the default runlevel. On Void, if the service is not active, link it into `/var/service` by hand:

```sh
sudo ln -s /etc/sv/sddm /var/service/
```

For a symlinked install, update with `git -C ~/src/island-dots pull`, then log out and back in.

## Rollback

Remove the autostart line and restore the installer backup printed by `./install.sh`, then remove `~/.config/quickshell/island`. Remove the `/var/service` symlinks for the services you added if you no longer need them, and re-enable the previous display manager to undo the SDDM switch.
