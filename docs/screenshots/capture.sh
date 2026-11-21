#!/usr/bin/env bash
# Capture Island screenshots from a running session.
#
#   ./capture.sh [OUTDIR]
#
# Prerequisites: an empty workspace with the bar, dock and widgets visible, a
# wallpaper from this theme, no personal windows. Run from the repository's
# docs/screenshots directory or pass an output directory.
#
# Captures: desktop, bar crop, launcher, Settings, Control Centre, power menu,
# notification toast and lock preview. Terminal, Neovim, tiling and theme
# variants need the extra steps in SHOTS_NEEDED.md.

set -u

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-$HERE}"
have() { command -v "$1" >/dev/null 2>&1; }

have qs || { echo "capture.sh: qs not found" >&2; exit 1; }
have grim || { echo "capture.sh: grim not found" >&2; exit 1; }
mkdir -p "$OUT" || exit 1

output=""
if have mmsg; then
  output="$(mmsg get all-monitors 2>/dev/null | jq -r '.monitors[] | select(.active) | .name' 2>/dev/null | head -n1)"
elif have hyprctl; then
  output="$(hyprctl -j monitors 2>/dev/null | jq -r '.[] | select(.focused) | .name' 2>/dev/null | head -n1)"
fi

shot() {
  local name=$1
  if [ -n "$output" ]; then
    grim -o "$output" "$OUT/$name.png"
  else
    grim "$OUT/$name.png"
  fi
  echo "captured $OUT/$name.png"
}

ipc() { qs -c island ipc call "$@"; }
cleanup() {
  ipc menu close >/dev/null 2>&1
  ipc launcher close >/dev/null 2>&1
  ipc settings close >/dev/null 2>&1
  ipc lock previewOff >/dev/null 2>&1
}
trap cleanup EXIT

shot island-desktop

if have magick; then
  magick "$OUT/island-desktop.png" -crop 1920x44+0+0 +repage "$OUT/island-bar.png" 2>/dev/null &&
    echo "captured $OUT/island-bar.png"
fi

ipc launcher open >/dev/null 2>&1
sleep 0.5
shot island-launcher
ipc launcher close >/dev/null 2>&1
sleep 0.2

ipc settings page appearance >/dev/null 2>&1
sleep 0.8
shot island-settings
ipc settings close >/dev/null 2>&1
sleep 0.2

ipc menu controls >/dev/null 2>&1
sleep 0.5
shot island-control-center
ipc menu close >/dev/null 2>&1
sleep 0.2

ipc menu power >/dev/null 2>&1
sleep 0.5
shot island-power-menu
ipc menu close >/dev/null 2>&1
sleep 0.2

if have notify-send; then
  notify-send -a "Island" -i preferences-desktop-theme \
    "Theme updated" "Island is now using the Space palette." 2>/dev/null || true
  sleep 0.5
  shot island-notifications
  ipc notifs clear >/dev/null 2>&1
  sleep 0.2
fi

ipc lock preview >/dev/null 2>&1
sleep 0.8
shot island-lock-preview
ipc lock previewOff >/dev/null 2>&1
