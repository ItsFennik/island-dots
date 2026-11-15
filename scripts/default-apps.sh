#!/bin/sh
# Default apps for the Settings "Default Apps" pane.
#   default-apps.sh query MIME...        → one line per MIME: MIME<TAB>default.desktop<TAB>id1;id2;…
#   default-apps.sh set APP.desktop MIME... → makes APP the default for every MIME (~/.config/mimeapps.list)
# Candidates are the desktop entries that list the MIME and aren't hidden; the first
# applications dir in XDG order wins for a given id (so ~/.local/share overrides /usr/share).
set -u
cmd=${1:-}; shift || true

case $cmd in
set)
    app=$1; shift
    exec xdg-mime default "$app" "$@" ;;
query)
    dirs="${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    # id<TAB>mimetypes for every visible entry
    table=$(
        IFS=:
        for d in $dirs; do
            [ -d "$d/applications" ] || continue
            find -L "$d/applications" -name '*.desktop' -type f 2>/dev/null | while read -r f; do
                printf '%s\t%s\n' "${f#"$d/applications/"}" "$f"
            done
        done | awk -F'\t' '
            { id = $1; gsub("/", "-", id); if (id in seen) next; seen[id] = 1
              f = $2; mt = ""; hide = 0; inmain = 0
              while ((getline l < f) > 0) {
                  if (l ~ /^\[/) { inmain = (l == "[Desktop Entry]"); continue }
                  if (!inmain) continue
                  if (l ~ /^MimeType=/) mt = substr(l, 10)
                  else if (l ~ /^(NoDisplay|Hidden)=true/) hide = 1
              }
              close(f)
              if (mt != "" && !hide) print id "\t;" mt }'
    )
    for m in "$@"; do
        def=$(xdg-mime query default "$m" 2>/dev/null)
        cands=$(printf '%s\n' "$table" | awk -F'\t' -v m=";$m;" 'index($2 ";", m) { printf "%s;", $1 }')
        printf '%s\t%s\t%s\n' "$m" "$def" "$cands"
    done ;;
*)
    echo "usage: $0 query MIME… | set APP.desktop MIME…" >&2; exit 2 ;;
esac
