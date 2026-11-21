#!/usr/bin/env bash
# Exit 0 on the first Island start this boot + session (and record it), 1 otherwise.
# Lets overlays/Lock.qml lock once at login without re-locking on hot reloads.
set -u
state="${XDG_STATE_HOME:-$HOME/.local/state}/island"
boot=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null) || boot=unknown
session="${XDG_SESSION_ID:-$(loginctl show-session self -p Id --value 2>/dev/null || echo tty)}"
stamp="$boot:$session"
mkdir -p "$state" || exit 1
[[ -f $state/session-stamp && $(<"$state/session-stamp") == "$stamp" ]] && exit 1
printf '%s\n' "$stamp" >"$state/session-stamp" || exit 1
exit 0
