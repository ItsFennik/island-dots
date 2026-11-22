#!/usr/bin/env bash
# Install Island into a Quickshell config directory.
#
#   ./install.sh                    symlink this checkout to ~/.config/quickshell/island
#   ./install.sh --copy             copy instead of symlink
#   ./install.sh --target DIR       install somewhere else
#   ./install.sh --init NAME        auto, systemd, openrc, runit, s6, dinit or none
#   ./install.sh --autostart MODE   compositor (default), systemd or none
#   ./install.sh --enable            enable and start the systemd user unit
#   ./install.sh --theme ID          apply a theme after installing
#   ./install.sh --dry-run           print the actions, change nothing
#   ./install.sh --no-deps           skip the command report
#   ./install.sh --help
#
# No root is needed. Existing configs are moved to
# ~/.local/state/island/install-backups/<timestamp>/.
# systemd user units are optional; OpenRC, runit, s6 and dinit do not need one
# because the compositor starts Island through scripts/island-startup.

set -u

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/island"
target="$XDG_CONFIG_HOME/quickshell/island"
mode="link"
init="${ISLAND_INIT:-auto}"
autostart=compositor
enable=0
theme=""
dry=0
deps=1

usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case $1 in
    --copy) mode=copy ;;
    --link) mode="link" ;;
    --target) target="${2:-}"; shift ;;
    --target=*) target="${1#*=}" ;;
    --init) init="${2:-}"; shift ;;
    --init=*) init="${1#*=}" ;;
    --autostart) autostart="${2:-}"; shift ;;
    --autostart=*) autostart="${1#*=}" ;;
    --enable) enable=1 ;;
    --theme) theme="${2:-}"; shift ;;
    --theme=*) theme="${1#*=}" ;;
    --dry-run) dry=1 ;;
    --no-deps) deps=0 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'install.sh: unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

have() { command -v "$1" >/dev/null 2>&1; }
say() { printf '%s\n' "$*"; }
die() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

[ -n "$target" ] || die "--target needs a directory"
case $mode in link|copy) ;; *) die "unknown deploy mode: $mode" ;; esac
case $autostart in compositor|systemd|none) ;; *) die "unknown autostart mode: $autostart" ;; esac
case $init in auto|systemd|openrc|runit|s6|dinit|none) ;; *) die "unknown init: $init" ;; esac

detect_init() {
  if [ -d /run/systemd/system ]; then printf systemd
  elif have rc-service; then printf openrc
  elif [ -d /run/runit ] || [ -d /etc/runit ]; then printf runit
  elif have s6-rc; then printf s6
  elif have dinitctl; then printf dinit
  else printf none
  fi
}
[ "$init" = auto ] && init="$(detect_init)"

if [ "$autostart" = systemd ] && [ "$init" != systemd ]; then
  die "--autostart systemd needs a systemd user manager; detected init: $init"
fi

if [ "$deps" = 1 ]; then
  missing=""
  for c in qs jq curl gdbus gio notify-send; do
    have "$c" || missing="$missing $c"
  done
  if ! have hyprctl && ! have mmsg && ! have niri && ! have swaymsg; then
    missing="$missing compositor-cli"
  fi
  if [ -n "$missing" ]; then
    say "Missing commands:$missing"
    say "See docs/installation.md for the guide for your distribution. Installation continues."
  else
    say "Core commands found."
  fi
fi

real_target=""
[ -e "$target" ] && real_target="$(cd -- "$target" 2>/dev/null && pwd -P || true)"
real_root="$(cd -- "$ROOT" && pwd -P)"
if [ "$real_target" = "$real_root" ]; then
  say "Already installed at $target"
else
  backup=""
  if [ -e "$target" ] || [ -L "$target" ]; then
    backup="$STATE/install-backups/$(date +%Y%m%d-%H%M%S)"
    say "Backing up $target to $backup"
    [ "$dry" = 1 ] || mkdir -p "$backup"
    [ "$dry" = 1 ] || mv "$target" "$backup/island"
  fi
  if [ "$dry" = 1 ]; then
    say "Would $mode $ROOT to $target"
  else
    mkdir -p "$(dirname -- "$target")" || die "cannot create $(dirname -- "$target")"
    if [ "$mode" = link ]; then
      ln -s "$ROOT" "$target"
    else
      mkdir -p "$target"
      ( cd -- "$ROOT" && tar -cf - \
          --exclude='./.git' --exclude='__pycache__' --exclude='*.pyc' . ) |
        ( cd -- "$target" && tar -xf - )
    fi
    say "Installed to $target"
  fi
  [ -n "$backup" ] && say "Rollback: rm -rf '$target' && mv '$backup/island' '$target'"
fi

unit_src="$ROOT/services/systemd/island.service"
unit_dir="$XDG_CONFIG_HOME/systemd/user"
unit_dst="$unit_dir/island.service"
if [ "$autostart" = systemd ]; then
  if [ "$dry" = 1 ]; then
    say "Would install $unit_dst"
  else
    mkdir -p "$unit_dir"
    sed "s|@TARGET@|$target|g" "$unit_src" >"$unit_dst"
    say "Installed $unit_dst"
    if have systemctl; then
      systemctl --user daemon-reload >/dev/null 2>&1 || true
      if [ "$enable" = 1 ]; then
        systemctl --user enable --now island.service ||
          say "Could not enable island.service; run: systemctl --user enable --now island.service"
      else
        say "Enable it with: systemctl --user enable --now island.service"
      fi
    fi
  fi
  say "Remove the compositor's island-startup line when using the systemd unit."
else
  say "No init service files are installed: the compositor starts Island."
  case $init in
    systemd) say "systemd alternative: re-run with --autostart systemd" ;;
    openrc|runit|s6|dinit|none) say "Detected init: $init (compositor autostart selected)" ;;
  esac
fi

if [ "$autostart" = compositor ]; then
  say ""
  say "Add this to your compositor config (see examples/):"
  if [ -n "${MANGO_INSTANCE_SIGNATURE:-}" ] || [[ ${XDG_CURRENT_DESKTOP:-} == *[Mm]ango* ]]; then
    say "  exec-once=$target/scripts/island-startup"
  elif [ -n "${SWAYSOCK:-}" ] || [[ ${XDG_CURRENT_DESKTOP:-} == *[Ss]way* ]]; then
    say "  exec $target/scripts/island-startup"
  elif [ -n "${NIRI_SOCKET:-}" ]; then
    say "  spawn-at-startup \"sh\" \"-c\" \"$target/scripts/island-startup\""
  elif [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    say "  exec-once = $target/scripts/island-startup"
  else
    say "  hyprland: exec-once = $target/scripts/island-startup"
    say "  niri:     spawn-at-startup \"sh\" \"-c\" \"$target/scripts/island-startup\""
    say "  sway:     exec $target/scripts/island-startup"
    say "  mango:    exec-once=$target/scripts/island-startup"
  fi
fi

if [ -n "$theme" ]; then
  if [ -x "$target/apply-theme.sh" ] && [ "$dry" = 0 ]; then
    "$target/apply-theme.sh" "$theme"
  else
    say "Would apply theme: $theme"
  fi
fi

say ""
say "Manual start: $target/scripts/island-startup"
say "Logs: ${XDG_STATE_HOME:-$HOME/.local/state}/island/logs/startup.log"
say "Docs: $target/docs/installation.md"
