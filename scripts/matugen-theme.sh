#!/usr/bin/env bash
# Build an Island theme from a wallpaper with matugen, then apply it everywhere.
#   matugen-theme.sh [image]     (defaults to the current wallpaper)
# Scheme / mode / colour preference come from Island Settings
# (matugenScheme, matugenMode, matugenPrefer). Writes themes/matugen.json.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/island"
SETTINGS="$CFG/island/settings.json"

command -v matugen >/dev/null || { echo "matugen not installed" >&2; exit 1; }

setting() {
  jq -er --arg k "$1" '.[$k] // empty' "$SETTINGS" 2>/dev/null ||
  jq -er --arg k "$1" '.[$k] // empty' "$HERE/defaults.json" 2>/dev/null || printf '%s' "$2"
}
scheme="$(setting matugenScheme tonal-spot)"
mode="$(setting matugenMode dark)"
prefer="$(setting matugenPrefer saturation)"

img="${1:-$(cat "$STATE/wallpaper" 2>/dev/null || true)}"
# Video wallpaper (mpvpaper): read colours from its poster frame instead.
case "${img,,}" in *.mp4|*.webm|*.mkv|*.mov|*.m4v|*.avi)
  img="${XDG_CACHE_HOME:-$HOME/.cache}/island/video-thumbs/$(printf '%s' "$img" | md5sum | cut -d' ' -f1).jpg" ;;
esac
[ -f "$img" ] || { echo "no wallpaper to read colours from" >&2; exit 1; }

matugen image "$img" --json hex --dry-run -m "$mode" -t "scheme-$scheme" --prefer "$prefer" 2>/dev/null |
jq --arg mode "$mode" '
  .colors as $c
  | def col(k): ($c[k][$mode].color // $c[k].default.color);
  {
    name: "Wallpaper (matugen)", dark: ($mode == "dark"),
    bg: col("surface"), bg_alt: col("surface_container_lowest"),
    surface: col("surface_container_high"), overlay: col("outline_variant"),
    fg: col("on_surface"), fg_dim: col("on_surface_variant"), fg_faint: col("outline"),
    accent: col("primary"), accent_fg: col("on_primary"),
    red: col("error"), green: col("tertiary"), yellow: col("secondary_fixed_dim"),
    blue: col("primary"), magenta: col("inverse_primary"), cyan: col("secondary")
  }' > "$HERE/themes/matugen.json.tmp"

mv "$HERE/themes/matugen.json.tmp" "$HERE/themes/matugen.json"
exec "$HERE/apply-theme.sh" matugen
