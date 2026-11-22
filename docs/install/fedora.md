# Install on Fedora and RHEL-like systems

This guide covers Fedora 44 and newer on a systemd user manager. RHEL 10, Rocky Linux and AlmaLinux are handled at the end; the binary Quickshell path is currently Fedora-only.

Island is a shell, not a compositor. Start with a working Wayland session on Hyprland, niri, Sway/SwayFX/Scroll or MangoWC.

## 1. Quickshell 0.3 or newer

Fedora's official `quickshell` package is 0.2.1, which is too old. Install it from the COPR:

```sh
sudo dnf copr enable lionheartp/Hyprland
sudo dnf install quickshell
qs --version
```

The same COPR also carries the current `awww`, `matugen`, `mpvpaper`, `hyprlock` and `hypridle`, so the package list below works after enabling it.

## 2. Packages

```sh
sudo dnf install qt6-qtbase qt6-qtdeclarative qt6-qtsvg qt6-qtwayland qt6-qttools \
  jq curl glib2 libnotify NetworkManager bluez pipewire pipewire-pulseaudio wireplumber \
  upower udisks2 grim slurp wl-clipboard cliphist matugen ddcutil python3-pillow \
  adwaita-sans-fonts jetbrains-mono-fonts foot kitty neovim sddm lxqt-policykit awww
```

Optional extras: `mpvpaper` and `ffmpeg` for video wallpapers, `hyprlock` for the alternate locker, `hypridle` or `swayidle` for idle locking.

`jetbrains-mono-fonts` is the plain font. Install the Nerd Font variant for the glyphs in the bar:

```sh
mkdir -p ~/.local/share/fonts
# download JetBrainsMono.zip from https://github.com/ryanoasis/nerd-fonts/releases
unzip JetBrainsMono.zip -d ~/.local/share/fonts/JetBrainsMono
fc-cache -f
```

## 3. Deploy the checkout

```sh
mkdir -p ~/src
git clone https://github.com/ItsFennik/island-dots ~/src/island-dots
cd ~/src/island-dots
./install.sh --dry-run
./install.sh
```

The installer symlinks the checkout by default and moves an existing target to `~/.local/state/island/install-backups/<timestamp>/island`. Use `--copy` for a detached copy. It does not edit the compositor config.

## 4. Add the compositor autostart

Add one line to the compositor config. The matching file in [`examples/`](../../examples/) also has the keybinds and layer rules.

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

`island-startup` is idempotent: it creates `XDG_RUNTIME_DIR` when needed, starts dbus and PipeWire when there is no user manager, starts the clipboard watchers, restores the wallpaper and launches Quickshell. On Fedora, PipeWire normally comes from its systemd user units.

## 5. First start

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

Pick a theme, wallpaper and font in Settings.

## 6. Optional pieces

Install the optional systemd user unit. This makes systemd supervise the shell:

```sh
./install.sh --autostart systemd --enable
```

Then remove the compositor's `island-startup` line. The unit runs `island-startup --foreground --no-pipewire`, so audio stays with the system's user units.

Apply a palette or refresh the login theme:

```sh
./apply-theme.sh orchid
./sddm/install.sh --theme    # theme only
./sddm/install.sh            # switch the display manager to SDDM
```

For a symlinked install, update with `git -C ~/src/island-dots pull`, then log out and back in.

## RHEL-like systems

On RHEL 10, Rocky Linux, AlmaLinux and similar, enable EPEL and CRB first. DNF 4 uses:

```sh
sudo dnf install epel-release
sudo dnf config-manager --set-enabled crb
```

On DNF 5, the second command is `sudo dnf config-manager setopt crb.enabled=1`.

The helper tools are then available from the base repos, EPEL or CRB:

```sh
sudo dnf install jq curl glib2 libnotify NetworkManager bluez pipewire wireplumber \
  upower udisks2 grim slurp wl-clipboard cliphist ddcutil python3-pillow \
  foot kitty neovim sddm lxqt-policykit
```

Package names can differ between RHEL releases; use `dnf search` for anything missing. `awww`, `matugen` and `mpvpaper` may need a source build or a third-party repository.

Quickshell is not in EPEL. Check whether the COPR offers an EL chroot:

```sh
sudo dnf copr enable lionheartp/Hyprland
sudo dnf install quickshell
```

If that fails, build Quickshell from source with the [upstream build instructions](https://github.com/quickshell-mirror/quickshell/blob/master/BUILD.md), using Qt 6.6 or newer, and install it to `/usr/local`. The deploy, autostart and first-start steps are the same as on Fedora. This binary path is not tested on every RHEL-like release; Fedora remains the supported Fedora-family setup.

## Rollback

Remove the autostart line (and disable `island.service` if you installed it), then restore the backup printed by `./install.sh` or remove `~/.config/quickshell/island`. To undo the SDDM switch, re-enable the previous display-manager service with systemd.
