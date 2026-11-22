# Install on openSUSE and the SUSE family

This guide covers openSUSE Tumbleweed and Leap, plus SLE-derived systems where the desktop packages exist. Tumbleweed is the practical target: it has a current Qt 6 toolchain. Island is a shell, not a compositor; start with a working Wayland session on Hyprland, niri, Sway/SwayFX/Scroll or MangoWC.

Quickshell is not in the official openSUSE OSS repository at the time of writing. Build it from source and install it to `/usr/local`. Several home projects on the Open Build Service package it, but they are not a supported installation path.

## 1. Build Quickshell

```sh
sudo zypper install cmake ninja gcc-c++ git pkgconf \
  qt6-base-devel qt6-declarative-devel qt6-svg-devel qt6-wayland-devel qt6-tools-devel \
  qt6-base-private-devel qt6-declarative-private-devel qt6-wayland-private-devel \
  qt6-shadertools-devel spirv-tools-devel libdrm-devel wayland-devel \
  wayland-protocols-devel cli11-devel jemalloc-devel

git clone https://github.com/quickshell-mirror/quickshell
cmake -S quickshell -B quickshell/build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCRASH_HANDLER=OFF
cmake --build quickshell/build
sudo cmake --install quickshell/build
qs --version
```

`-DCRASH_HANDLER=OFF` avoids the optional cpptrace dependency. Quickshell needs Qt 6.6 or newer and the matching private headers. Leap releases older than 16 may not satisfy that; use Tumbleweed or build on a newer release.

## 2. Packages

```sh
sudo zypper install jq curl glib2-tools libnotify-tools NetworkManager bluez \
  pipewire pipewire-pulseaudio wireplumber upower udisks2 grim slurp wl-clipboard \
  cliphist awww ddcutil python3-Pillow adwaita-fonts jetbrains-mono-fonts \
  foot kitty neovim sddm lxqt-policykit
```

Optional extras: `mpvpaper` and `ffmpeg` for video wallpapers, `swayidle` for idle locking, `hyprlock` if you use Hyprland. `matugen` is not in the openSUSE repositories; leave Material You off or build it separately. Install the JetBrains Mono Nerd Font variant from [nerd-fonts](https://github.com/ryanoasis/nerd-fonts/releases) for the bar glyphs.

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

`island-startup` is idempotent: it creates `XDG_RUNTIME_DIR` when needed, starts dbus and PipeWire when no user manager exists, starts the clipboard watchers, restores the wallpaper and launches Quickshell. On an openSUSE systemd session, PipeWire stays with its user units.

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

## 6. Optional pieces

```sh
./install.sh --autostart systemd --enable   # optional user unit; remove the compositor line
./apply-theme.sh orchid
./sddm/install.sh --theme                   # theme only
./sddm/install.sh                           # switch the display manager to SDDM
```

For a symlinked install, update with `git -C ~/src/island-dots pull`, then log out and back in.

## SUSE-family notes

- **openSUSE Leap:** install the Qt 6 development packages listed above and build Quickshell on the target release. Check `zypper info qt6-base-devel`; if the Qt version is older than 6.6, use Tumbleweed.
- **SLE / SLES:** not a desktop-focused target, and many of the helper packages are missing. Build Quickshell from source and use the distro's Qt 6 packages if they are new enough; otherwise use openSUSE Tumbleweed.
- **MicroOS / Aeon (immutable):** avoid installing the shell with `cmake --install` into the mutable overlay. Build and run it from a Tumbleweed container or use a mutable Tumbleweed install instead.

## Rollback

Remove the autostart line (and disable `island.service` if you installed it), then restore the backup printed by `./install.sh` or remove `~/.config/quickshell/island`. Remove `/usr/local/bin/qs` and its installed QML modules if you built Quickshell from source and no longer need it.
