#!/usr/bin/env bash
# Install the Island SDDM theme and make SDDM your login screen.
#
#   ./sddm/install.sh            install the theme and switch the display manager to SDDM
#   ./sddm/install.sh --theme    only (re)install the theme, e.g. after changing wallpaper
#
# Re-runs itself with sudo. Takes effect at the next boot (switching display managers
# from inside a running session would end it). The display manager is enabled through
# systemd, OpenRC, runit or dinit, whichever this system uses.
set -euo pipefail

[ "$(id -u)" = 0 ] || exec sudo "$0" "$@"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/island"
DEST=/usr/share/sddm/themes/island
USER_NAME="${SUDO_USER:-$(logname 2>/dev/null || echo "")}"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
STATE="$USER_HOME/.local/state/island"

command -v sddm >/dev/null || { echo "SDDM isn't installed (e.g. sudo dnf install sddm / pacman -S sddm / apt install sddm)." >&2; exit 1; }

# Theme
install -d "$DEST"
install -m644 "$SRC/Main.qml" "$SRC/metadata.desktop" "$SRC/theme.conf" "$DEST/"
[ -f "$SRC/preview.png" ] && install -m644 "$SRC/preview.png" "$DEST/"

# Your current Island wallpaper becomes the login background (the greeter can't read $HOME).
wall="$(cat "$STATE/wallpaper" 2>/dev/null || true)"
if [ -n "$wall" ] && [ -f "$wall" ]; then
  ext="${wall##*.}"
  rm -f "$DEST"/background.*
  install -m644 "$wall" "$DEST/background.$ext"
  sed -i "s|^background=.*|background=background.$ext|" "$DEST/theme.conf"
  echo "Background: $wall"
fi

# Your picture (~/.face.icon or ~/.face), where SDDM looks for it.
for f in "$USER_HOME/.face.icon" "$USER_HOME/.face"; do
  if [ -f "$f" ]; then install -Dm644 "$f" "/usr/share/sddm/faces/$USER_NAME.face.icon"; echo "Picture: $f"; break; fi
done

# Clock format from Island's settings.
if command -v jq >/dev/null && [ -f "$USER_HOME/.config/island/settings.json" ]; then
  c24="$(jq -r 'if has("clock24h") then .clock24h else true end' "$USER_HOME/.config/island/settings.json" 2>/dev/null || echo true)"
  sed -i "s|^clock24h=.*|clock24h=$c24|" "$DEST/theme.conf"
fi

# Cursor: only themes installed system-wide are visible to the greeter.
cursor=""
if command -v jq >/dev/null && [ -f "$USER_HOME/.config/island/settings.json" ]; then
  cursor="$(jq -r '.cursorTheme // empty' "$USER_HOME/.config/island/settings.json" 2>/dev/null || true)"
fi
[ -n "$cursor" ] && [ ! -d "/usr/share/icons/$cursor" ] && cursor=""

install -d /etc/sddm.conf.d
{
  echo "# Written by quickshell/island/sddm/install.sh"
  echo "[Theme]"
  echo "Current=island"
  [ -n "$cursor" ] && echo "CursorTheme=$cursor"
} > /etc/sddm.conf.d/zz-island.conf     # zz: read last, so it wins over other theme settings
echo "Theme installed to $DEST"

[ "${1:-}" = "--theme" ] && exit 0

# Display manager
if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
  current="$(basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" 2>/dev/null || true)"
  if [ "$current" = "sddm.service" ]; then
    echo "SDDM is already the display manager."
  else
    echo "Switching display manager: ${current:-none} -> sddm.service"
    systemctl enable --force sddm.service
    echo "Done. SDDM takes over at the next boot. (Undo: sudo systemctl enable --force ${current:-greetd.service})"
  fi
elif command -v rc-update >/dev/null 2>&1 && [ -f /etc/init.d/sddm ]; then
  rc-update add sddm default
  echo "SDDM enabled in the OpenRC default runlevel. Undo: rc-update del sddm default"
elif [ -d /etc/sv/sddm ] && [ -d /etc/runit/runsvdir/default ]; then
  ln -sfn /etc/sv/sddm /etc/runit/runsvdir/default/sddm
  echo "SDDM linked into the runit default runlevel. Undo: rm /etc/runit/runsvdir/default/sddm"
elif command -v dinitctl >/dev/null 2>&1; then
  dinitctl enable sddm
  echo "SDDM enabled with dinit. Undo: dinitctl disable sddm"
else
  echo "Could not detect how to enable SDDM."
  echo "Enable the sddm service with your init system, or start it from your display-manager setup."
fi
