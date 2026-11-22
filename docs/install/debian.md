# Install on Debian, Ubuntu, Mint, Pop!_OS and PikaOS

This guide covers Debian and Ubuntu and the distributions built on them. Quickshell 0.3 is available from Debian 13 backports, Debian 14, Ubuntu 26.10 and newer. Debian 12, Ubuntu 24.04 and older, and derivatives based on them need a source build or a newer release.

Island is a shell, not a compositor. Start with a working Wayland session on Hyprland, niri, Sway/SwayFX/Scroll or MangoWC.

## 1. Quickshell 0.3 or newer

Check what the archive offers:

```sh
apt policy quickshell
```

On Debian 13 (trixie), enable backports and install from there:

```sh
sudo sh -c 'echo "deb http://deb.debian.org/debian trixie-backports main" > /etc/apt/sources.list.d/trixie-backports.list'
sudo apt update
sudo apt install -t trixie-backports quickshell
```

On Debian 14/testing/sid and Ubuntu 26.10 or newer:

```sh
sudo apt update
sudo apt install quickshell
```

If the package is missing or older than 0.3, build Quickshell against Qt 6.6 or newer:

```sh
sudo apt install build-essential cmake ninja-build pkg-config git \
  qt6-base-dev qt6-declarative-dev qt6-svg-dev qt6-wayland-dev qt6-tools-dev \
  qt6-base-private-dev qt6-declarative-private-dev qt6-wayland-private-dev \
  qt6-shadertools-dev spirv-tools libdrm-dev libwayland-dev wayland-protocols \
  libcli11-dev libjemalloc-dev
git clone https://github.com/quickshell-mirror/quickshell
cmake -S quickshell -B quickshell/build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCRASH_HANDLER=OFF
cmake --build quickshell/build
sudo cmake --install quickshell/build
```

`-DCRASH_HANDLER=OFF` avoids the optional cpptrace dependency. Verify with `qs --version`.

## 2. Packages

```sh
sudo apt install jq curl libglib2.0-bin libnotify-bin network-manager bluez pipewire \
  pipewire-pulse wireplumber upower udisks2 grim slurp wl-clipboard cliphist ddcutil \
  python3-pil fonts-jetbrains-mono foot kitty neovim sddm lxpolkit
```

Optional extras: `swayidle` for idle locking, `mpvpaper` and `ffmpeg` for video wallpapers, and `hyprlock` if your compositor is Hyprland. `awww` and `matugen` are not in the Debian archive; the shell runs without them, but the wallpaper picker needs a backend.

Adwaita Sans is the default UI font. Install it from the GNOME release if it is not packaged, or pick another font in Settings. `fonts-jetbrains-mono` is the plain font; install the Nerd Font variant from [nerd-fonts](https://github.com/ryanoasis/nerd-fonts/releases) for the bar glyphs.

### Wallpaper backend

`awww` builds with Cargo. Debian 13 ships Rust 1.85, below awww's 1.87 minimum, so install a current toolchain with [rustup](https://rustup.rs/) on Debian 13, or build on Debian 14/sid. Then put both binaries on `PATH`:

```sh
sudo apt install pkg-config libwayland-dev wayland-protocols liblz4-dev
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
git clone https://codeberg.org/LGFae/awww
cd awww
cargo build --release
mkdir -p ~/.local/bin
install -m755 target/release/awww target/release/awww-daemon ~/.local/bin/
```

Open a new shell so `~/.local/bin` is picked up. The script also accepts the older `swww` binary if you build that instead.

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

`island-startup` is idempotent. It creates `XDG_RUNTIME_DIR` when needed, starts dbus and PipeWire when no user manager exists, starts the clipboard watchers, restores the wallpaper and launches Quickshell.

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

If the wallpaper backend was just installed, pick a wallpaper in Settings or run `scripts/wallpaper-set.sh --random`.

## 6. Optional pieces

```sh
./install.sh --autostart systemd --enable   # optional user unit; remove the compositor line
./apply-theme.sh orchid
./sddm/install.sh --theme                   # theme only
./sddm/install.sh                           # switch the display manager to SDDM
```

For a symlinked install, update with `git -C ~/src/island-dots pull`, then log out and back in.

## Rollback

Remove the autostart line (and disable `island.service` if you installed it), then restore the backup printed by `./install.sh` or remove `~/.config/quickshell/island`. Re-enable your previous display-manager service to undo the SDDM switch.
