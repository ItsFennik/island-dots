#!/usr/bin/env bash
# Set the wallpaper, remember it, and restore it on login.
#
# Usage:
#   wallpaper-set.sh /path/to/image|video   set a specific image or video
#   wallpaper-set.sh --random               pick a random image/video from wallDir + videoDir
#   wallpaper-set.sh --restore              re-apply the last one (no animation) — use at login
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
  find "$VDIR" -maxdepth 1 -type f \( -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mkv' \
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

if [ -n "$still" ] && [ -f "$still" ]; then
  if [ "$mode" = "restore" ]; then
    "$WP" img "$still" --transition-type none
  else
    "$WP" img "$still" --transition-type "$TRANSITION" --transition-duration "$DURATION" --transition-fps 60
  fi
fi

if is_video "$img"; then
  # Let the poster transition finish, then swap in the video on top of it.
  [ "$mode" = "restore" ] || sleep "$DURATION"
  stop_video
  mpvpaper -f -p -a FULL -o "$MPV_OPTS" ALL "$img" >/dev/null 2>&1
else
  # Kill the video once the new image is underneath, so the switch doesn't flash.
  stop_video
fi

printf '%s\n' "$img" > "$STATE_FILE"

# Wallpaper colours: rebuild the matugen theme for the new image (or video poster).
if [ "$mode" != restore ] && [ "$(setting matugen false)" = true ] && [ -f "$still" ]; then
  "$(dirname "$(readlink -f "$0")")/matugen-theme.sh" "$still" >/dev/null 2>&1 &
fi
