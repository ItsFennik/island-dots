#!/usr/bin/env bash
# Set the wallpaper, remember it, and restore it on login.
#
# Usage:
#   wallpaper-set.sh /path/to/image|video   set a specific image or video
#   wallpaper-set.sh --random               pick a random image/video from wallDir + videoDir
#   wallpaper-set.sh --restore              re-apply the last one (no animation), for login
#   wallpaper-set.sh --thumbs               make picker posters for every video in videoDir
#
# Backends: awww (formerly swww; falls back to swww) for images, mpvpaper for videos.
# A video also gets a poster frame (ffmpeg), which goes to awww underneath the video,
# feeds matugen, and is the picker thumbnail.

set -euo pipefail

# Folders + transition come from Island Settings (~/.config/island/settings.json).
SETTINGS="${XDG_CONFIG_HOME:-$HOME/.config}/island/settings.json"
setting() { [ -s "$SETTINGS" ] && jq -er --arg k "$1" '.[$k] // empty' "$SETTINGS" 2>/dev/null || printf '%s' "$2"; }
DIR="$(setting wallDir "${WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}")"; DIR="${DIR/#\~/$HOME}"
VDIR="$(setting videoDir "$HOME/Videos/Wallpapers")"; VDIR="${VDIR/#\~/$HOME}"
TRANSITION="$(setting wallTransition fade)"
DURATION="$(setting wallDuration 0.8)"
MPV_OPTS="$(setting videoMpvOptions "no-audio loop hwdec=auto panscan=1.0")"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/island"
STATE_FILE="$STATE_DIR/wallpaper"
THUMB_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/island/video-thumbs"
mkdir -p "$STATE_DIR" "$THUMB_DIR"

notify() { command -v notify-send >/dev/null 2>&1 && notify-send -a island "$1" "${2:-}" || true; }

# Smooth ease-out for every awww transition (cubic-bezier.com).
BEZIER="$(setting wallBezier ".25,.8,.25,1")"

# Transition fps = the fastest monitor's refresh rate (180 Hz here), 60 if Hyprland can't say.
trans_fps() {
  local f; f="$(hyprctl monitors -j 2>/dev/null | jq -r '[.[].refreshRate] | max | floor' 2>/dev/null)"
  [[ "$f" =~ ^[0-9]+$ ]] && [ "$f" -ge 30 ] && printf '%s' "$f" || printf 60
}

# Mouse pointer as awww fractions (x from the left, y from the BOTTOM) of the monitor it is on.
cursor_pos() {
  local c; c="$(hyprctl cursorpos 2>/dev/null)" || { printf center; return; }
  hyprctl monitors -j 2>/dev/null | jq -r --arg c "$c" '
    ($c | split(",") | map(ltrimstr(" ") | tonumber)) as [$cx, $cy]
    | map(. + {lw: (.width / .scale), lh: (.height / .scale)})
    | map(select($cx >= .x and $cx < .x + .lw and $cy >= .y and $cy < .y + .lh)) | first
    | if . == null then "center"
      else [($cx - .x) / .lw, 1 - ($cy - .y) / .lh]
           | map([[(. * 1000 | floor) / 1000, 0.001] | max, 0.999] | min | tostring | if test("\\.") then . else . + ".0" end)
           | join(",") end' \
    2>/dev/null || printf center
}

# awww flags for the configured transition. "cursor" = a circle growing out of the pointer.
trans_args() {
  local t="$TRANSITION"
  case "$t" in
    cursor) printf '%s\n' --transition-type grow --transition-pos "$(cursor_pos)" ;;
    *)      printf '%s\n' --transition-type "$t" ;;
  esac
  printf '%s\n' --transition-duration "$DURATION" --transition-fps "$(trans_fps)" --transition-bezier "$BEZIER"
}

is_video() { case "${1,,}" in *.mp4|*.webm|*.mkv|*.mov|*.m4v|*.avi) return 0 ;; *) return 1 ;; esac; }

# Poster path = md5 of the full path (the picker computes the same with Qt.md5).
thumb_of() { printf '%s/%s.jpg' "$THUMB_DIR" "$(printf '%s' "$1" | md5sum | cut -d' ' -f1)"; }
make_thumb() {
  local t; t="$(thumb_of "$1")"
  if [ ! -s "$t" ] || [ "$1" -nt "$t" ]; then
    command -v ffmpeg >/dev/null 2>&1 || return 1
    ffmpeg -loglevel error -y -ss 1 -i "$1" -frames:v 1 -vf "scale=1920:-2" -q:v 3 "$t" </dev/null ||
    ffmpeg -loglevel error -y -i "$1" -frames:v 1 -vf "scale=1920:-2" -q:v 3 "$t" </dev/null || return 1
  fi
  printf '%s' "$t"
}

list_videos() {
  [ -d "$VDIR" ] || return 0
  find "$VDIR" -maxdepth 2 -type f \( -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mkv' \
    -o -iname '*.mov' -o -iname '*.m4v' -o -iname '*.avi' \) 2>/dev/null
}

if [ "${1:-}" = --thumbs ]; then
  while IFS= read -r v; do make_thumb "$v" >/dev/null || true; done < <(list_videos)
  exit 0
fi

if command -v awww >/dev/null 2>&1; then
  WP=awww
elif command -v swww >/dev/null 2>&1; then
  WP=swww
else
  notify "No wallpaper backend" "Install awww (or swww)"
  echo "error: neither awww nor swww found" >&2
  exit 1
fi

ensure_daemon() {
  "$WP" query >/dev/null 2>&1 && return 0
  setsid -f "${WP}-daemon" >/dev/null 2>&1
  for _ in $(seq 1 40); do
    "$WP" query >/dev/null 2>&1 && return 0
    sleep 0.1
  done
  notify "Wallpaper daemon didn't start" "${WP}-daemon"
  exit 1
}

stop_video() {
  pkill -x mpvpaper 2>/dev/null || true
  for _ in $(seq 1 20); do pgrep -x mpvpaper >/dev/null || return 0; sleep 0.05; done
  pkill -9 -x mpvpaper 2>/dev/null || true
}

pick_random() {
  {
    find "$DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
      -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.avif' \) 2>/dev/null
    list_videos
  } | shuf -n1
}

mode="img"
case "${1:-}" in
  --random)  img="$(pick_random)"; [ -n "$img" ] || { notify "No wallpapers" "Nothing in $DIR or $VDIR"; exit 1; } ;;
  --restore)
    mode="restore"
    if [ -r "$STATE_FILE" ] && [ -f "$(<"$STATE_FILE")" ]; then
      img="$(<"$STATE_FILE")"
    else
      img="$(pick_random)"
      [ -n "$img" ] || exit 0   # nothing to restore, nothing to pick: fine
    fi
    ;;
  "") echo "usage: $0 <image|video> | --random | --restore | --thumbs" >&2; exit 1 ;;
  *)  img="$1" ;;
esac

[ -f "$img" ] || { notify "Not a file" "$img"; exit 1; }

# What awww shows (and matugen reads): the image itself, or a video's poster frame.
still="$img"
if is_video "$img"; then
  command -v mpvpaper >/dev/null 2>&1 || { notify "mpvpaper not installed" "Needed for video wallpapers"; exit 1; }
  still="$(make_thumb "$img" || true)"
fi

ensure_daemon

# Video -> picture: drop the video first so the transition plays on screen instead of under mpvpaper
# (awww still holds the old video's poster, so this doesn't flash).
is_video "$img" || [ "$mode" = restore ] || stop_video

if [ -n "$still" ] && [ -f "$still" ]; then
  if [ "$mode" = "restore" ]; then
    "$WP" img "$still" --transition-type none
  else
    mapfile -t targs < <(trans_args)
    "$WP" img "$still" "${targs[@]}"
  fi
fi

if is_video "$img"; then
  # Let the poster transition finish, then swap in the video on top of it.
  [ "$mode" = "restore" ] || sleep "$DURATION"
  stop_video
  # One mpvpaper per monitor, each with its own IPC socket (mpvpaper-<output>.sock), so
  # ~/.config/mango/scripts/wallpaper-autopause.py can pause only the monitors that have windows.
  run="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  rm -f "$run"/mpvpaper*.sock
  mapfile -t outs < <(mmsg get all-monitors 2>/dev/null | jq -r '.monitors[].name' 2>/dev/null)
  [ "${#outs[@]}" -gt 0 ] || outs=(ALL)
  for out in "${outs[@]}"; do
    mpvpaper -f -p -a FULL -o "$MPV_OPTS input-ipc-server=$run/mpvpaper-$out.sock" "$out" "$img" >/dev/null 2>&1
  done
else
  stop_video   # (restore path; otherwise already stopped above)
fi

printf '%s\n' "$img" > "$STATE_FILE"
# Keyboard RGB follows the wallpaper (also on --restore: OpenRGB's Direct mode doesn't survive a reboot).
setsid -f "$(dirname "$(readlink -f "$0")")/keyboard-rgb.sh" "$img" >/dev/null 2>&1 || true
# hyprlock's background (~/.config/hypr/hyprlock.conf): the image, or a video's poster frame.
[ -f "$still" ] && ln -sfn "$still" "${XDG_CACHE_HOME:-$HOME/.cache}/island/lock-wallpaper"

# Wallpaper colours: rebuild the matugen theme for the new image (or video poster).
if [ "$mode" != restore ] && [ "$(setting matugen false)" = true ] && [ -f "$still" ]; then
  "$(dirname "$(readlink -f "$0")")/matugen-theme.sh" "$still" >/dev/null 2>&1 &
elif [ "$mode" != restore ]; then
  # A wallpaper paired with a theme (~/.config/island/theme-walls.json, P in the picker) brings
  # that theme along, however it was picked. Stays put if the current theme also owns it.
  pairs="${XDG_CONFIG_HOME:-$HOME/.config}/island/theme-walls.json"
  cur_theme="$(cat "$STATE_DIR/theme" 2>/dev/null || true)"
  if [ -s "$pairs" ]; then
    want="$(jq -r --arg p "$img" --arg h "$HOME" --arg cur "$cur_theme" '
      [to_entries[] | select(.value | map(sub("^~"; $h)) | index($p)) | .key] as $ids
      | if ($ids | index($cur)) then empty else ($ids[0] // empty) end' "$pairs" 2>/dev/null || true)"
    [ -n "$want" ] && "$(dirname "$(readlink -f "$0")")/../apply-theme.sh" "$want" >/dev/null 2>&1 &
  fi
fi
