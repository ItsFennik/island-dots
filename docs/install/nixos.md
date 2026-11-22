# Install on NixOS

Island is packaged as a flake, so you can build and run it without installing Quickshell by hand. The flake package starts the shell; the checkout path below adds the full `island-startup` session helpers.

No root is needed for the checkout or the installer. Dependencies come from `configuration.nix`, and the checkout lives in your home. Island is a shell, not a compositor. Enable a Wayland compositor first: `programs.hyprland`, `programs.niri`, `programs.sway` or `programs.mango`.

## 1. Flake quick start

Build the shell straight from the repository:

```sh
nix build github:ItsFennik/island-dots
./result/bin/island
```

The first run symlinks the store copy to `~/.config/quickshell/island` and starts Quickshell. To keep the package in your NixOS configuration, add the repository as a flake input:

```nix
{
  inputs.island-dots.url = "github:ItsFennik/island-dots";
}
```

Pass the inputs to your modules, then install the package:

```nix
{ pkgs, inputs, ... }:
{
  environment.systemPackages = [
    inputs.island-dots.packages.${pkgs.system}.default
  ];
}
```

After `sudo nixos-rebuild switch`, start the shell with `island`. This path starts Quickshell only. Use the checkout below if you want the clipboard watchers, wallpaper restore and the rest of `island-startup`.

## 2. Packages and services

Add this to `configuration.nix` (or a home-manager module) and run `sudo nixos-rebuild switch`:

```nix
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    quickshell
    jq curl glib libnotify bluez
    grim slurp wl-clipboard cliphist
    matugen ddcutil awww mpvpaper ffmpeg
    foot kitty neovim polkit_gnome
  ];

  fonts.packages = with pkgs; [
    adwaita-fonts
    jetbrains-mono
    nerd-fonts.jetbrains-mono
  ];

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
  services.upower.enable = true;
  services.udisks2.enable = true;
  networking.networkmanager.enable = true;
  hardware.bluetooth.enable = true;
  security.polkit.enable = true;

  programs.hyprland.enable = true;   # or programs.niri / programs.sway / programs.mango
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
}
```

For the checkout path, Quickshell must be 0.3 or newer; `nixos-unstable` is current, and NixOS 26.05 ships 0.3.0. NixOS 25.11 had 0.2.1, which is too old. Use `nixos-unstable` or a flake pinned to it:

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
}
```

The `fonts.packages` entry installs `nerd-fonts.jetbrains-mono` system-wide. If you prefer a different font, change it in Settings after the first launch.

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

For the flake-only install, replace the startup script path with `island` in the same line. That starts the packaged shell without the session helpers.

`island-startup` is idempotent: it creates `XDG_RUNTIME_DIR` when needed, starts dbus and PipeWire when no user manager exists, starts the clipboard watchers, restores the wallpaper and launches Quickshell. On NixOS, PipeWire comes from the user units enabled above.

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

```sh
./install.sh --autostart systemd --enable   # optional user unit; remove the compositor line
./apply-theme.sh orchid
./sddm/install.sh --theme                   # theme only
./sddm/install.sh                           # switch the display manager to SDDM
```

For a symlinked install, update with `git -C ~/src/island-dots pull`, then log out and back in.

## Rollback

Remove the autostart line (and disable `island.service` if you installed it) and remove `~/.config/quickshell/island`. Remove the packages from `configuration.nix` and run `nixos-rebuild switch` if you do not want them any more.
