#!/usr/bin/env bash
# Exit 0 on the first Island start this boot + session (and record it), 1 otherwise.
# Lets overlays/Lock.qml lock once at login without re-locking on hot reloads.
set -u
state="${XDG_STATE_HOME:-$HOME/.local/state}/island"
boot=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null) || boot=unknown
if [ -n "${ISLAND_SESSION_ID:-}" ]; then
  session="$ISLAND_SESSION_ID"
elif [ -n "${XDG_SESSION_ID:-}" ]; then
  session="$XDG_SESSION_ID"
elif command -v loginctl >/dev/null 2>&1 &&
     session="$(loginctl show-session self -p Id --value 2>/dev/null)" &&
     [ -n "$session" ]; then
  :
else
  # No logind/elogind: use the compositor process start time, which is stable for
  # one session and changes at the next login.
  pid=""
  for c in mango Hyprland niri sway labwc river wayfire; do
    pid="$(pgrep -x "$c" 2>/dev/null | head -n1)"
    [ -n "$pid" ] && break
  done
  session="proc:$(stat -c %Y "/proc/${pid:-1}" 2>/dev/null || echo 0)"
fi
stamp="$boot:$session"
mkdir -p "$state" || exit 1
[[ -f $state/session-stamp && $(<"$state/session-stamp") == "$stamp" ]] && exit 1
printf '%s\n' "$stamp" >"$state/session-stamp" || exit 1
exit 0
