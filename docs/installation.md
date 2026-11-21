# Installation

Island is a Quickshell configuration plus a set of scripts. You can install it by symlinking the checkout to `~/.config/quickshell/island`, copying it there, or packaging it with your dotfiles manager. The included installer does the symlink/copy and the optional systemd unit.

Only Fedora 45 with MangoWC was exercised end to end while writing this page. Package names for the other distributions were checked against their current package indexes; commands for those are best effort. See [non-systemd.md](non-systemd.md) for init-specific session setup.

## 1. Packages

Core runtime:

| Need | Arch / Artix | Fedora | Debian / Ubuntu | Void | Alpine |
|---|---|---|---|---|---|
| Quickshell >= 0.3 | `quickshell` | `quickshell` from the `lionheartp/Hyprland` COPR | `quickshell` from trixie-backports or newer | `quickshell` | build from source |
| Qt 6 QML, SVG, Wayland | `qt6-base qt6-declarative qt6-svg qt6-wayland qt6-tools` | `qt6-qtbase qt6-qtdeclarative qt6-qtsvg qt6-qtwayland qt6-qttools` | `qt6-base-dev qt6-declarative-dev qt6-svg-dev qt6-wayland-dev qt6-tools-dev` | `qt6-base qt6-declarative qt6-svg qt6-wayland qt6-tools` | `qt6-qtbase-dev qt6-qtdeclarative-dev qt6-qtsvg-dev qt6-qtwayland-dev` |
| jq, curl | `jq curl` | `jq curl` | `jq curl` | `jq curl` | `jq curl` |
| gdbus, gio | `glib2` | `glib2` | `libglib2.0-bin` | `glib` | `glib` |
| notify-send | `libnotify` | `libnotify` | `libnotify-bin` | `libnotify` | `libnotify` |
| Network, Bluetooth, audio, power | `networkmanager bluez bluez-utils pipewire pipewire-pulse wireplumber upower udisks2` | `NetworkManager bluez pipewire pipewire-pulseaudio wireplumber upower udisks2` | `network-manager bluez pipewire pipewire-pulse wireplumber upower udisks2` | `NetworkManager bluez pipewire wireplumber upower udisks2` | `networkmanager bluez pipewire wireplumber upower udisks2` |
| Screenshots | `grim slurp wl-clipboard` | `grim slurp wl-clipboard` | `grim slurp wl-clipboard` | `grim slurp wl-clipboard` | `grim slurp wl-clipboard` |
| Clipboard history | `cliphist` | `cliphist` | `cliphist` | `cliphist` | `cliphist` |
| Wallpaper | `awww` | `awww` | build [awww](https://codeberg.org/LGFae/awww) or use a distro package if it appears | `awww` | `awww` |
| Fonts | `adwaita-fonts ttf-jetbrains-mono-nerd` | `adwaita-sans-fonts jetbrains-mono-fonts` | `fonts-jetbrains-mono`; Adwaita Sans from upstream if not packaged | `adwaita-fonts nerd-fonts` | `adwaita-fonts nerd-fonts` |
| Terminal, editor | `foot kitty neovim` | `foot kitty neovim` | `foot kitty neovim` | `foot kitty neovim` | `foot kitty neovim` |
| Polkit agent | `polkit-gnome` | `lxqt-policykit` | `lxpolkit` or `lxqt-policykit` | `polkit-gnome` | `polkit-gnome` |
| SDDM theme | `sddm` | `sddm` | `sddm` | `sddm` | `sddm` |
| Nerd Font glyphs | `ttf-jetbrains-mono-nerd` | install from [nerd-fonts](https://github.com/ryanoasis/nerd-fonts) | install from nerd-fonts | `nerd-fonts` | `nerd-fonts` |

Optional: `matugen` for Material You colours, `mpvpaper` and `ffmpeg` for video wallpapers, `ddcutil` for monitor brightness, `hyprlock` for the alternate locker, `python-pillow` for icon tinting and wall colour helpers, `udisks2` for the Drives pane, `swayidle` or `hypridle` for idle locking.

### Arch and Artix

```sh
sudo pacman -S --needed quickshell qt6-base qt6-declarative qt6-svg qt6-wayland qt6-tools \
  jq curl glib2 libnotify networkmanager bluez bluez-utils pipewire pipewire-pulse wireplumber \
  upower udisks2 grim slurp wl-clipboard cliphist matugen ddcutil python-pillow adwaita-fonts \
  ttf-jetbrains-mono-nerd foot kitty neovim sddm polkit-gnome awww
```

On Artix add `elogind` or `seatd` and enable your init's dbus service. The Quickshell package name is the same.

### Fedora

Fedora's official Quickshell was 0.2.1 at the time of writing. Island needs 0.3 or newer, so install it from the COPR first:

```sh
sudo dnf copr enable lionheartp/Hyprland
sudo dnf install quickshell
```

Then the rest:

```sh
sudo dnf install qt6-qtbase qt6-qtdeclarative qt6-qtsvg qt6-qtwayland qt6-qttools \
  jq curl glib2 libnotify NetworkManager bluez pipewire pipewire-pulseaudio wireplumber \
  upower udisks2 grim slurp wl-clipboard cliphist matugen ddcutil python3-pillow \
  adwaita-sans-fonts jetbrains-mono-fonts foot kitty neovim sddm lxqt-policykit awww
```

`jetbrains-mono-fonts` is the plain font. Install the Nerd Font variant from the [nerd-fonts releases](https://github.com/ryanoasis/nerd-fonts/releases) for the glyphs in the bar.

### Debian and Ubuntu

```sh
sudo apt install jq curl libglib2.0-bin libnotify-bin network-manager bluez pipewire \
  pipewire-pulse wireplumber upower udisks2 grim slurp wl-clipboard cliphist ddcutil \
  python3-pil fonts-jetbrains-mono foot kitty neovim sddm lxpolkit qt6-base-dev \
  qt6-declarative-dev qt6-svg-dev qt6-wayland-dev qt6-tools-dev
```

Quickshell is not in Debian 13's main archive. Use trixie-backports or newer:

```sh
sudo apt install -t trixie-backports quickshell
```

Ubuntu 24.04 has no Quickshell package; build it from source or use a newer Ubuntu. `awww` and `matugen` are not in the Debian archive. The wallpaper script also accepts the older `swww` command if you build that instead. Adwaita Sans is the default UI font; if it is unavailable, pick another font in Settings or install it from the GNOME font release.

### Void

```sh
sudo xbps-install quickshell qt6-base qt6-declarative qt6-svg qt6-wayland qt6-tools \
  jq curl glib libnotify NetworkManager bluez pipewire wireplumber upower udisks2 \
  grim slurp wl-clipboard cliphist matugen ddcutil python3-Pillow adwaita-fonts \
  nerd-fonts foot kitty neovim sddm polkit-gnome awww dbus seatd
```

### Alpine

Quickshell is not packaged in Alpine. Build it from source:

```sh
sudo apk add cmake samurai pkgconf git qt6-qtbase-dev qt6-qtdeclarative-dev \
  qt6-qtsvg-dev qt6-qtwayland-dev qt6-qtbase-private-dev qt6-qtdeclarative-private-dev \
  qt6-qtshadertools-dev spirv-tools-dev libdrm-dev wayland-dev \
  wayland-protocols jemalloc-dev
git clone https://github.com/quickshell-mirror/quickshell
cmake -S quickshell -B quickshell/build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build quickshell/build
sudo cmake --install quickshell/build
```

Runtime packages:

```sh
sudo apk add jq curl glib libnotify networkmanager bluez pipewire wireplumber upower \
  udisks2 grim slurp wl-clipboard cliphist py3-pillow adwaita-fonts nerd-fonts \
  foot kitty neovim sddm polkit-gnome awww dbus seatd
```

`matugen` is not packaged; leave Material You off or build it from source. Add your user to the `seat` group when using seatd, or use elogind.

### Nix

The repository has a flake:

```sh
nix develop
nix run .#
```

`nix run` installs the checkout into the Nix store and runs the shell through a wrapper. The Nix package is experimental; the supported path is a normal checkout in `~/.config/quickshell/island`.

## 2. Deploy the repository

The default target is `$XDG_CONFIG_HOME/quickshell/island`, normally `~/.config/quickshell/island`.

### Installer

```sh
./install.sh --dry-run     # show what would happen
./install.sh               # symlink this checkout into place
./install.sh --copy        # copy instead of symlink
```

The installer moves an existing target to `~/.local/state/island/install-backups/<timestamp>/island`. Roll back with:

```sh
rm -rf ~/.config/quickshell/island
mv ~/.local/state/island/install-backups/<timestamp>/island ~/.config/quickshell/island
```

It does not edit compositor configs. It prints the autostart line for the detected compositor.

### Manual symlink

```sh
git clone https://github.com/ItsFennik/island-dots ~/src/island-dots
mkdir -p ~/.config/quickshell
ln -sfn ~/src/island-dots ~/.config/quickshell/island
```

### Copy

```sh
git clone https://github.com/ItsFennik/island-dots
cp -a island-dots ~/.config/quickshell/island
```

Updates then require a new copy or `git pull` inside the installed directory.

### GNU Stow

The checkout is already the configuration directory, not a `stow` package tree. If you use stow, keep a package such as:

```
dotfiles/
  quickshell/
    island -> ../../src/island-dots
```

and stow the parent of `quickshell`. The `install.sh` symlink does the same thing more directly.

## 3. Autostart

Add one line to your compositor config. Copy from `examples/` rather than retyping keybinds.

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

`island-startup` is idempotent. It handles XDG_RUNTIME_DIR, dbus, PipeWire on non-systemd systems, clipboard, wallpaper and Quickshell. If you prefer systemd to supervise the shell:

```sh
./install.sh --autostart systemd --enable
```

Then remove the compositor's `island-startup` line. The unit is in [services/systemd/island.service](../services/systemd/island.service).

## 4. Optional extras

```sh
./apply-theme.sh space       # apply a palette
./apply-settings.sh          # push the saved settings to the compositor and apps
./sddm/install.sh --theme    # install or refresh the SDDM login theme
./sddm/install.sh            # make SDDM the display manager (asks for sudo)
```

`apply-theme.sh` and `apply-settings.sh` are normally called by the shell. Run them by hand after a fresh install, or after editing state outside the Settings window.

## Manual install without any script

1. Install the core packages above.
2. Put the checkout at `~/.config/quickshell/island` (symlink or copy).
3. Add the autostart line from step 3.
4. Make the scripts executable: `chmod +x ~/.config/quickshell/island/scripts/*.sh ~/.config/quickshell/island/scripts/island-* ~/.config/quickshell/island/*.sh`.
5. Run `~/.config/quickshell/island/scripts/island-startup`.
6. Open Settings with `qs -c island ipc call settings toggle` and pick a theme, wallpaper and font.

No root is needed except for the SDDM theme and for installing system packages.

## Rollback

- Installer backup: see the path printed by `./install.sh`.
- Themes and generated app configs are written only when their content changes. To go back to an older palette, re-run `./apply-theme.sh <old-id>`.
- Remove the autostart line and the systemd unit, then remove `~/.config/quickshell/island`.
- `sddm/install.sh` changes the display manager. On systemd, undo it with `sudo systemctl enable --force <old-display-manager>.service`; on OpenRC or runit use the undo command printed by the script.
