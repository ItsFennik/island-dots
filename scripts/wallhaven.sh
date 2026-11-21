#!/usr/bin/env bash
# Wallhaven (wallhaven.cc) for Island: search, download into wallDir, set.
#
# Usage:
#   wallhaven.sh search [query] [page] [seed]   JSON results for the picker (always valid JSON)
#   wallhaven.sh thumbs <id> <url> [<id> <url>…] cache thumbnails; prints each id as its file is ready
#   wallhaven.sh preview <id> <full-url>        cache the full image (for the picker), print its path
#   wallhaven.sh get <id> [full-url]            download into wallDir (wallhaven-<id>.<ext>), print the path
#   wallhaven.sh set <id> [full-url]            download + set as wallpaper
#   wallhaven.sh random [query]                 random hit for your filters → wallpaper
#   wallhaven.sh save-key                       store $WALLHAVEN_NEW_KEY as the API key (empty = remove)
#
# API key (only needed for NSFW, or to use your account's blacklist):
#   ~/.config/island/wallhaven-api-key   (one line, chmod 600), or set it in Island Settings → Wallpaper.
#   $WALLHAVEN_API_KEY overrides the file. Get a key at https://wallhaven.cc/settings/account
#
# Filters come from Island Settings (wallhaven* keys in ~/.config/island/settings.json).
# Images are fetched here with curl (not by Quickshell), so the shell never loads Qt's network
# and TLS stack; the picker shows the cached files in ~/.cache/island/wallhaven.

set -euo pipefail

HERE="$(dirname "$(readlink -f "$0")")"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/island"
KEY_FILE="$CFG/wallhaven-api-key"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/island/wallhaven"
API="https://wallhaven.cc/api/v1"
UA="island-wallpaper"

# All settings in one jq run: defaults.json overlaid with settings.json.
declare -A S=()
while IFS=$'\t' read -r k v; do S[$k]="$v"; done < <(
  jq -rn '[inputs] | add // {} | to_entries[] | "\(.key)\t\(.value | tostring)"' \
    "$HERE/../defaults.json" $( [ -s "$CFG/settings.json" ] && printf '%s' "$CFG/settings.json" ) 2>/dev/null || true)
setting() { local v="${S[$1]-}"; printf '%s' "${v:-${2:-}}"; }

DIR="$(setting wallDir "$HOME/Pictures/Wallpapers")"; DIR="${DIR/#\~/$HOME}"

notify() { command -v notify-send >/dev/null 2>&1 && notify-send -a island -i image "$1" "${2:-}" || true; }

api_key() {
  if [ -n "${WALLHAVEN_API_KEY:-}" ]; then printf '%s' "$WALLHAVEN_API_KEY"; return; fi
  [ -r "$KEY_FILE" ] && grep -v '^\s*#' "$KEY_FILE" | tr -d '[:space:]' | head -c 128 || true
}
KEY="$(api_key)"

# GET $API$1 with extra curl args; prints body, then the HTTP status on the last line.
# The key goes in a header (not the URL), read from a pipe so it never shows up in `ps`.
api_get() {
  local path="$1"; shift
  if [ -n "$KEY" ]; then
    curl -sS -G --max-time 20 -A "$UA" -w '\n%{http_code}' -H @<(printf 'X-API-Key: %s\n' "$KEY") "$@" "$API$path"
  else
    curl -sS -G --max-time 20 -A "$UA" -w '\n%{http_code}' "$@" "$API$path"
  fi
}

http_error() {
  case "$1" in
    401) printf 'API key rejected (or NSFW without a key)' ;;
    429) printf 'Rate limited by Wallhaven, try again in a minute' ;;
    000) printf "Can't reach wallhaven.cc" ;;
    *)   printf 'Wallhaven returned HTTP %s' "$1" ;;
  esac
}

valid_id() { [[ "$1" =~ ^[a-z0-9]{1,16}$ ]]; }
bits() { [ "$(setting "$1" "$2")" = true ] && printf 1 || printf 0; }

do_search() {
  local q="${1-$(setting wallhavenQuery "")}" page="${2:-1}" seed="${3:-}" sorting="${4:-$(setting wallhavenSorting toplist)}"
  local cats purity out code body atleast ratios
  cats="$(bits wallhavenGeneral true)$(bits wallhavenAnime true)$(bits wallhavenPeople false)"
  purity="1$(bits wallhavenSketchy false)$(bits wallhavenNsfw false)"
  [ "$cats" = 000 ] && cats=111
  local args=(--data-urlencode "q=$q" -d "categories=$cats" -d "purity=$purity" -d "sorting=$sorting" -d "order=desc" -d "page=$page")
  [ "$sorting" = toplist ] && args+=(-d "topRange=$(setting wallhavenTopRange 1M)")
  [ "$sorting" = random ] && [ -n "$seed" ] && args+=(-d "seed=$seed")
  atleast="$(setting wallhavenAtleast "")"; ratios="$(setting wallhavenRatios "")"
  [ -n "$atleast" ] && args+=(-d "atleast=$atleast")
  [ -n "$ratios" ] && args+=(-d "ratios=${ratios// /}")

  out="$(api_get /search "${args[@]}" 2>/dev/null || printf '\n000')"
  code="${out##*$'\n'}"; body="${out%$'\n'*}"
  if [ "$code" != 200 ]; then
    jq -cn --arg e "$(http_error "$code")" '{error: $e, items: []}'
    return
  fi
  printf '%s' "$body" | jq -c --arg dir "$DIR" --arg cache "$CACHE" '{
      page: (.meta.current_page // 1), last: (.meta.last_page // 1), seed: (.meta.seed // ""), total: (.meta.total // 0),
      items: [.data[] | { wid: .id, thumb: .thumbs.large, full: .path, res: .resolution, category, purity,
                          favs: .favorites, tfile: ($cache + "/thumbs/" + .id + ".jpg"), ready: false,
                          file: ($dir + "/wallhaven-" + .id + "." + (.path | split(".") | last)) }]
    }' 2>/dev/null || jq -cn '{error: "Unexpected reply from Wallhaven", items: []}'
  # Old thumbnails go after two weeks.
  [ "$page" = 1 ] && find "$CACHE/thumbs" -type f -mtime +14 -delete 2>/dev/null || true
}

# Thumbnails in parallel; prints each id once its file exists (cached ones straight away).
do_thumbs() {
  local d="$CACHE/thumbs" id url args=()
  mkdir -p "$d"
  while [ $# -ge 2 ]; do
    id="$1"; url="$2"; shift 2
    valid_id "$id" && [[ "$url" == https://th.wallhaven.cc/* ]] || continue
    if [ -s "$d/$id.jpg" ]; then echo "$id"; else args+=(-o "$d/$id.jpg.part" "$url"); fi
  done
  [ ${#args[@]} -gt 0 ] || return 0
  curl -sS --fail --parallel --parallel-max 8 --max-time 30 -A "$UA" -w '%{filename_effective}\n' "${args[@]}" 2>/dev/null |
    while IFS= read -r p; do
      [ -s "$p" ] && mv -f "$p" "${p%.part}" && basename "${p%.part}" .jpg
    done
  rm -f "$d"/*.part 2>/dev/null || true
}

# The full image, cached for the picker's big preview (the last 8 are kept).
do_preview() {
  local id="${1:?id}" url="${2:?url}" d="$CACHE/full" f
  valid_id "$id" && [[ "$url" == https://w.wallhaven.cc/* ]] || return 1
  mkdir -p "$d"; f="$d/$id.${url##*.}"
  if [ ! -s "$f" ]; then
    curl -sSf --max-time 120 -A "$UA" -o "$f.part" "$url" || { rm -f "$f.part"; return 1; }
    mv -f "$f.part" "$f"
  fi
  touch "$f"
  ls -1t "$d" | tail -n +9 | while IFS= read -r old; do rm -f "$d/$old"; done
  printf '%s\n' "$f"
}

do_get() {
  local id="${1:?id}" url="${2:-}" out code dest
  valid_id "$id" || { echo "bad id: $id" >&2; return 1; }
  if [ -z "$url" ]; then
    out="$(api_get "/w/$id" 2>/dev/null || printf '\n000')"
    code="${out##*$'\n'}"
    [ "$code" = 200 ] || { notify "Wallhaven" "$(http_error "$code")"; return 1; }
    url="$(printf '%s' "${out%$'\n'*}" | jq -r '.data.path')"
  fi
  [[ "$url" == https://w.wallhaven.cc/* ]] || { echo "unexpected image url: $url" >&2; return 1; }
  mkdir -p "$DIR"
  dest="$DIR/wallhaven-$id.${url##*.}"
  if [ ! -s "$dest" ]; then
    local cached="$CACHE/full/$id.${url##*.}"
    if [ -s "$cached" ]; then
      cp -f "$cached" "$dest.part"          # already previewed: no second download
    else
      curl -sSfL --max-time 120 -A "$UA" -o "$dest.part" "$url" || { rm -f "$dest.part"; notify "Wallhaven" "Download failed: $id"; return 1; }
    fi
    mv -f "$dest.part" "$dest"
  fi
  printf '%s\n' "$dest"
}

case "${1:-}" in
  search)  shift; do_search "$@" ;;
  thumbs)  shift; do_thumbs "$@" ;;
  preview) shift; do_preview "$@" ;;
  get)     shift; do_get "$@" ;;
  set)     shift; f="$(do_get "$@")" && exec "$HERE/wallpaper-set.sh" "$f" ;;
  random)
    shift
    res="$(do_search "${1-$(setting wallhavenQuery "")}" 1 "" random)"
    err="$(printf '%s' "$res" | jq -r '.error // empty')"
    [ -z "$err" ] || { notify "Wallhaven" "$err"; exit 1; }
    pick="$(printf '%s' "$res" | jq -r '.items | if length == 0 then empty else .[now % length | floor] | "\(.wid) \(.full)" end')"
    [ -n "$pick" ] || { notify "Wallhaven" "No results for your filters"; exit 1; }
    f="$(do_get ${pick})" && exec "$HERE/wallpaper-set.sh" "$f"
    ;;
  save-key)
    new="$(printf '%s' "${WALLHAVEN_NEW_KEY:-}" | tr -d '[:space:]')"
    mkdir -p "$CFG"
    if [ -z "$new" ]; then rm -f "$KEY_FILE"; notify "Wallhaven" "API key removed"; exit 0; fi
    (umask 077; printf '%s\n' "$new" > "$KEY_FILE.tmp" && mv -f "$KEY_FILE.tmp" "$KEY_FILE")
    KEY="$new"
    out="$(api_get /settings 2>/dev/null || printf '\n000')"
    case "${out##*$'\n'}" in
      200) notify "Wallhaven" "API key saved and working" ;;
      401) notify "Wallhaven" "API key saved, but Wallhaven rejected it. Check it on wallhaven.cc/settings/account" ;;
      *)   notify "Wallhaven" "API key saved (couldn't verify it right now)" ;;
    esac
    ;;
  *) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 1 ;;
esac
