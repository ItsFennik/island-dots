#!/usr/bin/env bash
# Light the keyboard with the wallpaper's main colour (OpenRGB, Direct mode).
#   keyboard-rgb.sh [image]      defaults to the current wallpaper
# Called by wallpaper-set.sh on every change and on login. Keeps an OpenRGB server running:
# the keyboard reverts to its rainbow the moment OpenRGB disconnects.
# KEYBOARD_RGB_DEVICE overrides which OpenRGB device is lit (name substring).

set -euo pipefail

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/island"
DEVICE="${KEYBOARD_RGB_DEVICE:-Hi75C}"

command -v openrgb >/dev/null || exit 0
command -v matugen >/dev/null || exit 0

img="${1:-$(cat "$STATE/wallpaper" 2>/dev/null || true)}"
# Video wallpaper: use its poster frame (same path wallpaper-set.sh makes).
case "${img,,}" in *.mp4|*.webm|*.mkv|*.mov|*.m4v|*.avi)
  img="${XDG_CACHE_HOME:-$HOME/.cache}/island/video-thumbs/$(printf '%s' "$img" | md5sum | cut -d' ' -f1).jpg" ;;
esac
[ -f "$img" ] || exit 0

src="$(matugen image "$img" --json hex --dry-run -m dark --prefer saturation 2>/dev/null |
  jq -r '.colors.source_color.default.color // empty')"
[ -n "$src" ] || exit 1

# Wallpaper colours are often dull; LEDs need the hue at full brightness and strong saturation.
hex="$(python3 -I -c '
import colorsys, sys
h = sys.argv[1].lstrip("#")
r, g, b = (int(h[i:i+2], 16) / 255 for i in (0, 2, 4))
hh, s, v = colorsys.rgb_to_hsv(r, g, b)
s = 0 if s < 0.08 else max(s, 0.85)   # near-grey wallpapers stay white
r, g, b = colorsys.hsv_to_rgb(hh, s, 1.0)
print("%02X%02X%02X" % tuple(round(c * 255) for c in (r, g, b)))
' "$src")"

# The keyboard drops back to its built-in rainbow as soon as OpenRGB lets go of it, so keep an
# OpenRGB server running (localhost only) and talk to it as a client.
PORT=6742
listening() { ss -ltnH "sport = :$PORT" 2>/dev/null | grep -q .; }
if ! listening; then
  setsid -f openrgb --server --server-host 127.0.0.1 --server-port "$PORT" --noautoconnect >/dev/null 2>&1
  for _ in $(seq 1 40); do listening && break; sleep 0.25; done
  listening || { echo "OpenRGB server didn't start" >&2; exit 1; }
fi
client() { openrgb --client "127.0.0.1:$PORT" "$@" 2>/dev/null; }

idx="$(client --list-devices |
  awk -v d="$DEVICE" '/^[0-9]+: / && index($0, d) { sub(":", "", $1); print $1; exit }')"
[ -n "$idx" ] || { echo "keyboard '$DEVICE' not found by OpenRGB" >&2; exit 1; }

client -d "$idx" -m Direct -c "$hex" >/dev/null
printf '%s\n' "$hex" > "$STATE/keyboard-rgb"
