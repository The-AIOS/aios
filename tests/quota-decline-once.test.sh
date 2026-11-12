#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Rotation: one notification per capped stretch, not one every 5 minutes (#298)
#
# WHY THIS EXISTS
# Since the lone-reading fallback (#281), an idle machine with every account near its
# cap could cycle every 5 minutes: confirm, find no account to rotate to, write a
# "declined" row, notify, re-arm. A notification every 5 minutes for a state that had
# not changed.
#
# WHAT IT HOLDS
#   * the first decline for an account notifies and logs a row; repeats for the same
#     account, while the stretch lasts, do neither
#   * the stretch ends when a reading drops under the threshold, or a swap happens,
#     and the next decline notifies again
#   * the decline path itself asks the stretch marker before it notifies (source check)
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PYBIN=""
for _cand in python3 python "py -3"; do
  if $_cand -c 'import sys' >/dev/null 2>&1; then PYBIN="$_cand"; break; fi
done
[ -n "$PYBIN" ] || { echo "SKIP: no working Python found" >&2; exit 0; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.claude"
HOME="$T" USERPROFILE="$T" USER_MD_PATH=/dev/null AIOS_QUOTA_NOTIFY=0 \
  $PYBIN - "hooks/claude-identity/_watch.py" <<'PY'
import importlib.util, inspect, sys
spec = importlib.util.spec_from_file_location("w", sys.argv[1])
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
P = F = 0
def check(label, got, want):
    global P, F
    if got == want: P += 1; print("  ok   " + label)
    else: F += 1; print(f"  FAIL {label}\n     got {got!r}, want {want!r}")
has = hasattr(w, "decline_is_new") and hasattr(w, "end_decline_stretch")
check("the watcher has a decline-stretch marker", has, True)
if has:
    A, B = "a@example.com", "b@example.com"
    w.end_decline_stretch()
    check("the first decline for an account is new (notify)", w.decline_is_new(A), True)
    check("a second decline for the same account is not", w.decline_is_new(A), False)
    check("nor a third", w.decline_is_new(A), False)
    check("a decline for a different account is new", w.decline_is_new(B), True)
    w.end_decline_stretch()
    check("after the stretch ends, the next decline notifies again", w.decline_is_new(B), True)
src = inspect.getsource(w)
i = src.find('"action": "declined"')
check("the decline path asks the marker before logging and notifying",
      i > 0 and "decline_is_new(" in src[max(0, i - 900):i], True)
check("a low reading ends the stretch", "end_decline_stretch()" in inspect.getsource(w.low_reading) if hasattr(w, "low_reading") else False, True)
print(f"\n-- {P} passed, {F} failed --")
sys.exit(1 if F else 0)
PY
