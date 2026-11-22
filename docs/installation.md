# Install

Pick the guide for your distribution. Each one is a complete walkthrough from a fresh machine to a running shell.

| Your distro | Guide |
|---|---|
| Arch, CachyOS, EndeavourOS, Manjaro, Garuda | [docs/install/arch.md](install/arch.md) |
| Artix Linux (and other Arch-based, OpenRC/runit/dinit/s6) | [docs/install/artix.md](install/artix.md) |
| Fedora, and RHEL-like systems | [docs/install/fedora.md](install/fedora.md) |
| Debian, Ubuntu, Mint, Pop!_OS, PikaOS | [docs/install/debian.md](install/debian.md) |
| openSUSE / SUSE-family | [docs/install/opensuse.md](install/opensuse.md) |
| NixOS | [docs/install/nixos.md](install/nixos.md) |
| Gentoo (OpenRC/systemd) | [docs/install/gentoo.md](install/gentoo.md) |
| Void Linux (runit) | [docs/install/void.md](install/void.md) |

Every guide installs the same checkout at `~/.config/quickshell/island`, adds one autostart line to the compositor and finishes with a first-run check. Island needs Quickshell 0.3 or newer and an existing Wayland compositor; it is not a compositor itself.

If your distribution is not listed, follow the closest package-manager guide and check the [Quickshell build instructions](https://github.com/quickshell-mirror/quickshell/blob/master/BUILD.md) for the minimum version.

Only the Fedora + MangoWC path has been exercised end to end. Package names for the other distributions were checked against their current indexes; the source-build and less common init paths are best effort.

## After the first login

- Open Settings with `SUPER + I` from the matching file in [`examples/`](../examples/), or run `qs -c island ipc call settings toggle`.
- Pick a theme, wallpaper and font in Settings, or apply a palette with `./apply-theme.sh orchid`.
- Read `qs log -c island` and `~/.local/state/island/logs/startup.log` when something does not start.
- See [non-systemd.md](non-systemd.md) for OpenRC, runit, s6 and dinit sessions, [theming.md](theming.md) for the palette pipeline and [troubleshooting.md](troubleshooting.md) for common failures.

## Installer and rollback

All guides use the same installer:

```sh
./install.sh --dry-run     # show what would happen
./install.sh               # symlink this checkout into place
./install.sh --copy        # copy instead of symlink
```

An existing target is moved to `~/.local/state/island/install-backups/<timestamp>/island` before it is replaced. To roll back, remove the new target and move the backup back:

```sh
rm -rf ~/.config/quickshell/island
mv ~/.local/state/island/install-backups/<timestamp>/island ~/.config/quickshell/island
```
