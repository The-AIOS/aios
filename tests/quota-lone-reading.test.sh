#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Rotation: a lone reading near the cap rotates after 5 minutes (#281)
#
# WHY THIS EXISTS
# A rotation needs two readings of the same account over the threshold, so one stale
# reading from a session that predates a swap cannot move the operator. But with one
# session running, or nobody at the keyboard, no second reading ever arrives: every
# watcher tick re-reads the same sample, and the gate waited forever while the
# account ran into its cap.
#
# WHAT IT HOLDS
#   * the same reading at or above 98%, armed 5 minutes ago by the clock, with no
#     low reading since, rotates
#   * before 5 minutes it does not
#   * a contradicting low reading in the window cancels the fallback
#   * a lone reading under 98% keeps waiting for a second reading (the normal gate)
#   * CONTROL: two distinct readings still confirm the normal way
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
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("w", sys.argv[1])
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
clock = [10_000.0]
w.time.time = lambda: clock[0]
P = F = 0
def check(label, got, want):
    global P, F
    if got == want: P += 1; print("  ok   " + label)
    else: F += 1; print(f"  FAIL {label}\n     got {got!r}, want {want!r}")
def fresh():
    w.disarm(); clock[0] = 10_000.0
A = "a@example.com"

fresh()
check("a lone 99% reading arms and does not rotate at once", w.confirm_or_arm(A, "7d", 99.0, 5000), False)
clock[0] += 299
check("the same reading re-read before 5 minutes: still waiting", w.confirm_or_arm(A, "7d", 99.0, 5000), False)
clock[0] += 2
check("the same reading after 5 minutes, nothing contradicting: rotates", w.confirm_or_arm(A, "7d", 99.0, 5000), True)
check("and the gate is disarmed after it", os.path.exists(w.ARMED_FILE), False)

fresh()
w.confirm_or_arm(A, "7d", 99.0, 5000)
w.low_reading(5010)
clock[0] += 400
check("a contradicting low reading inside the window cancels the fallback", w.confirm_or_arm(A, "7d", 99.0, 5000), False)

fresh()
w.confirm_or_arm(A, "5h", 96.0, 5000)
clock[0] += 400
check("a lone reading under 98% keeps waiting for a second one", w.confirm_or_arm(A, "5h", 96.0, 5000), False)

fresh()
w.confirm_or_arm(A, "7d", 99.0, 5000)
check("CONTROL: a second distinct reading 30 s later confirms the normal way", w.confirm_or_arm(A, "7d", 99.0, 5031), True)

print(f"\n-- {P} passed, {F} failed --")
sys.exit(1 if F else 0)
PY
