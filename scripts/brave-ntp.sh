#!/usr/bin/env bash
# Minimal Brave new-tab page in the theme colour. Only edits profiles of a Brave that isn't running,
# since Brave writes its prefs back on exit. Run by apply-theme.sh and the brave-origin launcher.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/island/theme"
id="$(cat "$STATE" 2>/dev/null)" || exit 0
bg="$(jq -r '.bg // empty' "$HERE/themes/$id.json" 2>/dev/null)"
[ -n "$bg" ] || exit 0

for root in "${XDG_CONFIG_HOME:-$HOME/.config}"/BraveSoftware/*/; do
  # SingletonLock -> "<host>-<pid>" while that Brave is running.
  lock="$(readlink "$root/SingletonLock" 2>/dev/null)"
  [ -n "$lock" ] && kill -0 "${lock##*-}" 2>/dev/null && continue
  for prefs in "$root"/Default/Preferences "$root"/Profile*/Preferences; do
    [ -f "$prefs" ] || continue
    tmp="$prefs.island-tmp"
    jq --arg bg "$bg" '
      .brave.new_tab_page.background = {type: "color", selected_value: $bg, random: false}
      | .brave.new_tab_page.show_background_image = true
      | .brave.new_tab_page.hide_all_widgets = true
      | .brave.new_tab_page.show_stats = false
      | .brave.new_tab_page.show_clock = false
      | .brave.new_tab_page.show_rewards = false
      | .brave.new_tab_page.show_brave_vpn = false
      | .brave.new_tab_page.show_together = false
      | .ntp.shortcust_visible = false
    ' "$prefs" > "$tmp" 2>/dev/null && [ -s "$tmp" ] && mv "$tmp" "$prefs" || rm -f "$tmp"
  done
done
exit 0
