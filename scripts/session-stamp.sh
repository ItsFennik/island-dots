#!/usr/bin/env bash
# Exit 0 (and record the stamp) on the first Island start since this login, 1 otherwise.
# Keyed by boot id + session id, so hot reloads and `qs -c island -n` don't re-lock, while a
# reboot or a new login does. Used by overlays/Lock.qml for Settings → Desktop & Widgets →
# Lock Screen → "Lock when the session starts".
set -u
state="${XDG_STATE_HOME:-$HOME/.local/state}/island"
boot=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null) || boot=unknown
session="${XDG_SESSION_ID:-$(loginctl show-session self -p Id --value 2>/dev/null || echo tty)}"
stamp="$boot:$session"
mkdir -p "$state" || exit 1
[[ -f $state/session-stamp && $(<"$state/session-stamp") == "$stamp" ]] && exit 1
printf '%s\n' "$stamp" >"$state/session-stamp" || exit 1
exit 0
