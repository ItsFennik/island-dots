#!/bin/sh
# Island screenshots. Prints the saved file (or "clipboard:<temp file>") on success; exits 1 if cancelled.
#   screenshot.sh <screen|all|window|region> [options]
#     --dir DIR      save here (default ~/Pictures/Screenshots); --no-save = clipboard only
#     --copy         also copy the image to the clipboard
#     --delay N      wait N seconds first
#     --pointer      include the mouse pointer
#     --sound        play the shutter sound
mode=${1:-region}; [ $# -gt 0 ] && shift
dir="$HOME/Pictures/Screenshots"; save=1; copy=0; delay=0; freeze=0; pointer=""; sound=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) dir=$2; shift ;;
    --no-save) save=0 ;;
    --copy) copy=1 ;;
    --delay) delay=$2; shift ;;
    --freeze) ;;   # (removed: hyprpicker's freeze layer stole slurp's clicks)
    --pointer) pointer="-c" ;;
    --sound) sound=1 ;;
  esac
  shift
done
log="${XDG_RUNTIME_DIR:-/tmp}/island-screenshot.log"
echo "$(date +%T) start mode=$mode" >> "$log"
case "$dir" in "~"*) dir="$HOME${dir#\~}" ;; esac
[ "$save" = 0 ] && copy=1

hypr() { [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] && command -v hyprctl >/dev/null; }

# Let Island's toolbar / menu unmap before anything is captured.
sleep 0.15
[ "$delay" -gt 0 ] 2>/dev/null && sleep "$delay"


geom=""; output=""
case "$mode" in
  screen)   # the monitor under focus
    hypr && output=$(hyprctl -j monitors | jq -r '.[] | select(.focused) | .name') ;;
  all) ;;
  window)   # click a window on any visible workspace
    if hypr; then
      boxes=$(hyprctl -j monitors | jq -r '[.[] | .activeWorkspace.id, .specialWorkspace.id] | map(select(. != null and . != 0)) | @json')
      geom=$(hyprctl -j clients | jq -r --argjson ws "$boxes" \
        '.[] | select(.mapped and (.hidden | not) and (.workspace.id as $w | $ws | index($w))) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1]) \(.title)"' \
        | slurp -r -b '#00000040' -c '#ffffffcc' -B '#0a84ff40' -w 2) || exit 1
    else
      geom=$(slurp -o -b '#00000040' -c '#ffffffcc' -w 2 </dev/null) || exit 1
    fi
    geom=$(printf '%s' "$geom" | cut -d' ' -f1,2) ;;
  region|*)
    geom=$(slurp -d -b '#00000059' -c '#ffffffdd' -s '#00000000' -w 1 </dev/null) || { echo "$(date +%T) slurp cancelled/failed ($?)" >> "$log"; exit 1; } ;;
esac
echo "$(date +%T) picked geom='$geom' output='$output'" >> "$log"

file=$(mktemp --suffix=.png "${XDG_RUNTIME_DIR:-/tmp}/island-shot-XXXXXX") || exit 1
if [ -n "$geom" ]; then grim $pointer -g "$geom" "$file"
elif [ -n "$output" ]; then grim $pointer -o "$output" "$file"
else grim $pointer "$file"; fi || { rm -f "$file"; exit 1; }

[ "$sound" = 1 ] && command -v pw-play >/dev/null && [ -f /usr/share/sounds/freedesktop/stereo/screen-capture.oga ] \
  && setsid -f pw-play /usr/share/sounds/freedesktop/stereo/screen-capture.oga >/dev/null 2>&1
[ "$copy" = 1 ] && wl-copy --type image/png < "$file" >/dev/null 2>&1

if [ "$save" = 1 ]; then
  mkdir -p "$dir"
  out="$dir/Screenshot $(date '+%Y-%m-%d at %H.%M.%S').png"
  n=2; base=${out%.png}; while [ -e "$out" ]; do out="$base ($n).png"; n=$((n + 1)); done
  chmod 644 "$file"; mv "$file" "$out" && echo "$(date +%T) saved $out" >> "$log" && printf '%s\n' "$out"
else
  # Clipboard only: keep the temp file (tmpfs) so Island can show a thumbnail of it.
  printf 'clipboard:%s\n' "$file"
fi
