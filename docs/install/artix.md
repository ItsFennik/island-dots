# Install on Artix Linux and other non-systemd Arch systems

This guide covers Artix on OpenRC, runit, dinit and s6, plus other Arch-based systems that do not run systemd. If your Arch derivative uses systemd, follow [arch.md](arch.md) instead.

Island does not need an init service. The compositor starts `scripts/island-startup`, and `scripts/island-session` can provide the dbus session around the compositor. See [non-systemd.md](../non-systemd.md) for the full session model.

## 1. Packages

```sh
sudo pacman -S --needed quickshell qt6-base qt6-declarative qt6-svg qt6-wayland qt6-tools \
  jq curl glib2 libnotify networkmanager bluez bluez-utils pipewire pipewire-pulse wireplumber \
  upower udisks2 grim slurp wl-clipboard cliphist matugen ddcutil python-pillow adwaita-fonts \
  ttf-jetbrains-mono-nerd foot kitty neovim sddm polkit-gnome awww
```

Pick one seat manager: install `elogind` for `loginctl`, lock and suspend integration, or `seatd` for a minimal setup. Do not enable both.

```sh
sudo pacman -S --needed elogind    # recommended for a desktop session
# or
sudo pacman -S --needed seatd
```

`qs --version` must report 0.3 or newer. Most of these packages are in the Artix repositories. If one is missing, enable the Arch-compatible repositories with `artix-archlinux-support`, or leave out the optional package (`matugen`, `awww`, the Nerd Font).

## 2. Enable the system services

OpenRC:

```sh
sudo rc-update add dbus default
sudo rc-update add NetworkManager default
sudo rc-update add bluetoothd default
sudo rc-update add elogind default        # or: rc-update add seatd default
sudo rc-service dbus start
sudo rc-service NetworkManager start
sudo rc-service bluetoothd start
sudo rc-service elogind start             # or: rc-service seatd start
```

runit:

```sh
sudo ln -s /etc/runit/sv/dbus /run/runit/service/
sudo ln -s /etc/runit/sv/NetworkManager /run/runit/service/
sudo ln -s /etc/runit/sv/bluetoothd /run/runit/service/
sudo ln -s /etc/runit/sv/elogind /run/runit/service/    # or: seatd
```

With seatd, add your user to the `seat` group, then log out and back in:

```sh
sudo usermod -aG seat "$USER"
```

dinit:

```sh
sudo dinitctl enable dbus
sudo dinitctl enable NetworkManager
sudo dinitctl enable bluetoothd
sudo dinitctl enable elogind      # or: seatd
```

On s6, enable the equivalent services through your s6-rc setup. The commands are collected in [non-systemd.md](../non-systemd.md).

## 3. Deploy the checkout

```sh
mkdir -p ~/src
git clone https://github.com/ItsFennik/island-dots ~/src/island-dots
cd ~/src/island-dots
./install.sh --dry-run
./install.sh
```

The installer detects OpenRC, runit, s6 or dinit and does not install a systemd unit. It symlinks the checkout by default and moves an existing target to `~/.local/state/island/install-backups/<timestamp>/island`. If detection is wrong, pass `--init openrc`, `--init runit`, `--init dinit`, `--init s6` or `--init none`.

## 4. Start the session

Start the compositor through `island-session` so it gets a dbus session that every app it launches can use:

```sh
~/.config/quickshell/island/scripts/island-session -- Hyprland
~/.config/quickshell/island/scripts/island-session -- niri
~/.config/quickshell/island/scripts/island-session -- sway
~/.config/quickshell/island/scripts/island-session -- mango
```

Use this command from a TTY or as the session command in your display manager. Then add the compositor autostart line from [`examples/`](../../examples/):

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

If you start the compositor without `island-session`, `island-startup` still creates a private bus for the shell and its helpers. GUI apps launched by the compositor will not share that bus, so prefer `island-session`.

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

The script enables SDDM with OpenRC, runit or dinit. On Artix runit, if it does not enable the service, link it by hand:

```sh
sudo ln -s /etc/runit/sv/sddm /run/runit/service/
```

For a symlinked install, update with `git -C ~/src/island-dots pull`, then log out and back in.

## Rollback

Remove the `island-startup` line from the compositor config and restore the installer backup printed by `./install.sh`. Then remove `~/.config/quickshell/island`. If you installed the SDDM theme, disable SDDM or switch back to the previous display manager with your init's commands.
