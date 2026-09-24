#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# The test suite must never put a quota banner on the machine it runs on
#
# WHY
# tests/multi-account-consistency.test.sh drives real `_watch.py` ticks with
# fixture accounts. `notify()` shells out to osascript / notify-send for real, so
# every local run of the suite showed a genuine macOS banner — "Claude quota
# watch: swapped from a@example.com: 5h at 99%" — indistinguishable from a real
# account swap. It surfaced as a "random" banner nobody could explain, on a
# machine whose own accounts were fine.
#
# WHAT IT CHECKS
#   1. AIOS_QUOTA_NOTIFY=0 silences notify(), and WITHOUT it notify() does call
#      the notifier (the control: otherwise "silenced" could mean "never worked").
#      Both measured through a recording stand-in on PATH — nothing reaches the desktop.
#   2. Every test that drives the watcher sets AIOS_QUOTA_NOTIFY=0.
#   3. The whole watcher suite, run with the recorder on PATH, calls it zero times.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ✓ %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  ✗ %s\n      %s\n' "$1" "${2:-}"; }
PYBIN=""; for _c in python3 python "py -3"; do if $_c -c 'import sys' >/dev/null 2>&1; then PYBIN="$_c"; break; fi; done
[ -n "$PYBIN" ] || { echo "SKIP: no working Python" >&2; exit 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/shim"; : > "$T/calls.log"
for n in osascript notify-send; do
  printf '#!/bin/sh\necho "%s $*" >> "%s/calls.log"\n' "$n" "$T" > "$T/shim/$n"; chmod +x "$T/shim/$n"
done
W=hooks/claude-identity/_watch.py

echo "-- 1. the switch silences notify(), and notify() is live without it --"
call(){ PATH="$T/shim:$PATH" $PYBIN -c "import importlib.util as u,sys;s=u.spec_from_file_location('w','$W');m=u.module_from_spec(s);s.loader.exec_module(m);m.notify('isolation-probe')" ; }
: > "$T/calls.log"; AIOS_QUOTA_NOTIFY=0 call >/dev/null 2>&1
[ "$(grep -c . "$T/calls.log")" -eq 0 ] && ok "AIOS_QUOTA_NOTIFY=0 → no notifier call" || no "AIOS_QUOTA_NOTIFY=0 still called the notifier" "$(head -1 "$T/calls.log")"
: > "$T/calls.log"; ( unset AIOS_QUOTA_NOTIFY; call ) >/dev/null 2>&1
grep -q 'isolation-probe' "$T/calls.log" && ok "control: without it, notify() calls the notifier (operators still get real alerts)" \
  || no "control: notify() made no call even when enabled" "the silence above would prove nothing"

echo "-- 2. every test that drives the watcher sets the switch --"
bad=""
for f in tests/*.sh; do
  case "$f" in tests/watch-notify-isolation.test.sh) continue ;; esac
  grep -q '_watch\.py' "$f" || continue
  grep -qE 'AIOS_QUOTA_NOTIFY=0' "$f" || bad="$bad $f"
done
[ -z "$bad" ] && ok "all watcher-driving tests set AIOS_QUOTA_NOTIFY=0" || no "watcher tests without the switch:$bad" "each run would put a real banner on the desktop"

echo "-- 3. the watcher suite, end to end, reaches the notifier zero times --"
: > "$T/calls.log"
for f in tests/*.sh; do
  case "$f" in tests/watch-notify-isolation.test.sh) continue ;; esac
  grep -q '_watch\.py' "$f" || continue
  PATH="$T/shim:$PATH" bash "$f" >/dev/null 2>&1
done
[ "$(grep -c . "$T/calls.log")" -eq 0 ] && ok "no watcher test reached the desktop notifier" \
  || no "a watcher test still fires a desktop notification" "$(head -1 "$T/calls.log")"

printf '\n  %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
